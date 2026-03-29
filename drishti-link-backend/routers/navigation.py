"""Navigation session lifecycle endpoints."""
from __future__ import annotations

import structlog
from fastapi import APIRouter, HTTPException, status
from fastapi.responses import ORJSONResponse

from core.exceptions import SessionNotFoundError, SessionAlreadyActiveError
from models.session import (
    NavigationSession, SessionStartRequest,
    SessionUpdateRequest, SessionSummary, SessionStatus,
)

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/navigation")

# In-memory session store (replace with Redis/PostgreSQL in production)
_sessions: dict[str, NavigationSession] = {}


def _get_session(session_id: str) -> NavigationSession:
    session = _sessions.get(session_id)
    if not session:
        raise SessionNotFoundError(message=f"Session {session_id!r} not found.")
    return session


@router.post(
    "/sessions",
    response_model=NavigationSession,
    status_code=status.HTTP_201_CREATED,
    summary="Start a navigation session",
)
async def start_session(body: SessionStartRequest) -> NavigationSession:
    # Guard: one active session per user
    active = [
        s for s in _sessions.values()
        if s.user_id == body.user_id and s.status == SessionStatus.ACTIVE
    ]
    if active:
        raise SessionAlreadyActiveError(user_id=body.user_id)

    session = NavigationSession(
        user_id=body.user_id,
        start_location=body.start_location,
        destination=body.destination,
        route_id=body.route_id,
        guardian_ids=body.guardian_ids,
        current_location=body.start_location,
    )
    _sessions[session.session_id] = session

    log.info(
        "navigation.session_started",
        session_id=session.session_id,
        user_id=body.user_id,
        guardian_count=len(body.guardian_ids),
    )
    return session


@router.get(
    "/sessions/{session_id}",
    response_model=NavigationSession,
    summary="Get session details",
)
async def get_session(session_id: str) -> NavigationSession:
    return _get_session(session_id)


@router.patch(
    "/sessions/{session_id}/location",
    response_model=NavigationSession,
    summary="Update current location and stats",
)
async def update_location(
    session_id: str, body: SessionUpdateRequest
) -> NavigationSession:
    session = _get_session(session_id)
    if session.status != SessionStatus.ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Session is not active.",
        )
    session.current_location = body.current_location
    session.waypoints.append(body.current_location)
    return session


@router.post(
    "/sessions/{session_id}/pause",
    response_model=NavigationSession,
    summary="Pause an active session",
)
async def pause_session(session_id: str) -> NavigationSession:
    session = _get_session(session_id)
    session.status = SessionStatus.PAUSED
    log.info("navigation.session_paused", session_id=session_id)
    return session


@router.post(
    "/sessions/{session_id}/resume",
    response_model=NavigationSession,
    summary="Resume a paused session",
)
async def resume_session(session_id: str) -> NavigationSession:
    session = _get_session(session_id)
    if session.status != SessionStatus.PAUSED:
        raise HTTPException(status_code=409, detail="Session is not paused.")
    session.status = SessionStatus.ACTIVE
    log.info("navigation.session_resumed", session_id=session_id)
    return session


@router.post(
    "/sessions/{session_id}/end",
    response_model=SessionSummary,
    summary="End a navigation session and return summary",
)
async def end_session(session_id: str) -> SessionSummary:
    from datetime import datetime, timezone

    session = _get_session(session_id)
    session.status = SessionStatus.COMPLETED
    session.ended_at = datetime.now(timezone.utc)

    duration = (session.ended_at - session.started_at).total_seconds() / 60.0

    summary = SessionSummary(
        session_id=session_id,
        duration_minutes=round(duration, 2),
        distance_covered_m=session.distance_covered_m,
        total_overrides=session.total_overrides,
        total_warnings=session.total_warnings,
        hazards_avoided=session.hazards_avoided,
        max_pc_encountered=session.max_pc_encountered,
        ended_at=session.ended_at,
    )
    log.info(
        "navigation.session_ended",
        session_id=session_id,
        duration_min=summary.duration_minutes,
        overrides=summary.total_overrides,
    )
    return summary


@router.get(
    "/sessions",
    response_model=list[NavigationSession],
    summary="List sessions for a user",
)
async def list_sessions(
    user_id: str, limit: int = 20, offset: int = 0
) -> list[NavigationSession]:
    user_sessions = [
        s for s in _sessions.values() if s.user_id == user_id
    ]
    return user_sessions[offset : offset + limit]
