"""
monitoring/health.py

Health Check Endpoints — Drishti-Link
══════════════════════════════════════

Two endpoints:

  GET /health
      Simple liveness probe — 200 OK means the process is alive.
      Used by Railway / load balancer for routing decisions.

  GET /health/detailed
      Full system status — used by cloud provider for auto-restart
      and by the admin dashboard for at-a-glance system health.

      Returns one of three system states:
        ● healthy    — all components nominal
        ● degraded   — running but with reduced capability
        ● down       — critical failure, restart recommended
"""

from __future__ import annotations

import time
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

import structlog
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

log = structlog.get_logger(__name__)

router = APIRouter(tags=["Health"])


# ═════════════════════════════════════════════════════════════════════════════
# System state enum
# ═════════════════════════════════════════════════════════════════════════════

class SystemState(str, Enum):
    HEALTHY  = "healthy"
    DEGRADED = "degraded"
    DOWN     = "down"


# ═════════════════════════════════════════════════════════════════════════════
# Component checkers  (pure functions — each probes one component)
# ═════════════════════════════════════════════════════════════════════════════

def _check_yolo(app_state) -> dict:
    try:
        yolo = getattr(app_state, "yolo", None)
        loaded = yolo is not None and yolo.is_ready
        return {
            "status":  "loaded" if loaded else "not_loaded",
            "healthy": loaded,
            "detail":  None if loaded else "YOLO model not yet loaded",
        }
    except Exception as exc:
        return {"status": "error", "healthy": False, "detail": str(exc)}


def _check_mediapipe(app_state) -> dict:
    try:
        mp = getattr(app_state, "mediapipe", None)
        if mp is None:
            return {"status": "not_initialized", "healthy": False, "detail": "Service missing"}
        avail = getattr(mp, "_pose_available", True)
        return {
            "status":  "loaded" if avail else "degraded_no_pose",
            "healthy": True,    # degraded mediapipe is still acceptable
            "detail":  None if avail else "Pose model not available — using heuristic fallback",
        }
    except Exception as exc:
        return {"status": "error", "healthy": False, "detail": str(exc)}


def _check_firebase(app_state) -> dict:
    try:
        svc = getattr(app_state, "firebase", None)
        if svc is None:
            # Firebase may not be a named attribute — try import probe
            try:
                import firebase_admin
                _ = firebase_admin.get_app()
                return {"status": "connected", "healthy": True, "detail": None}
            except Exception:
                return {"status": "not_configured", "healthy": True,
                        "detail": "Firebase not initialised — local mode"}

        ready = getattr(svc, "_ready", False)
        return {
            "status":  "connected" if ready else "not_connected",
            "healthy": ready,
            "detail":  None if ready else "Firebase connection not established",
        }
    except Exception as exc:
        return {"status": "error", "healthy": False, "detail": str(exc)}


def _check_adaptive_engine(app_state) -> dict:
    try:
        ae = getattr(app_state, "adaptive", None)
        if ae is None:
            return {"status": "not_initialized", "healthy": False, "detail": "AdaptiveEngine missing"}
        # Light probe: check state dict exists
        _ = ae._states
        return {"status": "active", "healthy": True, "detail": None}
    except Exception as exc:
        return {"status": "error", "healthy": False, "detail": str(exc)}


def _check_governor(app_state) -> dict:
    try:
        gov = getattr(app_state, "governor", None)
        if gov is None:
            return {"status": "not_initialized", "healthy": False}
        return {"status": "active", "healthy": True}
    except Exception as exc:
        return {"status": "error", "healthy": False, "detail": str(exc)}


def _check_ws_pool(app_state) -> dict:
    try:
        from websocket.live_stream import get_pool
        pool = get_pool()
        stats = pool.stats()
        return {
            "active":    stats.get("active", 0),
            "resumable": stats.get("resumable", 0),
            "healthy":   True,
        }
    except Exception as exc:
        return {"active": 0, "resumable": 0, "healthy": False, "detail": str(exc)}


def _check_model_manager(app_state) -> dict:
    try:
        mgr = getattr(app_state, "model_manager", None)
        if mgr is None:
            return {"status": "not_initialized", "healthy": False}
        active = mgr._active
        return {
            "active_version": active,
            "observing":      mgr._observing,
            "healthy":        active is not None,
        }
    except Exception as exc:
        return {"active_version": None, "healthy": False, "detail": str(exc)}


def _check_metrics(app_state) -> dict:
    try:
        metrics = getattr(app_state, "metrics", None)
        if metrics is None:
            return {"healthy": False, "detail": "MetricsCollector not found"}
        snap = metrics.snapshot()
        perf = snap.get("performance", {})
        return {
            "avg_processing_ms": perf.get("frame_processing_ms", {}).get("mean", 0),
            "p95_ms":            perf.get("frame_processing_ms", {}).get("p95", 0),
            "fps":               perf.get("frames_per_second", 0),
            "total_frames":      perf.get("total_frames", 0),
            "p95_ok":            perf.get("p95_ok", True),
            "healthy":           True,
        }
    except Exception as exc:
        return {"healthy": False, "detail": str(exc)}


