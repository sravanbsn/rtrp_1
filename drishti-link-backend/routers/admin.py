"""
routers/admin.py

Admin REST API — Drishti-Link
══════════════════════════════

All endpoints require admin Firebase token claim.
Auth enforced by AuthMiddleware in core/middleware.py.

Endpoint groups:
  Dashboard   — GET  /api/v1/admin/dashboard
  Users       — GET  /api/v1/admin/users[/{user_id}/...]
  System      — GET  /api/v1/admin/metrics
               POST /api/v1/admin/models/activate/{version}
               POST /api/v1/admin/broadcast
               GET  /api/v1/admin/logs
  Hazards     — GET  /api/v1/admin/hazard-map
               GET  /api/v1/admin/hotspots
               POST /api/v1/admin/hazard-map/verify/{hazard_id}
"""

from __future__ import annotations

import asyncio
import time
from datetime import datetime, timezone
from typing import Optional

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel

log = structlog.get_logger(__name__)

router = APIRouter(prefix="/api/v1/admin", tags=["Admin"])


# ═════════════════════════════════════════════════════════════════════════════
# Request/response schemas
# ═════════════════════════════════════════════════════════════════════════════

class BroadcastRequest(BaseModel):
    message:    str
    voice:      bool = True
    haptic:     str  = "GENTLE_PULSE"
    target:     str  = "all"          # "all" | specific user_id


class ActivateModelRequest(BaseModel):
    confirm: bool = False


class VerifyHazardRequest(BaseModel):
    verified:    bool
    verified_by: str
    notes:       Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# Dependency: extract app state
# ═════════════════════════════════════════════════════════════════════════════

def _app_state(request: Request):
    return request.app.state


# ═════════════════════════════════════════════════════════════════════════════
# DASHBOARD
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/dashboard", summary="Admin dashboard snapshot")
async def dashboard(state=Depends(_app_state)) -> dict:
    """
    One-shot dashboard payload for the admin frontend.
    Aggregates metrics + model info + top hazard locations.
    """
    metrics_snap  = state.metrics.snapshot()
    perf          = metrics_snap.get("performance", {})
    biz           = metrics_snap.get("business", {})
    model_status  = await state.model_manager.status()

    # Top hazard locations aggregated from all users' area_memory
    top_hazards = await _aggregate_top_hazards(state, limit=10)

    return {
        "generated_at":       datetime.now(timezone.utc).isoformat(),
        "active_sessions":    biz.get("active_navigation_sessions", 0),
        "total_users":        await _count_users(state),
        "daily_active_users": biz.get("daily_active_users", 0),
        "alerts_today":       metrics_snap.get("ai", {}).get("total_overrides", 0),
        "sos_today":          biz.get("sos_alerts_triggered", 0),
        "avg_processing_ms":  perf.get("frame_processing_ms", {}).get("mean", 0),
        "p95_processing_ms":  perf.get("frame_processing_ms", {}).get("p95", 0),
        "p95_ok":             perf.get("p95_ok", True),
        "model_version":      model_status.get("active_version", "unknown"),
        "total_distance_km":  biz.get("total_distance_km", 0),
        "hazards_avoided_today": biz.get("hazards_avoided", 0),
        "top_hazard_locations": top_hazards,
        "frames_per_second":  perf.get("frames_per_second", 0),
        "total_frames":       perf.get("total_frames", 0),
    }


# ═════════════════════════════════════════════════════════════════════════════
# USER MONITORING
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/users", summary="List all users with basic stats")
async def list_users(
    limit:  int     = Query(50, ge=1, le=200),
    offset: int     = Query(0, ge=0),
    state          = Depends(_app_state),
) -> dict:
    """
    Returns a paginated list of users with their adaptive stats.
    Data sourced from AdaptiveEngine in-memory state.
    """
    adaptive = state.adaptive
    user_ids = list(adaptive._states.keys())
    total    = len(user_ids)
    page     = user_ids[offset: offset + limit]

    users = []
    for uid in page:
        us = adaptive._states[uid]
        thresholds = us.thresholds.to_dict()
        pattern    = us.walking_pattern.to_dict()
        users.append({
            "user_id":           uid,
            "warning_threshold": thresholds["warning_pct"],
            "override_threshold": thresholds["override_pct"],
            "total_sessions":    pattern["total_sessions"],
            "avg_speed_mps":     pattern["avg_speed_mps"],
            "known_hazard_cells": sum(1 for c in us.area_memory.values() if c.is_known),
            "accuracy_sessions": len(us.accuracy_history),
            "pattern_mature":    pattern["pattern_mature"],
            "last_threshold_change": (
                us.threshold_history[-1]["timestamp"]
                if us.threshold_history else None
            ),
        })

    return {"total": total, "offset": offset, "limit": limit, "users": users}


