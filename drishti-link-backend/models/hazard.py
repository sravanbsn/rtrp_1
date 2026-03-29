"""Hazard detection result schema."""
from __future__ import annotations
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field
import uuid
from datetime import datetime


class HazardType(str, Enum):
    VEHICLE        = "vehicle"
    PEDESTRIAN     = "pedestrian"
    POTHOLE        = "pothole"
    STEP_CURB      = "step_curb"
    CONSTRUCTION   = "construction"
    ANIMAL         = "animal"
    CROWD          = "crowd"
    WATER_PUDDLE   = "water_puddle"
    ELECTRIC_POLE  = "electric_pole"
    UNKNOWN        = "unknown"


class HazardSeverity(str, Enum):
    LOW      = "low"       # Pc < 0.40
    MEDIUM   = "medium"    # 0.40 <= Pc < 0.70
    HIGH     = "high"      # Pc >= 0.70 (override)
    CRITICAL = "critical"  # SOS level


class BoundingBox(BaseModel):
    x1: float = Field(..., ge=0.0, le=1.0, description="Left (normalized)")
    y1: float = Field(..., ge=0.0, le=1.0, description="Top (normalized)")
    x2: float = Field(..., ge=0.0, le=1.0, description="Right (normalized)")
    y2: float = Field(..., ge=0.0, le=1.0, description="Bottom (normalized)")

    model_config = {"extra": "forbid"}

    @property
    def center_x(self) -> float:
        return (self.x1 + self.x2) / 2

    @property
    def center_y(self) -> float:
        return (self.y1 + self.y2) / 2

    @property
    def area(self) -> float:
        return (self.x2 - self.x1) * (self.y2 - self.y1)


class HazardDetection(BaseModel):
    """A single detected hazard from YOLO inference."""
    hazard_id:        str          = Field(default_factory=lambda: uuid.uuid4().hex[:8])
    hazard_type:      HazardType
    confidence:       float        = Field(..., ge=0.0, le=1.0)
    bounding_box:     BoundingBox
    estimated_distance_m: Optional[float] = Field(None, ge=0.0, description="Depth estimation in metres")
    estimated_velocity_mps: Optional[float] = Field(None, description="Object velocity (positive = approaching)")
    severity:         HazardSeverity
    collision_prob:   float        = Field(..., ge=0.0, le=1.0, description="Pc score")
    direction_hint:   Optional[str] = Field(None, description="e.g. 'left', 'right', 'straight'")
    plain_language:   str = Field(..., description="Human-readable description for TTS")
    detected_at:      datetime     = Field(default_factory=datetime.utcnow)

    model_config = {"extra": "forbid"}


class FrameAnalysisResult(BaseModel):
    """Complete result of analysing one camera frame."""
    frame_id:         str          = Field(default_factory=lambda: uuid.uuid4().hex)
    session_id:       str
    user_id:          str
    hazards:          list[HazardDetection] = []
    dominant_hazard:  Optional[HazardDetection] = None
    overall_pc:       float        = Field(0.0, ge=0.0, le=1.0)
    should_override:  bool         = False
    should_warn:      bool         = False
    haptic_pattern:   str          = "none"   # "none" | "mild" | "strong" | "sos"
    tts_message:      Optional[str] = None
    inference_ms:     float        = 0.0
    processed_at:     datetime     = Field(default_factory=datetime.utcnow)

    model_config = {"extra": "forbid"}
