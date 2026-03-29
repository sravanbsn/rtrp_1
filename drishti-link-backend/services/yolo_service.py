"""
services/yolo_service.py

Production YOLOv8 detection service — Drishti-Link.

Design goals:
  ● Model loaded ONCE at startup via lifespan; zero per-request overhead
  ● CPU-bound inference runs in ThreadPoolExecutor — never blocks event loop
  ● Frame-skip logic: every 3rd frame normally; every frame when Pc > 0.60
  ● Night mode: auto CLAHE equalisation after 7 PM IST
  ● Per-detection: class, confidence, bbox, distance_m, position, movement, threat
  ● Target P95 latency: < 80 ms on CPU (< 20 ms on GPU)
"""

from __future__ import annotations

import asyncio
import base64
import io
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Optional

import cv2
import numpy as np
import structlog
from PIL import Image

from core.config import settings

log = structlog.get_logger(__name__)

# ── Thread pool for CPU-bound inference ──────────────────────────────────────
_INFERENCE_POOL = ThreadPoolExecutor(max_workers=2, thread_name_prefix="yolo-inf")

# ── Input resolution ─────────────────────────────────────────────────────────
INPUT_SIZE = 640   # YOLOv8 expects square input

# ── Night mode threshold (IST hour, 24h) ─────────────────────────────────────
NIGHT_HOUR_START = 19   # 7 PM
NIGHT_HOUR_END   = 6    # 6 AM

# ── Frame-skip configuration ─────────────────────────────────────────────────
NORMAL_SKIP      = 3    # process 1-in-3 frames at normal Pc
HIGH_PC_SKIP     = 1    # process every frame when Pc ≥ HIGH_PC_THRESHOLD
HIGH_PC_THRESHOLD = 0.60

# ═════════════════════════════════════════════════════════════════════════════
# Detection class definitions — COCO + Indian street custom classes
# ═════════════════════════════════════════════════════════════════════════════

class ThreatCategory(str, Enum):
    VEHICLE  = "vehicle"
    ANIMAL   = "animal"
    TERRAIN  = "terrain"
    PERSON   = "person"
    UNKNOWN  = "unknown"


class MovementVector(str, Enum):
    APPROACHING = "approaching"
    STATIONARY  = "stationary"
    RECEDING    = "receding"
    UNKNOWN     = "unknown"


class FramePosition(str, Enum):
    LEFT   = "left"
    CENTER = "center"
    RIGHT  = "right"


# Maps YOLO class_id → (display_name, ThreatCategory)
# Standard COCO classes + custom Indian street classes (80+)
CLASS_REGISTRY: dict[int, tuple[str, ThreatCategory]] = {
    # ── Persons ──────────────────────────────────────────────────────────────
    0:  ("person",              ThreatCategory.PERSON),
    # ── Vehicles (COCO) ──────────────────────────────────────────────────────
    1:  ("bicycle",             ThreatCategory.VEHICLE),
    2:  ("car",                 ThreatCategory.VEHICLE),
    3:  ("motorcycle",          ThreatCategory.VEHICLE),
    5:  ("bus",                 ThreatCategory.VEHICLE),
    7:  ("truck",               ThreatCategory.VEHICLE),
    # ── Animals ──────────────────────────────────────────────────────────────
    15: ("cat",                 ThreatCategory.ANIMAL),
    16: ("dog",                 ThreatCategory.ANIMAL),
    19: ("cow",                 ThreatCategory.ANIMAL),
    # ── Custom Indian street classes (trained additions) ──────────────────────
    80: ("auto_rickshaw",       ThreatCategory.VEHICLE),
    81: ("pothole",             ThreatCategory.TERRAIN),
    82: ("open_drain",          ThreatCategory.TERRAIN),
    83: ("speed_bump",          ThreatCategory.TERRAIN),
    84: ("construction_barrier",ThreatCategory.TERRAIN),
    85: ("loose_wire",          ThreatCategory.TERRAIN),
    86: ("wet_floor",           ThreatCategory.TERRAIN),
    87: ("goat",                ThreatCategory.ANIMAL),
}

