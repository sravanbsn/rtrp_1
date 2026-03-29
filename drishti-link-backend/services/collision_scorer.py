"""
services/collision_scorer.py  (updated for new Detection dataclass)

Computes Pc (collision probability) from YOLOService Detection objects
and mediapipe MotionResult. Combines:

  proximity_score = f(distance_m)                   weight 0.40
  size_score      = f(bbox area in frame)            weight 0.25
  approach_score  = 1.0 if approaching else 0.0     weight 0.20
  type_weight     = per-hazard-type danger rating    weight 0.15

Final Pc = clip(weighted_sum, 0.0, 1.0)
"""

from __future__ import annotations

from typing import Optional

import structlog

from core.config import settings
from models.hazard import (
    BoundingBox as ModelBBox,
    HazardDetection,
    HazardSeverity,
    HazardType,
)
from services.yolo_service import Detection, MovementVector, ThreatCategory

log = structlog.get_logger(__name__)

# ── Danger weight per threat category ────────────────────────────────────────
CATEGORY_WEIGHT: dict[ThreatCategory, float] = {
    ThreatCategory.VEHICLE:  0.95,
    ThreatCategory.PERSON:   0.55,
    ThreatCategory.ANIMAL:   0.65,
    ThreatCategory.TERRAIN:  0.40,
    ThreatCategory.UNKNOWN:  0.50,
}

# Per-class fine-grained overrides (takes priority over category weight)
CLASS_WEIGHT: dict[str, float] = {
    "car":                  0.95,
    "truck":                0.98,
    "bus":                  0.97,
    "motorcycle":           0.90,
    "auto_rickshaw":        0.88,
    "bicycle":              0.70,
    "person":               0.55,
    "dog":                  0.60,
    "cow":                  0.75,
    "goat":                 0.50,
    "cat":                  0.35,
    "pothole":              0.45,
    "open_drain":           0.50,
    "speed_bump":           0.30,
    "construction_barrier": 0.55,
    "loose_wire":           0.60,
    "wet_floor":            0.25,
}

# Hinglish TTS templates {dir} and {dist} are formatted in
PLAIN_LANGUAGE: dict[ThreatCategory, str] = {
    ThreatCategory.VEHICLE:  "{dir} gaadi aa rahi hai — {dist}m pe",
    ThreatCategory.PERSON:   "{dir} koi insaan hai",
    ThreatCategory.ANIMAL:   "{dir} jaanwar hai",
    ThreatCategory.TERRAIN:  "{dist}m aage {cls} hai — savdhaan",
    ThreatCategory.UNKNOWN:  "Koi cheez hai — savdhaan rahein",
}


def _severity_from_pc(pc: float) -> HazardSeverity:
    if pc >= settings.DEFAULT_PC_THRESHOLD:
        return HazardSeverity.HIGH
    if pc >= settings.DEFAULT_WARNING_THRESHOLD:
        return HazardSeverity.MEDIUM
    return HazardSeverity.LOW


def _plain_language(det: Detection, pc: float) -> str:
    template = PLAIN_LANGUAGE.get(
        det.threat_category,
        PLAIN_LANGUAGE[ThreatCategory.UNKNOWN],
    )
    dist_str = f"{det.distance_meters:.0f}" if det.distance_meters else "?"
    return template.format(
        dir=det.position_in_frame.value,
        dist=dist_str,
        cls=det.class_name,
    )