@router.get("/users/{user_id}/profile", summary="Full adaptive profile for one user")
async def user_profile(
    user_id: str,
    state   = Depends(_app_state),
) -> dict:
    adaptive = state.adaptive
    if user_id not in adaptive._states:
        await adaptive.load_from_firebase(user_id)

    us = adaptive._states.get(user_id)
    if not us:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "user_id":            user_id,
        "personal_thresholds": us.thresholds.to_dict(),
        "walking_pattern":    us.walking_pattern.to_dict(),
        "known_hazards":      [
            c.to_dict() for c in us.area_memory.values() if c.is_known
        ],
        "threshold_history":  us.threshold_history[-20:],
        "recent_accuracy":    us.accuracy_history[-10:],
    }


@router.get("/users/{user_id}/sessions", summary="Session history for a user")
async def user_sessions(
    user_id: str,
    limit:   int = Query(20, ge=1, le=100),
    state       = Depends(_app_state),
) -> dict:
    adaptive = state.adaptive
    us = adaptive._states.get(user_id)
    if not us:
        raise HTTPException(status_code=404, detail="User not found in active state")

    return {
        "user_id":  user_id,
        "sessions": us.accuracy_history[-limit:],
        "total":    len(us.accuracy_history),
    }


@router.get("/users/{user_id}/accuracy", summary="AI accuracy stats for a user")
async def user_accuracy(
    user_id: str,
    state   = Depends(_app_state),
) -> dict:
    adaptive = state.adaptive
    us = adaptive._states.get(user_id)
    if not us:
        raise HTTPException(status_code=404, detail="User not found")

    history = us.accuracy_history
    if not history:
        return {"user_id": user_id, "sessions": 0, "message": "No session data yet"}

    precisions = [s.get("precision", 0) for s in history]
    recalls    = [s.get("recall", 0)    for s in history]
    f1s        = [s.get("f1_score", 0)  for s in history]
    fps        = [s.get("false_positives", 0) for s in history]
    fns        = [s.get("false_negatives", 0) for s in history]

    def _avg(lst):
        return round(sum(lst) / len(lst), 4) if lst else 0.0

    return {
        "user_id":            user_id,
        "sessions_analysed":  len(history),
        "avg_precision":      _avg(precisions),
        "avg_recall":         _avg(recalls),
        "avg_f1":             _avg(f1s),
        "total_false_positives": sum(fps),
        "total_false_negatives": sum(fns),
        "recent_trend":       history[-5:],
    }


# ═════════════════════════════════════════════════════════════════════════════
# SYSTEM CONTROL
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/metrics", summary="Full metrics JSON")
async def full_metrics(state=Depends(_app_state)) -> dict:
    return state.metrics.snapshot()


@router.post("/models/activate/{version}", summary="Hot-swap model version")
async def activate_model(
    version: str,
    body:    ActivateModelRequest,
    state   = Depends(_app_state),
) -> dict:
    if not body.confirm:
        return {
            "status":  "preview",
            "message": f"Add 'confirm: true' to activate version {version}",
            "version": version,
        }

    result = await state.model_manager.activate_version(version, state.yolo)

    from core.logging_config import log_model_event
    log_model_event(
        event="activation_requested",
        version=version,
        details={"success": result.success, "previous": result.previous},
    )

    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    return {
        "status":       "activated",
        "version":      result.version,
        "previous":     result.previous,
        "message":      result.message,
        "activated_at": result.activated_at,
    }


@router.get("/models", summary="List all registered model versions")
async def list_models(state=Depends(_app_state)) -> dict:
    versions = await state.model_manager.list_versions()
    status   = await state.model_manager.status()
    return {"versions": versions, "status": status}


