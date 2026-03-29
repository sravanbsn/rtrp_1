"""Navigation session schemas."""
from __future__ import annotations
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime
import uuid


class SessionStatus(str, Enum):
    ACTIVE    = "active"
    PAUSED    = "paused"
    COMPLETED = "completed"
    ABORTED   = "aborted"


class GeoPoint(BaseModel):
    lat: float = Field(..., ge=-90.0,  le=90.0)
    lng: float = Field(..., ge=-180.0, le=180.0)
    accuracy_m: Optional[float] = None
    altitude_m: Optional[float] = None
    recorded_at: datetime = Field(default_factory=datetime.utcnow)

    model_config = {"extra": "forbid"}


class SessionStartRequest(BaseModel):
    user_id:        str
    start_location: GeoPoint
    destination:    Optional[GeoPoint] = None
    route_id:       Optional[str]      = None   # pre-saved route
    guardian_ids:   list[str]          = Field(default_factory=list)

    model_config = {"extra": "forbid"}


class SessionUpdateRequest(BaseModel):
    current_location: GeoPoint
    speed_mps:        Optional[float] = None
    heading_degrees:  Optional[float] = Field(None, ge=0, le=360)

    model_config = {"extra": "forbid"}


class NavigationSession(BaseModel):
    session_id:     str       = Field(default_factory=lambda: uuid.uuid4().hex)
    user_id:        str
    status:         SessionStatus = SessionStatus.ACTIVE
    start_location: GeoPoint
    destination:    Optional[GeoPoint] = None
    current_location: Optional[GeoPoint] = None
    route_id:       Optional[str] = None
    guardian_ids:   list[str]    = Field(default_factory=list)

    # Metrics accumulated during session
    distance_covered_m:  float = 0.0
    total_overrides:     int   = 0
    total_warnings:      int   = 0
    hazards_avoided:     int   = 0
    max_pc_encountered:  float = 0.0

    started_at:   datetime           = Field(default_factory=datetime.utcnow)
    ended_at:     Optional[datetime] = None
    waypoints:    list[GeoPoint]     = Field(default_factory=list)

    model_config = {"extra": "forbid", "use_enum_values": True}


class SessionSummary(BaseModel):
    """Compact summary returned on session end."""
    session_id:         str
    duration_minutes:   float
    distance_covered_m: float
    total_overrides:    int
    total_warnings:     int
    hazards_avoided:    int
    max_pc_encountered: float
    ended_at:           datetime

    model_config = {"extra": "forbid"}
