"""Alert and notification schemas."""
from __future__ import annotations
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime
import uuid


class AlertType(str, Enum):
    COLLISION_OVERRIDE = "collision_override"
    HAZARD_WARNING     = "hazard_warning"
    SOS_TRIGGERED      = "sos_triggered"
    SOS_RESOLVED       = "sos_resolved"
    SAFE_ZONE_EXIT     = "safe_zone_exit"
    SAFE_ZONE_ENTER    = "safe_zone_enter"
    LOW_BATTERY        = "low_battery"
    GPS_LOST           = "gps_lost"
    SESSION_STARTED    = "session_started"
    SESSION_ENDED      = "session_ended"


class AlertSeverity(str, Enum):
    INFO     = "info"
    WARNING  = "warning"
    DANGER   = "danger"
    CRITICAL = "critical"


class NotificationChannel(str, Enum):
    PUSH      = "push"
    SMS       = "sms"
    WHATSAPP  = "whatsapp"
    EMAIL     = "email"
    IN_APP    = "in_app"


class Alert(BaseModel):
    alert_id:       str          = Field(default_factory=lambda: uuid.uuid4().hex)
    user_id:        str
    session_id:     Optional[str] = None
    alert_type:     AlertType
    severity:       AlertSeverity
    title:          str
    body:           str          = Field(..., description="Plain-language description")
    location_lat:   Optional[float] = None
    location_lng:   Optional[float] = None
    location_label: Optional[str]   = None
    pc_at_trigger:  Optional[float] = Field(None, ge=0.0, le=1.0)
    guardian_notified: bool      = False
    channels_used:  list[NotificationChannel] = Field(default_factory=list)
    resolved:       bool         = False
    resolved_at:    Optional[datetime] = None
    user_response:  Optional[str]      = None    # "resumed_normally", "called_guardian", etc.
    created_at:     datetime     = Field(default_factory=datetime.utcnow)

    model_config = {"extra": "forbid"}


class AlertCreateRequest(BaseModel):
    user_id:     str
    session_id:  Optional[str] = None
    alert_type:  AlertType
    severity:    AlertSeverity
    title:       str
    body:        str
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None
    pc_at_trigger: Optional[float] = None
    notify_guardian: bool = True
    channels:    list[NotificationChannel] = [NotificationChannel.PUSH]

    model_config = {"extra": "forbid"}


class AlertResolveRequest(BaseModel):
    resolved_by:   str   # "user" | "guardian" | "auto"
    user_response: Optional[str] = None

    model_config = {"extra": "forbid"}