@router.post("/models/rollback", summary="Rollback to previous model version")
async def rollback_model(state=Depends(_app_state)) -> dict:
    result = await state.model_manager.rollback(state.yolo)

    from core.logging_config import log_model_event
    log_model_event("rollback", version=result.version or "unknown")

    if not result.success:
        raise HTTPException(status_code=400, detail=result.message)

    return {
        "status":   "rolled_back",
        "version":  result.version,
        "previous": result.previous,
        "message":  result.message,
    }


@router.post("/broadcast", summary="Send message to all active sessions")
async def broadcast(
    body:  BroadcastRequest,
    state = Depends(_app_state),
) -> dict:
    """
    Sends an admin broadcast to all (or one) active WebSocket session(s).
    Useful for urgent area alerts or system maintenance warnings.
    """
    from websocket.live_stream import get_pool
    pool   = get_pool()
    stats  = pool.stats()
    active = stats.get("active", 0)

    # Note: actual WS message delivery requires storing ws references;
    # this ships the broadcast via Firebase RTDB which WS clients subscribe to.
    try:
        from firebase_admin import db
        payload = {
            "type":    "admin_broadcast",
            "message": body.message,
            "voice":   body.voice,
            "haptic":  body.haptic,
            "target":  body.target,
            "sent_at": datetime.now(timezone.utc).isoformat(),
        }
        db.reference("admin/broadcasts").push(payload)
        log.warning("admin.broadcast_sent", target=body.target, message=body.message[:80])
    except Exception as exc:
        log.error("admin.broadcast_failed", exc=str(exc))
        raise HTTPException(status_code=500, detail=f"Broadcast failed: {exc}")

    return {
        "status":          "sent",
        "target":          body.target,
        "active_sessions": active,
        "message":         body.message,
    }


@router.get("/logs", summary="Recent system logs (last N entries)")
async def recent_logs(
    limit:    int  = Query(100, ge=1, le=500),
    level:    str  = Query("INFO", description="Minimum level: DEBUG/INFO/WARNING/ERROR"),
    category: Optional[str] = Query(None, description="Filter by category prefix e.g. 'override'"),
    state         = Depends(_app_state),
) -> dict:
    """
    Returns recent log entries from the in-memory log ring buffer.
    If log buffer is not configured, returns recent Firebase logs.
    """
    try:
        # Try in-memory buffer (set up in logging_config if enabled)
        buf = getattr(state, "_log_buffer", None)
        if buf:
            entries = list(buf)[-limit:]
            if category:
                entries = [e for e in entries if str(e.get("event","")).startswith(category)]
            return {"count": len(entries), "entries": entries}
    except Exception:
        pass

    # Fallback: read from Firebase admin/critical_logs
    try:
        from firebase_admin import db
        ref   = db.reference("admin/critical_logs")
        data  = ref.order_by_key().limit_to_last(limit).get()
        if data:
            entries = list(data.values())
            if category:
                entries = [e for e in entries if str(e.get("event","")).startswith(category)]
            return {"count": len(entries), "source": "firebase", "entries": entries}
    except Exception as exc:
        log.warning("admin.logs_fetch_failed", exc=str(exc))

    return {"count": 0, "entries": [], "message": "No log buffer configured"}


# ═════════════════════════════════════════════════════════════════════════════
# HAZARD INTELLIGENCE
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/hazard-map", summary="All known hazards with coordinates")
async def hazard_map(
    min_count:  int   = Query(1, ge=1, description="Minimum detection count"),
    known_only: bool  = Query(False, description="Only return KNOWN hazards (count >= 3)"),
    state             = Depends(_app_state),
) -> dict:
    """
    Aggregated hazard map across all users.
    Each hazard includes lat/lng, type, count, and peak hour.
    """
    adaptive = state.adaptive
    all_cells = []

    for user_state in adaptive._states.values():
        for cell in user_state.area_memory.values():
            if cell.total_count < min_count:
                continue
            if known_only and not cell.is_known:
                continue
            all_cells.append({
                "grid_key":      cell.grid_key,
                "lat":           cell.lat,
                "lng":           cell.lng,
                "hazard_type":   cell.dominant_hazard,
                "count":         cell.total_count,
                "is_known":      cell.is_known,
                "peak_hour":     cell.peak_hour,
                "last_seen":     cell.last_seen,
                "hazard_counts": cell.hazard_counts,
            })

    # Merge duplicate grid keys (different users may have same cell)
    merged = _merge_hazard_cells(all_cells)

    return {
        "total_cells":  len(merged),
        "known_hazards": sum(1 for c in merged if c["is_known"]),
        "hazards":       merged,
        "generated_at":  datetime.now(timezone.utc).isoformat(),
    }


