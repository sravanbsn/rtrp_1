"""
core/logging_config.py

Structured JSON Logging System — Drishti-Link
═══════════════════════════════════════════════

Three destinations:
  CONSOLE (dev)   — human-readable colored output via structlog
  FILE (prod)     — JSON-Lines, daily rotation (logs/drishti-{date}.jsonl)
  FIREBASE (all)  — critical events only (SOS, OVERRIDE, ERROR)

Eight log categories (used as event prefixes):
  navigation.*    — session start/end, distance, summary
  ai_decision.*   — every moral governor decision chain
  override.*      — every override with reason + duration
  sos.*           — all SOS events
  performance.*   — slow requests (>100ms WARNING, >500ms ERROR)
  error.*         — all exceptions with stack trace
  adaptive.*      — threshold changes with reasons
  model.*         — model load/switch/rollback events

Every log entry includes:
  timestamp, request_id, user_id, session_id,
  level, event, message, duration_ms, metadata
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import os
import sys
import traceback
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import structlog
from structlog.types import EventDict, WrappedLogger

# ── Config ────────────────────────────────────────────────────────────────────
LOG_DIR          = Path(os.getenv("LOG_DIR", "logs"))
LOG_LEVEL        = os.getenv("LOG_LEVEL", "INFO").upper()
IS_PRODUCTION    = os.getenv("ENVIRONMENT", "development").lower() == "production"
SLOW_REQUEST_MS  = 100
VERY_SLOW_MS     = 500

# Firebase critical event types (fire-and-forget)
FIREBASE_CRITICAL = frozenset({"sos", "override", "error", "model"})


# ═════════════════════════════════════════════════════════════════════════════
# Structlog processors
# ═════════════════════════════════════════════════════════════════════════════

def _add_timestamp(
    logger: WrappedLogger, method: str, event_dict: EventDict
) -> EventDict:
    event_dict["timestamp"] = datetime.now(timezone.utc).isoformat()
    return event_dict


def _add_log_level(
    logger: WrappedLogger, method: str, event_dict: EventDict
) -> EventDict:
    event_dict["level"] = method.upper()
    return event_dict


def _ensure_request_id(
    logger: WrappedLogger, method: str, event_dict: EventDict
) -> EventDict:
    """Carries request_id forward if bound to context."""
    if "request_id" not in event_dict:
        event_dict["request_id"] = None
    return event_dict


class _FirebaseSink:
    """
    Structlog processor that asynchronously ships critical events to Firebase.
    Only fires for SOS, OVERRIDE, ERROR, MODEL events.
    Does nothing if Firebase is not configured.
    """

    def __call__(
        self, logger: WrappedLogger, method: str, event_dict: EventDict
    ) -> EventDict:
        event: str = str(event_dict.get("event", ""))
        category   = event.split(".")[0].lower()

        if category in FIREBASE_CRITICAL and method.upper() in ("WARNING", "ERROR", "CRITICAL"):
            try:
                import asyncio
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    asyncio.create_task(
                        _firebase_log_async(dict(event_dict))
                    )
            except Exception:
                pass   # never crash logging
        return event_dict


async def _firebase_log_async(entry: dict) -> None:
    try:
        from firebase_admin import db
        ref = db.reference("admin/critical_logs")
        ref.push(entry)
    except Exception:
        pass


# ═════════════════════════════════════════════════════════════════════════════
# File handler (JSON Lines, daily rotation)
# ═════════════════════════════════════════════════════════════════════════════

class _JsonLinesHandler(logging.handlers.TimedRotatingFileHandler):
    """
    Writes one JSON object per line, rotates daily at midnight.
    Keeps 30 days of log files.
    """

    def __init__(self) -> None:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        path = LOG_DIR / "drishti-backend.jsonl"
        super().__init__(
            filename=str(path),
            when="midnight",
            interval=1,
            backupCount=30,
            encoding="utf-8",
            utc=True,
        )
        self.setFormatter(logging.Formatter("%(message)s"))

    def emit(self, record: logging.LogRecord) -> None:
        try:
            # structlog already serialised the record as JSON via the renderer
            super().emit(record)
        except Exception:
            self.handleError(record)


# ═════════════════════════════════════════════════════════════════════════════
# Configurator — call once at app startup
# ═════════════════════════════════════════════════════════════════════════════

def configure_logging() -> None:
    """
    Configure structlog + stdlib logging for the application.
    Call in main.py before any other imports that log.
    """
    # ── Shared processors (both console and file) ────────────────────────────
    shared_processors: list = [
        structlog.contextvars.merge_contextvars,
        _add_timestamp,
        _add_log_level,
        _ensure_request_id,
        structlog.stdlib.add_log_level,
        structlog.processors.StackInfoRenderer(),
        _FirebaseSink(),
    ]

    if IS_PRODUCTION:
        # ── Production: JSON to file + stderr ─────────────────────────────────
        structlog.configure(
            processors=shared_processors + [
                structlog.processors.format_exc_info,
                structlog.processors.JSONRenderer(),
            ],
            wrapper_class=structlog.make_filtering_bound_logger(
                logging.getLevelName(LOG_LEVEL)
            ),
            context_class=dict,
            logger_factory=structlog.PrintLoggerFactory(),
        )

        # Attach file handler to stdlib root logger
        file_handler = _JsonLinesHandler()
        file_handler.setLevel(LOG_LEVEL)
        stdlib_root = logging.getLogger()
        stdlib_root.setLevel(LOG_LEVEL)
        stdlib_root.addHandler(file_handler)
        # Stderr for cloud provider capture
        stderr_handler = logging.StreamHandler(sys.stderr)
        stderr_handler.setLevel(LOG_LEVEL)
        stdlib_root.addHandler(stderr_handler)

    else:
        # ── Development: colored, human-readable console ───────────────────────
        structlog.configure(
            processors=shared_processors + [
                structlog.dev.ConsoleRenderer(colors=True),
            ],
            wrapper_class=structlog.make_filtering_bound_logger(logging.DEBUG),
            context_class=dict,
            logger_factory=structlog.PrintLoggerFactory(),
        )

    # Silence noisy libraries
    for noisy in ("uvicorn.access", "httpx", "firebase_admin"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


# ═════════════════════════════════════════════════════════════════════════════
# Typed event helpers — one function per category
# ═════════════════════════════════════════════════════════════════════════════

_log = structlog.get_logger("drishti")


def log_navigation_start(
    user_id:    str,
    session_id: str,
    request_id: Optional[str] = None,
) -> None:
    _log.info(
        "navigation.session_start",
        user_id=user_id, session_id=session_id, request_id=request_id,
    )


def log_navigation_end(
    user_id:      str,
    session_id:   str,
    duration_min: float,
    distance_m:   float,
    overrides:    int,
    warnings:     int,
) -> None:
    _log.info(
        "navigation.session_end",
        user_id=user_id, session_id=session_id,
        duration_min=round(duration_min, 1),
        distance_m=round(distance_m, 1),
        overrides=overrides, warnings=warnings,
    )


def log_ai_decision(
    user_id:    str,
    session_id: str,
    frame_id:   str,
    decision:   str,
    pc_score:   float,
    rules:      list,
    confidence: float,
    duration_ms: float,
) -> None:
    _log.info(
        "ai_decision.frame",
        user_id=user_id, session_id=session_id, frame_id=frame_id,
        decision=decision, pc_score=round(pc_score, 4),
        rules=rules, confidence=round(confidence, 3),
        duration_ms=round(duration_ms, 1),
    )


def log_override(
    user_id:    str,
    session_id: str,
    reason:     str,
    rules:      list,
    pc_score:   float,
    held_s:     float = 0.0,
) -> None:
    _log.warning(
        "override.fired",
        user_id=user_id, session_id=session_id,
        reason=reason, rules=rules,
        pc_score=round(pc_score, 4),
        held_seconds=round(held_s, 2),
    )


def log_sos(
    user_id:       str,
    session_id:    str,
    stationary_s:  float,
    lat:           float,
    lng:           float,
) -> None:
    _log.critical(
        "sos.triggered",
        user_id=user_id, session_id=session_id,
        stationary_seconds=round(stationary_s, 0),
        lat=lat, lng=lng,
    )


def log_slow_request(
    path:        str,
    method:      str,
    duration_ms: float,
    request_id:  Optional[str] = None,
    user_id:     Optional[str] = None,
) -> None:
    level = "error" if duration_ms > VERY_SLOW_MS else "warning"
    getattr(_log, level)(
        "performance.slow_request",
        path=path, method=method,
        duration_ms=round(duration_ms, 1),
        request_id=request_id, user_id=user_id,
        threshold_ms=VERY_SLOW_MS if level == "error" else SLOW_REQUEST_MS,
    )


def log_error(
    event:      str,
    exc:        Exception,
    user_id:    Optional[str] = None,
    session_id: Optional[str] = None,
    request_id: Optional[str] = None,
    **extra,
) -> None:
    _log.error(
        f"error.{event}",
        user_id=user_id, session_id=session_id, request_id=request_id,
        exc_type=type(exc).__name__,
        exc_message=str(exc),
        traceback="".join(traceback.format_exception(type(exc), exc, exc.__traceback__)),
        **extra,
    )


def log_adaptive_change(
    user_id:       str,
    session_id:    str,
    old_warning:   float,
    new_warning:   float,
    old_override:  float,
    new_override:  float,
    reason:        str,
) -> None:
    _log.info(
        "adaptive.threshold_changed",
        user_id=user_id, session_id=session_id,
        old_warning=old_warning, new_warning=new_warning,
        old_override=old_override, new_override=new_override,
        reason=reason,
    )


def log_model_event(
    event:   str,
    version: str,
    details: Optional[dict] = None,
) -> None:
    _log.warning(
        f"model.{event}",
        version=version,
        **(details or {}),
    )
