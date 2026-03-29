"""Per-user adaptive profile schemas."""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime


class WalkingPattern(BaseModel):
    avg_speed_mps:           float = 0.8
    typical_route_ids:       list[str] = Field(default_factory=list)
    peak_hours:              list[int] = Field(default_factory=list)  # 0-23 hours
    avg_session_duration_min: float = 20.0

    model_config = {"extra": "forbid"}


class ThresholdProfile(BaseModel):
    """Per-user tuned collision thresholds (starts at global defaults)."""
    pc_override_threshold: float = Field(0.70, ge=0.10, le=0.95)
    pc_warning_threshold:  float = Field(0.40, ge=0.05, le=0.80)
    false_positive_rate:   float = 0.0   # track over time
    false_negative_rate:   float = 0.0
    samples_used:          int   = 0
    last_tuned_at:         Optional[datetime] = None

    model_config = {"extra": "forbid"}


class UserProfileCreate(BaseModel):
    user_id:        str
    name:           str
    phone:          str
    language:       str = "hindi"
    guardian_ids:   list[str] = Field(default_factory=list)
    home_lat:       Optional[float] = None
    home_lng:       Optional[float] = None

    model_config = {"extra": "forbid"}


class UserProfile(BaseModel):
    user_id:           str
    name:              str
    phone:             str
    language:          str = "hindi"
    guardian_ids:      list[str]         = Field(default_factory=list)
    home_lat:          Optional[float]   = None
    home_lng:          Optional[float]   = None
    threshold_profile: ThresholdProfile  = Field(default_factory=ThresholdProfile)
    walking_pattern:   WalkingPattern    = Field(default_factory=WalkingPattern)

    # Lifetime stats
    total_sessions:        int   = 0
    total_distance_m:      float = 0.0
    total_hazards_avoided: int   = 0
    total_overrides:       int   = 0

    created_at:  datetime  = Field(default_factory=datetime.utcnow)
    updated_at:  datetime  = Field(default_factory=datetime.utcnow)
    last_active: Optional[datetime] = None

    model_config = {"extra": "forbid", "from_attributes": True}