@router.get("/hotspots", summary="Top 10 most dangerous locations")
async def hotspots(state=Depends(_app_state)) -> dict:
    """
    Returns the 10 grid cells with the highest detection counts.
    Includes human-readable labels and temporal patterns.
    """
    result = await hazard_map(min_count=1, known_only=False, state=state)
    cells  = result.get("hazards", [])
    top10  = sorted(cells, key=lambda c: c["count"], reverse=True)[:10]

    for i, c in enumerate(top10, 1):
        c["rank"] = i
        hour = c.get("peak_hour")
        c["peak_time_label"] = _hour_label(hour) if hour is not None else "Unknown"
        c["danger_level"] = (
            "Critical" if c["count"] >= 10 else
            "High"     if c["count"] >= 5  else
            "Moderate"
        )

    return {
        "hotspots":     top10,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/hazard-map/verify/{hazard_id}", summary="Human verify a hazard")
async def verify_hazard(
    hazard_id: str,
    body:      VerifyHazardRequest,
    state     = Depends(_app_state),
) -> dict:
    """
    Mark a hazard as human-verified (or disputed).
    Stored in Firebase for reference by feedback_trainer.
    """
    payload = {
        "hazard_id":   hazard_id,
        "verified":    body.verified,
        "verified_by": body.verified_by,
        "notes":       body.notes,
        "verified_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        from firebase_admin import db
        db.reference(f"admin/verified_hazards/{hazard_id}").set(payload)
        log.info("admin.hazard_verified", hazard_id=hazard_id,
                 verified=body.verified, by=body.verified_by)
    except Exception as exc:
        log.warning("admin.hazard_verify_failed", exc=str(exc))

    return {"status": "verified" if body.verified else "disputed", **payload}


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

async def _aggregate_top_hazards(state, limit: int = 10) -> list[dict]:
    """Collect and rank known hazard cells across all users."""
    all_known = []
    for us in state.adaptive._states.values():
        for cell in us.area_memory.values():
            if cell.is_known:
                all_known.append({
                    "lat":        cell.lat,
                    "lng":        cell.lng,
                    "hazard_type": cell.dominant_hazard,
                    "count":      cell.total_count,
                })
    return sorted(all_known, key=lambda c: c["count"], reverse=True)[:limit]


async def _count_users(state) -> int:
    return len(state.adaptive._states)


def _merge_hazard_cells(cells: list[dict]) -> list[dict]:
    """
    Merge cells with the same grid_key (from different users).
    Sums counts and keeps the most recent last_seen.
    """
    merged: dict[str, dict] = {}
    for cell in cells:
        key = cell["grid_key"]
        if key not in merged:
            merged[key] = dict(cell)
        else:
            existing = merged[key]
            existing["count"] += cell["count"]
            # Merge hazard_counts
            for htype, cnt in cell.get("hazard_counts", {}).items():
                existing["hazard_counts"][htype] = (
                    existing["hazard_counts"].get(htype, 0) + cnt
                )
            # Keep is_known if any user marked it
            existing["is_known"] = existing["is_known"] or cell["is_known"]
            # Update dominant hazard
            if existing["hazard_counts"]:
                existing["hazard_type"] = max(
                    existing["hazard_counts"], key=existing["hazard_counts"].get
                )
    return list(merged.values())


def _hour_label(hour: int) -> str:
    labels = {
        range(5, 9):   "Early Morning (5-9 AM)",
        range(9, 12):  "Morning (9 AM-12 PM)",
        range(12, 17): "Afternoon (12-5 PM)",
        range(17, 20): "Evening (5-8 PM)",
        range(20, 24): "Night (8 PM-12 AM)",
        range(0, 5):   "Late Night (12-5 AM)",
    }
    for r, label in labels.items():
        if hour in r:
            return label
    return f"Hour {hour}:00"