# Classes we actively care about (filter out irrelevant COCO classes)
RELEVANT_CLASS_IDS: frozenset[int] = frozenset(CLASS_REGISTRY.keys())

# Approximate real-world heights (metres) for distance estimation via pinhole model
REAL_HEIGHT_M: dict[str, float] = {
    "person":               1.70,
    "car":                  1.50,
    "motorcycle":           1.20,
    "auto_rickshaw":        1.80,
    "bus":                  3.00,
    "truck":                3.50,
    "bicycle":              1.00,
    "cow":                  1.40,
    "dog":                  0.50,
    "cat":                  0.30,
    "goat":                 0.60,
    "pothole":              0.10,
    "speed_bump":           0.15,
    "construction_barrier": 1.20,
}
DEFAULT_REAL_HEIGHT_M = 1.0

# Focal length in pixels (calibrated for typical mobile camera @ 640px)
FOCAL_LENGTH_PX = 600.0


# ═════════════════════════════════════════════════════════════════════════════
# Data types
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class BBox:
    """Bounding box in pixel coordinates."""
    x: int   # top-left x
    y: int   # top-left y
    w: int   # width
    h: int   # height

    @property
    def center_x(self) -> float:
        return self.x + self.w / 2

    @property
    def center_y(self) -> float:
        return self.y + self.h / 2

    @property
    def area(self) -> int:
        return self.w * self.h

    def norm(self, frame_w: int, frame_h: int) -> dict:
        """Return normalized (0-1) coordinates."""
        return {
            "x": self.x / frame_w,
            "y": self.y / frame_h,
            "w": self.w / frame_w,
            "h": self.h / frame_h,
        }


@dataclass
class Detection:
    """A single object detection result."""
    class_id:          int
    class_name:        str
    confidence:        float
    bbox:              BBox
    distance_meters:   Optional[float]
    position_in_frame: FramePosition
    movement_vector:   MovementVector
    threat_category:   ThreatCategory

    def to_dict(self, frame_w: int = INPUT_SIZE, frame_h: int = INPUT_SIZE) -> dict:
        return {
            "class_name":        self.class_name,
            "confidence":        round(self.confidence, 4),
            "bbox":              self.bbox.norm(frame_w, frame_h),
            "distance_meters":   round(self.distance_meters, 2) if self.distance_meters else None,
            "position_in_frame": self.position_in_frame.value,
            "movement_vector":   self.movement_vector.value,
            "threat_category":   self.threat_category.value,
        }


@dataclass
class FrameResult:
    """Full result for one processed frame."""
    frame_id:         str
    session_id:       str
    detections:       list[Detection]
    skipped:          bool              = False
    night_mode:       bool              = False
    preprocessing_ms: float            = 0.0
    inference_ms:     float            = 0.0
    total_ms:         float            = 0.0
    frame_width:      int              = INPUT_SIZE
    frame_height:     int              = INPUT_SIZE

    @property
    def highest_threat(self) -> Optional[Detection]:
        return self.detections[0] if self.detections else None


# ═════════════════════════════════════════════════════════════════════════════
# Per-session tracking state
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class SessionTrack:
    """Tracks frame-skip counter and bbox history per session."""
    frame_counter:  int = 0
    current_pc:     float = 0.0
    # Deque of {class_id: BBox} from last N frames (for movement vector)
    bbox_history:   deque = field(default_factory=lambda: deque(maxlen=5))

    def should_process(self) -> bool:
        skip = HIGH_PC_SKIP if self.current_pc >= HIGH_PC_THRESHOLD else NORMAL_SKIP
        self.frame_counter += 1
        return (self.frame_counter % skip) == 0

    def record_bboxes(self, detections: list[Detection]) -> None:
        snapshot = {d.class_id: d.bbox for d in detections}
        self.bbox_history.append(snapshot)


