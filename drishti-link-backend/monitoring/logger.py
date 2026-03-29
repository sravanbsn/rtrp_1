"""Structured event logger for domain-specific events."""
from __future__ import annotations
import structlog
from datetime import datetime, timezone

log = structlog.get_logger("drishti.events")


def log_override(user_id: str, session_id: str, pc: float, hazard: str, direction: str) -> None:
    log.warning(
        "event.override",
        user_id=user_id, session_id=session_id,
        pc=round(pc, 3), hazard=hazard, direction=direction,
        ts=datetime.now(timezone.utc).isoformat(),
    )


def log_sos(user_id: str, lat: float, lng: float, alert_id: str) -> None:
    log.critical(
        "event.sos",
        user_id=user_id, lat=lat, lng=lng, alert_id=alert_id,
        ts=datetime.now(timezone.utc).isoformat(),
    )


def log_session(user_id: str, session_id: str, event: str, **kwargs) -> None:
    log.info(
        f"event.session.{event}",
        user_id=user_id, session_id=session_id,
        ts=datetime.now(timezone.utc).isoformat(),
        **kwargs,
    )


def log_feedback(user_id: str, feedback_type: str, pc: float | None) -> None:
    log.info(
        "event.feedback",
        user_id=user_id, feedback_type=feedback_type, pc=pc,
        ts=datetime.now(timezone.utc).isoformat(),
    )