# ═════════════════════════════════════════════════════════════════════════════
# State aggregator
# ═════════════════════════════════════════════════════════════════════════════

def _aggregate_state(components: dict) -> SystemState:
    """
    Determine overall system state from component health.

    Rules:
      ● YOLO not loaded     → DOWN  (cannot do anything useful)
      ● Firebase error      → DEGRADED (learning disabled, navigation works)
      ● Adaptive engine err → DEGRADED
      ● All healthy         → HEALTHY
    """
    yolo_ok     = components.get("yolo_model", {}).get("healthy", False)
    firebase_ok = components.get("firebase", {}).get("healthy", True)
    adaptive_ok = components.get("adaptive_engine", {}).get("healthy", True)
    governor_ok = components.get("moral_governor", {}).get("healthy", True)

    if not yolo_ok or not governor_ok:
        return SystemState.DOWN

    if not firebase_ok or not adaptive_ok:
        return SystemState.DEGRADED

    return SystemState.HEALTHY


# ═════════════════════════════════════════════════════════════════════════════
# FastAPI Endpoints
# ═════════════════════════════════════════════════════════════════════════════

@router.get("/health", summary="Liveness probe")
async def liveness(request: Request) -> JSONResponse:
    """
    Fastest possible liveness check.
    Returns 200 if the process is alive and accepting connections.
    Used by Railway/ECS for routing, not restart decisions.
    """
    return JSONResponse(
        status_code=200,
        content={
            "status": "alive",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    )


@router.get("/health/detailed", summary="Full system health check")
async def detailed_health(request: Request) -> JSONResponse:
    """
    Full component health check — used by cloud provider for auto-restart
    and by the admin dashboard.

    HTTP status codes:
      200 → healthy or degraded (process running)
      503 → down (restart recommended)
    """
    t0 = time.perf_counter()
    app_state = request.app.state

    # ── Probe all components ──────────────────────────────────────────────────
    components = {
        "yolo_model":      _check_yolo(app_state),
        "mediapipe":       _check_mediapipe(app_state),
        "firebase":        _check_firebase(app_state),
        "adaptive_engine": _check_adaptive_engine(app_state),
        "moral_governor":  _check_governor(app_state),
        "websocket_pool":  _check_ws_pool(app_state),
        "model_manager":   _check_model_manager(app_state),
    }

    metrics_info = _check_metrics(app_state)
    system_state = _aggregate_state(components)

    # Uptime
    started_at = getattr(app_state, "started_at", time.monotonic())
    uptime_s   = round(time.monotonic() - started_at, 0)

    # Model info
    model_version = components["model_manager"].get("active_version", "unknown")

    body = {
        "status":             system_state.value,
        "timestamp":          datetime.now(timezone.utc).isoformat(),
        "uptime_seconds":     uptime_s,
        "model_version":      model_version,
        "probe_ms":           round((time.perf_counter() - t0) * 1000, 2),

        # Component breakdown
        "components":         components,

        # Quick summary fields (for cloud provider decision making)
        "yolo_model":         components["yolo_model"]["status"],
        "firebase":           components["firebase"]["status"],
        "adaptive_engine":    components["adaptive_engine"]["status"],
        "moral_governor":     components["moral_governor"]["status"],
        "websocket_pool":     {
            "active":    components["websocket_pool"].get("active", 0),
            "resumable": components["websocket_pool"].get("resumable", 0),
        },

        # Performance
        "avg_processing_ms":  metrics_info.get("avg_processing_ms", 0),
        "p95_ms":             metrics_info.get("p95_ms", 0),
        "p95_ok":             metrics_info.get("p95_ok", True),
        "frames_per_second":  metrics_info.get("fps", 0),
    }

    http_status = 200 if system_state != SystemState.DOWN else 503

    log.info(
        "health.check",
        state=system_state.value,
        probe_ms=body["probe_ms"],
        active_sessions=components["websocket_pool"].get("active", 0),
    )

    return JSONResponse(status_code=http_status, content=body)


# ════════════════════════════════════════════════════════════════════════════
# Startup / shutdown lifecycle hook  (call from main.py lifespan)
# ════════════════════════════════════════════════════════════════════════════

def record_startup_time(app_state) -> None:
    """Call this in lifespan startup to record server start time."""
    app_state.started_at = time.monotonic()
    log.info("health.startup_time_recorded",
             ts=datetime.now(timezone.utc).isoformat())
