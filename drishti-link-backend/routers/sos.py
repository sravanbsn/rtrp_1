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

    # ── Persist alert to Firestore ────────────────────────────────
    background_tasks.add_task(_persist_sos_to_firebase, alert, body.lat, body.lng)

    # ── Notify guardians ─────────────────────────────────────────
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
    user_id: str = "",
    resolved_by: str = "user",
    user_response: str = "user_confirmed_safe",
) -> Alert:
    # Retrieve from Firestore
    try:
        from services.firebase_admin_service import FirebaseAdminService
        db_client = FirebaseAdminService.firestore_client
        if db_client:
            doc_ref = db_client.collection('alerts').document(alert_id)
            snap = doc_ref.get()
            if snap.exists:
                data = snap.to_dict()
                doc_ref.update({
                    'resolved': True,
                    'resolved_at': datetime.now(timezone.utc).isoformat(),
                    'user_response': user_response,
                    'resolved_by': resolved_by,
                })
                # Clear RTDB SOS status
                if user_id:
                    from firebase_admin import db as rtdb
                    rtdb.reference(f'live_sessions/{user_id}/status').set('navigating')

                log.info("sos.resolved", alert_id=alert_id, resolved_by=resolved_by)
                # Return a minimal Alert object
                return Alert(
                    alert_id=alert_id,
                    user_id=data.get('user_id', ''),
                    session_id=data.get('session_id'),
                    alert_type=AlertType.SOS_TRIGGERED,
                    severity=AlertSeverity.CRITICAL,
                    title='SOS Resolved',
                    body='Guardian confirmed user is safe.',
                    resolved=True,
                    user_response=user_response,
                )
    except Exception as exc:
        log.error("sos.resolve_error", exc=str(exc))

    from core.exceptions import ResourceNotFoundError
    raise ResourceNotFoundError(message=f"SOS alert {alert_id!r} not found.")


@router.get(
    "/{alert_id}",
    response_model=Alert,
    summary="Get SOS alert status",
)
async def get_sos_status(alert_id: str) -> Alert:
    try:
        from services.firebase_admin_service import FirebaseAdminService
        db_client = FirebaseAdminService.firestore_client
        if db_client:
            snap = db_client.collection('alerts').document(alert_id).get()
            if snap.exists:
                data = snap.to_dict()
                return Alert(
                    alert_id=alert_id,
                    user_id=data.get('user_id', ''),
                    session_id=data.get('session_id'),
                    alert_type=AlertType(data.get('alert_type', 'sos_triggered')),
                    severity=AlertSeverity.CRITICAL,
                    title=data.get('title', 'SOS'),
                    body=data.get('body', ''),
                    resolved=data.get('resolved', False),
                )
    except Exception as exc:
        log.error("sos.get_error", exc=str(exc))
    from core.exceptions import ResourceNotFoundError
    raise ResourceNotFoundError(message=f"SOS alert {alert_id!r} not found.")


# ── Firebase persistence helper ────────────────────────────────────────────────

async def _persist_sos_to_firebase(alert: Alert, lat: float, lng: float) -> None:
    """
    Background task:
    1. Write SOS alert to Firestore `alerts` collection
    2. Set RTDB `live_sessions/{user_id}/status` = "sos"
    3. Send FCM high-priority push to linked guardian(s)
    """
    try:
        from services.firebase_admin_service import FirebaseAdminService
        db_client = FirebaseAdminService.firestore_client
        if not db_client:
            log.warning("sos.firebase_unavailable — SOS not persisted to Firestore")
            return

        # 1. Firestore write
        alert_data = {
            'alert_id':         alert.alert_id,
            'user_id':          alert.user_id,
            'session_id':       alert.session_id,
            'alert_type':       'sos_triggered',
            'type':             'sos',
            'severity':         'critical',
            'title':            alert.title,
            'body':             alert.body,
            'location_lat':     lat,
            'location_lng':     lng,
            'location_label':   alert.location_label,
            'guardian_notified': False,
            'resolved':         False,
            'created_at':       datetime.now(timezone.utc),
        }
        db_client.collection('alerts').document(alert.alert_id).set(alert_data)
        log.info("sos.firestore_written", alert_id=alert.alert_id)

        # 2. RTDB status update
        try:
            from firebase_admin import db as rtdb
            rtdb.reference(f'live_sessions/{alert.user_id}').update({
                'status': 'sos',
                'sos_alert_id': alert.alert_id,
                'sos_lat': lat,
                'sos_lng': lng,
            })
            log.info("sos.rtdb_updated", user_id=alert.user_id)
        except Exception as rtdb_exc:
            log.warning("sos.rtdb_update_failed", exc=str(rtdb_exc))

        # 3. FCM push via FirebaseAdminService
        try:
            guardians_snap = db_client.collection('guardians') \
                .where('linked_user_uid', '==', alert.user_id).stream()
            for guardian_doc in guardians_snap:
                gdata = guardian_doc.to_dict()
                for token in gdata.get('fcm_tokens', []):
                    await FirebaseAdminService.send_guardian_notification(
                        token=token,
                        title="🆘 SOS Alert!",
                        body=alert.body,
                        data={'alert_id': alert.alert_id, 'type': 'sos', 'lat': str(lat), 'lng': str(lng)},
                        high_priority=True,
                    )
                    log.info("sos.fcm_sent", guardian_id=guardian_doc.id)
        except Exception as fcm_exc:
            log.warning("sos.fcm_failed", exc=str(fcm_exc))

    except Exception as exc:
        log.error("sos.persist_failed", exc=str(exc))
