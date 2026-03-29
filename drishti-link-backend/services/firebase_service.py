"""Firebase real-time sync service."""
from __future__ import annotations
import structlog
from core.config import settings

log = structlog.get_logger(__name__)

_firebase_initialized = False


def _init_firebase() -> bool:
    global _firebase_initialized
    if _firebase_initialized:
        return True
    if not settings.FIREBASE_PROJECT_ID:
        log.warning("firebase.not_configured")
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred, {
            "storageBucket": settings.FIREBASE_STORAGE_BUCKET,
        })
        _firebase_initialized = True
        log.info("firebase.initialized", project=settings.FIREBASE_PROJECT_ID)
        return True
    except Exception as exc:
        log.error("firebase.init_failed", exc=str(exc))
        return False


class FirebaseService:
    """Sync navigation events and alerts to Firebase Realtime DB / Firestore."""

    def __init__(self) -> None:
        self._ready = _init_firebase()

    async def push_location(self, user_id: str, lat: float, lng: float, accuracy: float = 0.0) -> None:
        if not self._ready:
            return
        try:
            from firebase_admin import db
            ref = db.reference(f"users/{user_id}/location")
            ref.set({"lat": lat, "lng": lng, "accuracy": accuracy})
        except Exception as exc:
            log.error("firebase.push_location_failed", user_id=user_id, exc=str(exc))

    async def push_alert(self, user_id: str, alert_id: str, payload: dict) -> None:
        if not self._ready:
            return
        try:
            from firebase_admin import db
            ref = db.reference(f"users/{user_id}/alerts/{alert_id}")
            ref.set(payload)
            log.info("firebase.alert_pushed", alert_id=alert_id)
        except Exception as exc:
            log.error("firebase.push_alert_failed", alert_id=alert_id, exc=str(exc))

    async def update_session_status(self, user_id: str, session_id: str, status: str) -> None:
        if not self._ready:
            return
        try:
            from firebase_admin import db
            ref = db.reference(f"users/{user_id}/active_session")
            ref.update({"session_id": session_id, "status": status})
        except Exception as exc:
            log.error("firebase.session_update_failed", exc=str(exc))
