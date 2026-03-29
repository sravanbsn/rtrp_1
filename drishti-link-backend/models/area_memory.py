"""Local area hazard memory schemas."""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime
import uuid


class AreaHazardRecord(BaseModel):
    """A recurring hazard observed at a specific geographic area."""
    record_id:       str   = Field(default_factory=lambda: uuid.uuid4().hex)
    area_id:         str   = Field(..., description="Geohash or grid cell ID")
    hazard_type:     str
    lat:             float = Field(..., ge=-90.0,  le=90.0)
    lng:             float = Field(..., ge=-180.0, le=180.0)
    radius_m:        float = Field(10.0, ge=1.0, le=500.0)

    # Frequency and recency scoring
    observation_count: int   = 1
    avg_pc_score:      float = Field(0.0, ge=0.0, le=1.0)
    last_observed_at:  datetime = Field(default_factory=datetime.utcnow)
    first_observed_at: datetime = Field(default_factory=datetime.utcnow)

    # Time-of-day pattern (which hours this hazard is most frequent)
    peak_hours:        list[int] = Field(default_factory=list)

    # Confidence increases with observation_count
    confidence_score:  float = Field(0.1, ge=0.0, le=1.0)
    active:            bool  = True
    plain_language:    str   = ""

    model_config = {"extra": "forbid"}


class AreaMemoryQuery(BaseModel):
    lat:       float = Field(..., ge=-90.0,  le=90.0)
    lng:       float = Field(..., ge=-180.0, le=180.0)
    radius_m:  float = Field(100.0, ge=10.0, le=2000.0)
    min_confidence: float = Field(0.3, ge=0.0, le=1.0)
    limit:     int   = Field(10, ge=1, le=50)

    model_config = {"extra": "forbid"}


class AreaMemoryUpdateRequest(BaseModel):
    area_id:   str
    hazard_type: str
    lat:       float
    lng:       float
    pc_score:  float = Field(..., ge=0.0, le=1.0)
    hour_of_day: int = Field(..., ge=0, le=23)

    model_config = {"extra": "forbid"}