class CollisionScorer:
    """
    Stateless scorer: takes YOLOService Detection list + optional MotionResult
    and returns fully scored HazardDetection objects (for models/hazard.py).
    """

    async def score_detections(
        self,
        detections:   list[Detection],
        depth_map:    Optional[dict] = None,    # kept for interface compat
        user_id:      Optional[str]  = None,
        motion_result: Optional[object] = None, # MediaPipe MotionResult
    ) -> list[HazardDetection]:
        """Convert Detection → HazardDetection with Pc score."""
        scored: list[HazardDetection] = []

        for det in detections:
            pc = self._compute_pc(det, motion_result)

            # Map to model BoundingBox (normalised 0-1)
            norm = det.bbox.norm(1, 1)  # already norm from scorer perspective
            model_bbox = ModelBBox(
                x1=det.bbox.x / 640,
                y1=det.bbox.y / 480,
                x2=(det.bbox.x + det.bbox.w) / 640,
                y2=(det.bbox.y + det.bbox.h) / 480,
            )

            # Map class → HazardType
            hazard_type = _class_to_hazard_type(det.class_name)

            scored.append(HazardDetection(
                hazard_type=hazard_type,
                confidence=det.confidence,
                bounding_box=model_bbox,
                estimated_distance_m=det.distance_meters,
                estimated_velocity_mps=None,
                severity=_severity_from_pc(pc),
                collision_prob=pc,
                direction_hint=det.position_in_frame.value,
                plain_language=_plain_language(det, pc),
            ))

        return sorted(scored, key=lambda h: h.collision_prob, reverse=True)

    def _compute_pc(
        self,
        det:           Detection,
        motion_result: Optional[object],
    ) -> float:
        # ── 1. Proximity score (from distance estimate) ────────────────────
        if det.distance_meters is not None and det.distance_meters > 0:
            proximity = 1.0 / (1.0 + det.distance_meters)
        else:
            # Fallback: use normalised bbox area
            frame_area = 640 * 480
            proximity = min(det.bbox.area / frame_area * 5.0, 1.0)

        # ── 2. Size score ─────────────────────────────────────────────────
        frame_area = 640 * 480
        size_score = min(det.bbox.area / (frame_area * 0.25), 1.0)

        # ── 3. Approach score ─────────────────────────────────────────────
        if det.movement_vector == MovementVector.APPROACHING:
            approach_score = 1.0
        elif det.movement_vector == MovementVector.STATIONARY:
            approach_score = 0.3
        else:
            approach_score = 0.0

        # ── 4. Type weight ────────────────────────────────────────────────
        type_w = CLASS_WEIGHT.get(
            det.class_name,
            CATEGORY_WEIGHT.get(det.threat_category, 0.5),
        )

        # ── 5. User motion modifier: moving toward hazard = +10% ──────────
        motion_factor = 1.0
        if motion_result is not None:
            vel = getattr(motion_result, "user_velocity_mps", 0.0)
            if vel > 0.8:  # walking briskly
                motion_factor = 1.10

        pc_raw = (
            proximity    * 0.40
            + size_score * 0.25
            + approach_score * 0.20
            + type_w     * 0.15
        ) * motion_factor

        return round(max(0.0, min(1.0, pc_raw)), 4)


# ── Class name → HazardType mapping ─────────────────────────────────────────
_CLASS_TO_HAZARD: dict[str, HazardType] = {
    "car":                  HazardType.VEHICLE,
    "truck":                HazardType.VEHICLE,
    "bus":                  HazardType.VEHICLE,
    "motorcycle":           HazardType.VEHICLE,
    "auto_rickshaw":        HazardType.VEHICLE,
    "bicycle":              HazardType.VEHICLE,
    "person":               HazardType.PEDESTRIAN,
    "dog":                  HazardType.ANIMAL,
    "cow":                  HazardType.ANIMAL,
    "cat":                  HazardType.ANIMAL,
    "goat":                 HazardType.ANIMAL,
    "pothole":              HazardType.POTHOLE,
    "open_drain":           HazardType.POTHOLE,
    "speed_bump":           HazardType.STEP_CURB,
    "construction_barrier": HazardType.CONSTRUCTION,
    "loose_wire":           HazardType.ELECTRIC_POLE,
    "wet_floor":            HazardType.WATER_PUDDLE,
}


def _class_to_hazard_type(class_name: str) -> HazardType:
    return _CLASS_TO_HAZARD.get(class_name, HazardType.UNKNOWN)
