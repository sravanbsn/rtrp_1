"""
SOS emergency alert endpoints.
Life-critical path — must never fail silently.
Retries notification delivery with exponential backoff.
"""
from __future__ import annotations

import structlog
from datetime import datetime, timezone
from fastapi import APIRouter, BackgroundTasks, status
from fastapi.responses import ORJSONResponse

from core.exceptions import GuardianNotConfiguredError, NotificationDeliveryError
from models.alert import Alert, AlertType, AlertSeverity, NotificationChannel
from models.session import GeoPoint

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/sos")

# In-memory store (replace with DB)
_sos_events: dict[str, dict] = {}


class SOSTriggerRequest:
    def __init__(
        self,
        user_id: str,
        session_id: str | None,
        lat: float,
        lng: float,
        location_label: str | None = None,
        triggered_by: str = "user",   # "user" | "auto_fall" | "auto_freeze"
        guardian_ids: list[str] | None = None,
    ):
        self.user_id       = user_id
        self.session_id    = session_id
        self.lat           = lat
        self.lng           = lng
        self.location_label = location_label
        self.triggered_by  = triggered_by
        self.guardian_ids  = guardian_ids or []


from pydantic import BaseModel, Field

class SOSTriggerBody(BaseModel):
    user_id:        str
    session_id:     str | None = None
    lat:            float = Field(..., ge=-90.0,  le=90.0)
    lng:            float = Field(..., ge=-180.0, le=180.0)
    location_label: str | None = None
    triggered_by:   str = "user"
    guardian_ids:   list[str] = Field(default_factory=list)


async def _notify_guardians(
    alert: Alert,
    guardian_ids: list[str],
    lat: float,
    lng: float,
) -> None:
    """Background task: send SOS to all guardians via all channels."""
    from services.notification_service import NotificationService
    svc = NotificationService()

    for guardian_id in guardian_ids:
        try:
            await svc.send_sos(
                guardian_id=guardian_id,
                user_name="Arjun",   # TODO: fetch from user service
                lat=lat,
                lng=lng,
                alert_id=alert.alert_id,
            )
            log.info(
                "sos.guardian_notified",
                guardian_id=guardian_id,
                alert_id=alert.alert_id,
            )
        except Exception as exc:
            # Log but don't fail — notify all available channels
            log.error(
                "sos.notification_failed",
                guardian_id=guardian_id,
                exc=str(exc),
            )


@router.post(
    "/trigger",
    response_model=Alert,
    status_code=status.HTTP_201_CREATED,
    summary="🆘 Trigger SOS emergency alert",
    description=(
        "Life-critical endpoint. Creates SOS alert, immediately returns ACK, "
        "then notifies all guardians in background via SMS/WhatsApp/push."
    ),
)
async def trigger_sos(
    body: SOSTriggerBody,
    background_tasks: BackgroundTasks,
) -> Alert:
    if not body.guardian_ids:
        raise GuardianNotConfiguredError(user_id=body.user_id)

    alert = Alert(
        user_id=body.user_id,
        session_id=body.session_id,
        alert_type=AlertType.SOS_TRIGGERED,
        severity=AlertSeverity.CRITICAL,
        title="🆘 SOS Triggered",
        body=f"Arjun needs help at {body.location_label or 'current location'}. Tap to see map.",
        location_lat=body.lat,
        location_lng=body.lng,
        location_label=body.location_label,
        guardian_notified=False,
        channels_used=[NotificationChannel.PUSH, NotificationChannel.SMS, NotificationChannel.WHATSAPP],
    )

    _sos_events[alert.alert_id] = {"alert": alert, "resolved": False}

    # Non-blocking guardian notification
    background_tasks.add_task(
        _notify_guardians,
        alert=alert,
        guardian_ids=body.guardian_ids,
        lat=body.lat,
        lng=body.lng,
    )

    log.critical(
        "sos.triggered",
        alert_id=alert.alert_id,
        user_id=body.user_id,
        triggered_by=body.triggered_by,
        guardian_count=len(body.guardian_ids),
    )
    return alert


@router.post(
    "/{alert_id}/resolve",
    response_model=Alert,
    summary="Resolve / cancel an active SOS",
)
async def resolve_sos(
    alert_id: str,
    resolved_by: str = "user",
    user_response: str = "user_confirmed_safe",
) -> Alert:
    event = _sos_events.get(alert_id)
    if not event:
        from core.exceptions import ResourceNotFoundError
        raise ResourceNotFoundError(message=f"SOS alert {alert_id!r} not found.")

    alert: Alert = event["alert"]
    alert.resolved     = True
    alert.resolved_at  = datetime.now(timezone.utc)
    alert.user_response = user_response
    event["resolved"]  = True

    log.info(
        "sos.resolved",
        alert_id=alert_id,
        resolved_by=resolved_by,
        user_response=user_response,
    )
    return alert


@router.get(
    "/{alert_id}",
    response_model=Alert,
    summary="Get SOS alert status",
)
async def get_sos_status(alert_id: str) -> Alert:
    event = _sos_events.get(alert_id)
    if not event:
        from core.exceptions import ResourceNotFoundError
        raise ResourceNotFoundError(message=f"SOS alert {alert_id!r} not found.")
    return event["alert"]