# ═════════════════════════════════════════════════════════════════════════════
# YOLOService — main service class
# ═════════════════════════════════════════════════════════════════════════════

class YOLOService:
    """
    YOLOv8 inference service.
    Instantiate once at startup (app.state.yolo = YOLOService()).
    Call await yolo.load() during lifespan.
    """

    def __init__(self) -> None:
        self._model: Any           = None
        self._is_ready: bool       = False
        self._model_path: str      = settings.YOLO_MODEL_PATH
        self._session_tracks: dict[str, SessionTrack] = {}

    # ── Properties ───────────────────────────────────────────────────────────
    @property
    def is_ready(self) -> bool:
        return self._is_ready

    # ── Startup ──────────────────────────────────────────────────────────────
    def load_sync(self, path: Optional[str] = None) -> None:
        """Blocking model load — called once from thread pool at startup."""
        try:
            from ultralytics import YOLO
            
            if path is None:
                path_obj = Path(self._model_path)
            else:
                path_obj = Path(path)

            if not path_obj.exists():
                log.warning(
                    "yolo.weights_missing",
                    path=str(path_obj),
                    fallback="yolov8n.pt",
                )
                path = Path("yolov8n.pt")

            self._model = YOLO(str(path_obj))
            # Bake hyperparameters so they never need passing per-call
            self._model.overrides.update({
                "conf":  settings.YOLO_CONFIDENCE,
                "iou":   settings.YOLO_IOU,
                "imgsz": INPUT_SIZE,
                "verbose": False,
            })
            self._is_ready = True
            log.info("yolo.loaded", path=str(path_obj))

        except Exception as exc:
            log.error("yolo.load_failed", exc=str(exc))
            self._is_ready = False
            raise

    async def load(self, path: Optional[str] = None) -> None:
        """Async wrapper — await this from FastAPI lifespan."""
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(_INFERENCE_POOL, self.load_sync, path)

    # ── Public API ────────────────────────────────────────────────────────────
    async def detect_bytes(
        self,
        frame_bytes: bytes,
        session_id:  str,
        frame_id:    str,
        current_pc:  float = 0.0,
    ) -> FrameResult:
        """
        Main entry point: raw bytes (JPEG/PNG/WebP).
        Handles frame-skip, night-mode, preprocessing, inference.
        """
        if not self._is_ready:
            from core.exceptions import ModelNotLoadedError
            raise ModelNotLoadedError()

        # ── Frame-skip check ─────────────────────────────────────────────
        track = self._get_track(session_id, current_pc)
        if not track.should_process():
            return FrameResult(
                frame_id=frame_id,
                session_id=session_id,
                detections=[],
                skipped=True,
            )

        t_total = time.perf_counter()

        # ── Decode ───────────────────────────────────────────────────────
        try:
            img_bgr = _decode_frame(frame_bytes)
        except Exception as exc:
            from core.exceptions import InvalidFrameError
            raise InvalidFrameError(message=f"Frame decode error: {exc}")

        orig_h, orig_w = img_bgr.shape[:2]

        # ── Night mode preprocessing ──────────────────────────────────────
        night = _is_night_mode()
        t_pre = time.perf_counter()
        img_bgr = _preprocess(img_bgr, night_mode=night)
        pre_ms = (time.perf_counter() - t_pre) * 1000

        # ── Inference (thread pool) ───────────────────────────────────────
        loop = asyncio.get_running_loop()
        t_inf = time.perf_counter()
        raw_results = await loop.run_in_executor(
            _INFERENCE_POOL,
            self._infer_sync,
            img_bgr,
        )
        inf_ms = (time.perf_counter() - t_inf) * 1000

        # ── Post-process ─────────────────────────────────────────────────
        detections = self._post_process(raw_results, track, orig_w, orig_h)
        track.record_bboxes(detections)

        total_ms = (time.perf_counter() - t_total) * 1000

        log.debug(
            "yolo.frame_processed",
            session_id=session_id,
            frame_id=frame_id,
            count=len(detections),
            night_mode=night,
            pre_ms=round(pre_ms, 1),
            inf_ms=round(inf_ms, 1),
            total_ms=round(total_ms, 1),
        )

        if total_ms > 80:
            log.warning("yolo.slow_frame", total_ms=round(total_ms, 1), session_id=session_id)

        return FrameResult(
            frame_id=frame_id,
            session_id=session_id,
            detections=detections,
            skipped=False,
            night_mode=night,
            preprocessing_ms=round(pre_ms, 2),
            inference_ms=round(inf_ms, 2),
            total_ms=round(total_ms, 2),
            frame_width=orig_w,
            frame_height=orig_h,
        )

    async def detect_base64(
        self,
        b64_frame:  str,
        session_id: str,
        frame_id:   str,
        current_pc: float = 0.0,
    ) -> FrameResult:
        """Entry point for base64-encoded frames (WebSocket / Flutter)."""
        try:
            frame_bytes = base64.b64decode(b64_frame)
        except Exception as exc:
            from core.exceptions import InvalidFrameError
            raise InvalidFrameError(message=f"Invalid base64 data: {exc}")
        return await self.detect_bytes(frame_bytes, session_id, frame_id, current_pc)

    def update_pc(self, session_id: str, pc: float) -> None:
        """Update current Pc score for a session (controls frame-skip rate)."""
        track = self._session_tracks.get(session_id)
        if track:
            track.current_pc = pc

    def cleanup_session(self, session_id: str) -> None:
        self._session_tracks.pop(session_id, None)

    # ── Internal ─────────────────────────────────────────────────────────────
    def _get_track(self, session_id: str, current_pc: float) -> SessionTrack:
        if session_id not in self._session_tracks:
            self._session_tracks[session_id] = SessionTrack()
        track = self._session_tracks[session_id]
        track.current_pc = current_pc
        return track

    def _infer_sync(self, img_bgr: np.ndarray) -> list:
        """Pure sync inference — runs in thread pool."""
        results = self._model.predict(img_bgr, stream=False)
        return results

    def _post_process(
        self,
        raw_results: list,
        track:       SessionTrack,
        orig_w:      int,
        orig_h:      int,
    ) -> list[Detection]:
        detections: list[Detection] = []

        for result in raw_results:
            if result.boxes is None:
                continue

            for box in result.boxes:
                class_id   = int(box.cls[0])
                confidence = float(box.conf[0])

                # Filter to relevant classes only
                if class_id not in RELEVANT_CLASS_IDS:
                    continue

                class_name, threat_cat = CLASS_REGISTRY[class_id]

                # bbox in pixel coords (xyxy → xywh)
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                bbox = BBox(
                    x=int(x1), y=int(y1),
                    w=int(x2 - x1), h=int(y2 - y1),
                )

                distance_m = _estimate_distance(class_name, bbox.h, orig_h)
                position   = _frame_position(bbox.center_x, orig_w)
                movement   = _movement_vector(class_id, bbox, track)

                detections.append(Detection(
                    class_id=class_id,
                    class_name=class_name,
                    confidence=confidence,
                    bbox=bbox,
                    distance_meters=distance_m,
                    position_in_frame=position,
                    movement_vector=movement,
                    threat_category=threat_cat,
                ))

        # Sort by distance ascending (nearest threats first)
        detections.sort(
            key=lambda d: d.distance_meters if d.distance_meters else 999
        )
        return detections


# ═════════════════════════════════════════════════════════════════════════════
# Helper functions (pure, easily unit-testable)
# ═════════════════════════════════════════════════════════════════════════════

def _decode_frame(frame_bytes: bytes) -> np.ndarray:
    """Decode raw bytes (JPEG/PNG/WebP) to BGR numpy array."""
    arr = np.frombuffer(frame_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("cv2.imdecode returned None — likely corrupt or unsupported frame")
    return img


def _is_night_mode() -> bool:
    """Return True if current IST hour is in night range."""
    ist_hour = (datetime.now(timezone.utc).hour + 5) % 24  # approximate IST
    return ist_hour >= NIGHT_HOUR_START or ist_hour < NIGHT_HOUR_END


def _preprocess(img_bgr: np.ndarray, night_mode: bool = False) -> np.ndarray:
    """
    Preprocess frame for YOLO:
    1. Resize to INPUT_SIZE × INPUT_SIZE (letterbox preserving AR)
    2. Apply CLAHE if night mode
    3. Returns BGR numpy array
    """
    # ── Letterbox resize ─────────────────────────────────────────────────
    h, w = img_bgr.shape[:2]
    scale = INPUT_SIZE / max(h, w)
    new_w = int(w * scale)
    new_h = int(h * scale)
    resized = cv2.resize(img_bgr, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

    # Pad to square
    padded = np.zeros((INPUT_SIZE, INPUT_SIZE, 3), dtype=np.uint8)
    pad_top  = (INPUT_SIZE - new_h) // 2
    pad_left = (INPUT_SIZE - new_w) // 2
    padded[pad_top:pad_top + new_h, pad_left:pad_left + new_w] = resized

    # ── Night mode: CLAHE on luminance channel ────────────────────────────
    if night_mode:
        lab = cv2.cvtColor(padded, cv2.COLOR_BGR2LAB)
        l_ch, a_ch, b_ch = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        l_ch = clahe.apply(l_ch)
        padded = cv2.cvtColor(cv2.merge([l_ch, a_ch, b_ch]), cv2.COLOR_LAB2BGR)

    return padded


def _estimate_distance(
    class_name:   str,
    bbox_h_px:    int,
    frame_h_px:   int,
) -> Optional[float]:
    """
    Pinhole camera model:
      distance = (real_height × focal_length) / bbox_h_px
    Focal length calibrated for a mobile camera @ INPUT_SIZE resolution.
    """
    if bbox_h_px <= 0:
        return None
    real_h = REAL_HEIGHT_M.get(class_name, DEFAULT_REAL_HEIGHT_M)
    # Scale focal length to actual frame height
    focal = FOCAL_LENGTH_PX * (frame_h_px / INPUT_SIZE)
    distance = (real_h * focal) / bbox_h_px
    return round(max(0.1, min(distance, 50.0)), 2)   # clamp: 0.1m – 50m


def _frame_position(center_x_px: float, frame_w_px: int) -> FramePosition:
    """Classify horizontal object position into thirds of the frame."""
    ratio = center_x_px / max(frame_w_px, 1)
    if ratio < 0.33:
        return FramePosition.LEFT
    if ratio > 0.67:
        return FramePosition.RIGHT
    return FramePosition.CENTER


def _movement_vector(
    class_id: int,
    current_bbox: BBox,
    track: SessionTrack,
) -> MovementVector:
    """
    Estimate movement by comparing current bbox area to previous frame's.
    Larger area → approaching; Smaller → receding; Similar → stationary.
    Requires at least 2 frames of history.
    """
    if len(track.bbox_history) < 2:
        return MovementVector.UNKNOWN

    prev_snapshot = track.bbox_history[-2]
    prev_bbox = prev_snapshot.get(class_id)
    if prev_bbox is None:
        return MovementVector.UNKNOWN

    area_delta = current_bbox.area - prev_bbox.area
    # 5% change threshold to call it stationary
    threshold = prev_bbox.area * 0.05

    if area_delta > threshold:
        return MovementVector.APPROACHING
    if area_delta < -threshold:
        return MovementVector.RECEDING
    return MovementVector.STATIONARY
