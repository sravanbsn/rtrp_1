"""
websocket/live_stream.py

Production WebSocket Handler — Drishti-Link Real-Time Navigation
════════════════════════════════════════════════════════════════

WebSocket endpoint: ws://<host>/api/v1/ws/navigate/{session_id}

Full processing pipeline per frame:
  raw bytes/base64
    → YOLOService.detect_bytes()         (object detection)
    → MediaPipeService.analyze()         (motion/depth)
    → CollisionScorer.score_detections() (Pc computation)
    → AdaptiveEngine.get_pc_boost()      (area memory)
    → MoralGovernor.evaluate()           (ethical decision)
    → JSON response                      (<100ms target)

Connection management:
  ● Max 1 active navigation session per user (enforced at accept)
  ● Heartbeat ping every 30 seconds
  ● Resume window: reconnect within 60s to restore session state
  ● Graceful degradation on slow frames (frame-skip signal to client)
  ● Clean session teardown + adaptive learning on any disconnect
"""

from __future__ import annotations

import asyncio
import base64
import json
import time
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Optional

import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status

from core.config import settings
from monitoring.metrics import MetricsCollector

log = structlog.get_logger(__name__)

router = APIRouter()

# ── Tunables ──────────────────────────────────────────────────────────────────
HEARTBEAT_INTERVAL_S   = 30       # ping interval
RESUME_WINDOW_S        = 60       # seconds to allow reconnect and reclaim session
MAX_FRAME_QUEUE        = 5        # drop frames if queue exceeds this
TARGET_FRAME_MS        = 100      # target round-trip per frame
SLOW_FRAME_THRESHOLD   = 150      # warn client to throttle if above this


# ═════════════════════════════════════════════════════════════════════════════
# Protocol schemas
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class ConnectedResponse:
    status:              str = "connected"
    session_id:          str = ""
    user_id:             str = ""
    warning_threshold:   float = 0.40
    override_threshold:  float = 0.70
    area_memory_loaded:  bool = False
    known_hazards_nearby: int = 0
    server_version:      str = "1.0.0"


@dataclass
class FrameResponse:
    frame_id:         str
    pc_score:         float          # 0.0–1.0
    decision:         str            # OVERRIDE / WARNING / AREA_MEMORY_ALERT / CLEAR / SOS
    haptic_pattern:   str
    voice_message:    Optional[str]
    detected_objects: list
    processing_ms:    float
    area_memory_alert: bool
    confidence:       float
    rules_triggered:  list[str]
    guardian_summary: str
    throttle_hint:    bool = False   # True → client should reduce frame rate


@dataclass
class ErrorResponse:
    status:  str = "error"
    code:    str = ""
    message: str = ""


# ═════════════════════════════════════════════════════════════════════════════
# Per-session state
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class SessionState:
    session_id:     str
    user_id:        str
    connected_at:   float          # time.monotonic()
    last_seen:      float
    frames_processed: int = 0
    total_overrides:  int = 0
    total_warnings:   int = 0
    distance_m:       float = 0.0
    stationary_for_s: float = 0.0
    last_velocity:    float = 0.0
    last_lat:         float = 0.0
    last_lng:         float = 0.0

    def mark_alive(self) -> None:
        self.last_seen = time.monotonic()

    def update_stationary(self, velocity: float, frame_dt_s: float = 0.1) -> None:
        if velocity < 0.05:
            self.stationary_for_s += frame_dt_s
        else:
            self.stationary_for_s = 0.0
        self.last_velocity = velocity


# ═════════════════════════════════════════════════════════════════════════════
# Connection Pool
# ═════════════════════════════════════════════════════════════════════════════

class ConnectionPool:
    """
    Tracks all active WebSocket sessions.
    Enforces one-session-per-user policy.
    Provides resume window for reconnects.
    """

    def __init__(self) -> None:
        # user_id → SessionState
        self._active:    dict[str, SessionState] = {}
        # session_id → (user_id, expiry_time) for resume window
        self._resumable: dict[str, tuple[str, float]] = {}
        self._lock       = asyncio.Lock()

    async def accept(self, user_id: str, session_id: str) -> tuple[bool, str]:
        """
        Try to register a new connection.
        Returns (accepted, reason).
        Evicts a previous session if it's in the resume window.
        """
        async with self._lock:
            # Already connected — reject (one session per user)
            if user_id in self._active:
                return False, "USER_ALREADY_NAVIGATING"

            # Check if reconnecting within resume window
            if session_id in self._resumable:
                uid, expiry = self._resumable[session_id]
                if uid == user_id and time.monotonic() < expiry:
                    del self._resumable[session_id]
                    log.info("ws.session_resumed", user_id=user_id, session_id=session_id)

            state = SessionState(
                session_id=session_id,
                user_id=user_id,
                connected_at=time.monotonic(),
                last_seen=time.monotonic(),
            )
            self._active[user_id] = state
            return True, "OK"

    async def release(self, user_id: str, resumable: bool = True) -> Optional[SessionState]:
        """
        Remove session from active pool.
        If resumable=True, keep it in resume window for RESUME_WINDOW_S.
        Returns the SessionState so caller can run end-of-session processing.
        """
        async with self._lock:
            state = self._active.pop(user_id, None)
            if state and resumable:
                expiry = time.monotonic() + RESUME_WINDOW_S
                self._resumable[state.session_id] = (user_id, expiry)
            return state

    async def get_state(self, user_id: str) -> Optional[SessionState]:
        async with self._lock:
            return self._active.get(user_id)

    def active_count(self) -> int:
        return len(self._active)

    def stats(self) -> dict:
        return {
            "active":    len(self._active),
            "resumable": len(self._resumable),
        }


# Singleton pool — shared across all WS connections in this process
_POOL = ConnectionPool()


def get_pool() -> ConnectionPool:
    return _POOL


# ═════════════════════════════════════════════════════════════════════════════
# Main WebSocket handler
# ═════════════════════════════════════════════════════════════════════════════

@router.websocket("/navigate/{session_id}")
async def navigation_ws_handler(
    websocket:  WebSocket,
    session_id: str,
) -> None:
    """
    Primary WebSocket handler.
    Called by the router after token validation.

    app_state is expected to have:
      .yolo            YOLOService
      .mediapipe       MediaPipeService
      .scorer          CollisionScorer
      .adaptive        AdaptiveEngine
      .governor        MoralGovernor
      .metrics         MetricsCollector
    """
    app_state = websocket.app.state
    # We get user_id from the authenticated request state normally, but for WS
    # we'll extract it after checking auth headers or query params
    # Assuming AuthMiddleware handled it (or WS token validation):
    user_id = getattr(websocket.state, "user_id", "anonymous")
    
    metrics: MetricsCollector = app_state.metrics
    pool:    ConnectionPool   = _POOL

    # ── Accept connection ─────────────────────────────────────────────────────
    accepted, reason = await pool.accept(user_id, session_id)
    if not accepted:
        await websocket.accept()
        await _send_error(websocket, "REJECTED", reason)
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        log.warning("ws.rejected", user_id=user_id, reason=reason)
        return

    await websocket.accept()
    metrics.ws_connected()

    log.info("ws.connected", user_id=user_id, session_id=session_id)

    # ── Load user adaptive profile ────────────────────────────────────────────
    adaptive = app_state.adaptive
    await adaptive.load_from_firebase(user_id)
    thresholds = await adaptive.get_thresholds(user_id)

    # Check for known hazards near last known position
    state = await pool.get_state(user_id)
    area_cells = []
    if state and (state.last_lat or state.last_lng):
        area_cells = await adaptive.query_area_memory(
            user_id, state.last_lat, state.last_lng, radius_m=50.0
        )

    # ── Send CONNECTED response ───────────────────────────────────────────────
    await _send_json(websocket, asdict(ConnectedResponse(
        session_id=session_id,
        user_id=user_id,
        warning_threshold=thresholds.warning,
        override_threshold=thresholds.override,
        area_memory_loaded=True,
        known_hazards_nearby=sum(1 for c in area_cells if c.get("is_known")),
    )))

    # ── Start heartbeat task ──────────────────────────────────────────────────
    heartbeat_task = asyncio.create_task(
        _heartbeat_loop(websocket, session_id)
    )

    # ── Frame processing loop ─────────────────────────────────────────────────
    try:
        async for raw_msg in _frame_receiver(websocket):
            t_frame = time.perf_counter()

            frame_payload = _parse_frame_message(raw_msg)
            if frame_payload is None:
                await _send_error(websocket, "PARSE_ERROR", "Invalid frame payload")
                continue

            frame_bytes, frame_meta = frame_payload
            frame_id = str(uuid.uuid4())[:8]

            # Update session state
            session_state = await pool.get_state(user_id)
            if session_state:
                session_state.mark_alive()
                session_state.frames_processed += 1
                frame_dt = 0.1   # assume 100ms frame rate
                session_state.update_stationary(frame_meta.get("velocity", 0.0), frame_dt)
                lat = frame_meta.get("lat", session_state.last_lat)
                lng = frame_meta.get("lng", session_state.last_lng)
                session_state.last_lat, session_state.last_lng = lat, lng

            # ── Full AI pipeline ──────────────────────────────────────────────
            response = await _run_pipeline(
                app_state   = app_state,
                frame_bytes = frame_bytes,
                frame_id    = frame_id,
                session_id  = session_id,
                user_id     = user_id,
                meta        = frame_meta,
                thresholds  = thresholds,
                session_state = session_state,
            )

            processing_ms = (time.perf_counter() - t_frame) * 1000

            # Update metrics
            metrics.record_frame(processing_ms)
            if response["decision"] == "OVERRIDE":
                metrics.record_override()
                if session_state:
                    session_state.total_overrides += 1
            elif response["decision"] == "WARNING":
                if session_state:
                    session_state.total_warnings += 1

            # Throttle hint if frames are taking too long
            throttle = processing_ms > SLOW_FRAME_THRESHOLD

            frame_resp = FrameResponse(
                frame_id=frame_id,
                pc_score=response.get("pc_score", 0.0),
                decision=response.get("decision", "CLEAR"),
                haptic_pattern=response.get("haptic_pattern", "NONE"),
                voice_message=response.get("voice_message"),
                detected_objects=response.get("detected_objects", []),
                processing_ms=round(processing_ms, 1),
                area_memory_alert=response.get("area_memory_alert", False),
                confidence=response.get("confidence", 0.0),
                rules_triggered=response.get("rules_triggered", []),
                guardian_summary=response.get("guardian_summary", ""),
                throttle_hint=throttle,
            )

            await _send_json(websocket, asdict(frame_resp))

    except WebSocketDisconnect as exc:
        log.info("ws.disconnected", user_id=user_id, code=exc.code)
    except Exception as exc:
        log.exception("ws.error", user_id=user_id, exc=str(exc))
        try:
            await _send_error(websocket, "SERVER_ERROR", "Internal error")
        except Exception:
            pass
    finally:
        heartbeat_task.cancel()
        metrics.ws_disconnected()
        await _on_disconnect(
            pool=pool,
            app_state=app_state,
            user_id=user_id,
            session_id=session_id,
        )


# ═════════════════════════════════════════════════════════════════════════════
# Pipeline runner
# ═════════════════════════════════════════════════════════════════════════════

async def _run_pipeline(
    app_state,
    frame_bytes:   bytes,
    frame_id:      str,
    session_id:    str,
    user_id:       str,
    meta:          dict,
    thresholds,
    session_state: Optional[SessionState],
) -> dict:
    """
    Fan-out the full AI pipeline for one frame.
    YOLO and MediaPipe run concurrently for lower latency.
    """
    velocity = float(meta.get("velocity", 0.0))
    lat      = float(meta.get("lat", 0.0))
    lng      = float(meta.get("lng", 0.0))
    intent   = meta.get("user_intent", "walking")

    # ── Stage 1: YOLO + MediaPipe concurrently ────────────────────────────────
    yolo_task = asyncio.create_task(
        app_state.yolo.detect_bytes(frame_bytes, session_id, frame_id)
    )
    mp_task = asyncio.create_task(
        app_state.mediapipe.analyze(frame_bytes, session_id)
    )

    # Wait for both
    yolo_result, mp_result = await asyncio.gather(
        yolo_task, mp_task, return_exceptions=True
    )

    # Graceful degradation: if either fails, continue with empty result
    detections = []
    if not isinstance(yolo_result, Exception) and yolo_result:
        detections = getattr(yolo_result, "detections", [])
    else:
        if isinstance(yolo_result, Exception):
            log.warning("ws.yolo_error", exc=str(yolo_result))

    motion_result = None
    if not isinstance(mp_result, Exception):
        motion_result = mp_result
    else:
        log.warning("ws.mediapipe_error", exc=str(mp_result))

    # ── Stage 2: Collision scoring ────────────────────────────────────────────
    scored_hazards = []
    if detections:
        scored_hazards = await app_state.scorer.score_detections(
            detections=detections,
            user_id=user_id,
            motion_result=motion_result,
        )

    pc_score = max((h.collision_prob for h in scored_hazards), default=0.0)

    # ── Stage 3: Area memory Pc boost ─────────────────────────────────────────
    area_boost, area_hint = 0.0, None
    if lat and lng:
        area_boost, area_hint = await app_state.adaptive.get_pc_boost_at_location(
            user_id, lat, lng
        )
        if area_boost > 0:
            # Record scored hazard at this location for learning
            for h in scored_hazards[:1]:
                asyncio.create_task(
                    app_state.adaptive.record_hazard_at_location(
                        user_id, lat, lng,
                        str(getattr(h, "hazard_type", "unknown")),
                        pc_score,
                    )
                )

    # ── Stage 4: Moral Governor ───────────────────────────────────────────────
    from services.moral_governor import (
        GovernorInput, UserIntent, LocationContext, TimeOfDay,
        build_governor_input_from_analysis
    )

    gov_input = build_governor_input_from_analysis(
        session_id=session_id,
        user_id=user_id,
        frame_id=frame_id,
        pc_score=pc_score,
        hazards=scored_hazards,
        user_velocity=velocity,
        override_threshold=thresholds.override,
        warning_threshold=thresholds.warning,
        area_boost=area_boost,
        area_hint=area_hint,
        stationary_for_s=session_state.stationary_for_s if session_state else 0.0,
    )

    # Update intent from client message
    intent_map = {
        "walking":       UserIntent.WALKING,
        "crossing_road": UserIntent.CROSSING,
        "crossing":      UserIntent.CROSSING,
        "turning_left":  UserIntent.TURNING_LEFT,
        "turning_right": UserIntent.TURNING_RIGHT,
        "stopped":       UserIntent.STOPPED,
    }
    gov_input.user_intent = intent_map.get(intent.lower(), UserIntent.WALKING)

    trace = app_state.governor.evaluate(gov_input)

    # ── Build response dict ────────────────────────────────────────────────────
    objects_out = [
        {
            "class_name":   d.class_name,
            "confidence":   round(d.confidence, 3),
            "distance_m":   d.distance_m,
            "position":     d.position_in_frame.value if hasattr(d, "position_in_frame") else d.position,
            "movement":     str(d.movement_vector),
            "threat":       str(d.threat_category),
        }
        for d in detections
    ]

    return {
        "pc_score":         round(pc_score, 4),
        "decision":         trace.decision.value,
        "haptic_pattern":   trace.haptic.value,
        "voice_message":    trace.voice_message,
        "detected_objects": objects_out,
        "area_memory_alert": area_hint is not None,
        "confidence":       trace.confidence,
        "rules_triggered":  trace.rules_triggered,
        "guardian_summary": trace.guardian_summary,
    }


# ═════════════════════════════════════════════════════════════════════════════
# Disconnect handler — triggers adaptive learning
# ═════════════════════════════════════════════════════════════════════════════

async def _on_disconnect(
    pool:       ConnectionPool,
    app_state,
    user_id:    str,
    session_id: str,
) -> None:
    """
    Called on any disconnect (clean or crash).
    Releases the connection, triggers adaptive end-of-session processing.
    """
    state = await pool.release(user_id, resumable=True)
    if not state:
        return

    duration_min = (time.monotonic() - state.connected_at) / 60.0

    log.info(
        "ws.session_ended",
        user_id=user_id,
        session_id=session_id,
        frames=state.frames_processed,
        overrides=state.total_overrides,
        duration_min=round(duration_min, 1),
    )

    # Fire-and-forget background adaptive processing
    asyncio.create_task(
        app_state.adaptive.process_session_end(
            user_id=user_id,
            session_id=session_id,
            total_overrides_fired=state.total_overrides,
            confirmed_incidents=0,      # resolved post-session via feedback
            false_negatives=0,
            duration_min=duration_min,
            distance_m=state.distance_m,
            avg_speed_mps=state.last_velocity,
        )
    )

    app_state.governor.cleanup_session(session_id)


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

async def _heartbeat_loop(ws: WebSocket, session_id: str) -> None:
    """Send ping every HEARTBEAT_INTERVAL_S; close on failure."""
    try:
        while True:
            await asyncio.sleep(HEARTBEAT_INTERVAL_S)
            await ws.send_json({"type": "ping", "session_id": session_id,
                                "ts": datetime.now(timezone.utc).isoformat()})
    except Exception:
        pass  # connection already closed; suppressed


async def _frame_receiver(ws: WebSocket):
    """Async generator: yield raw messages from client."""
    while True:
        msg = await ws.receive()
        if msg["type"] == "websocket.disconnect":
            break
        if "text" in msg:
            yield msg["text"]
        elif "bytes" in msg:
            yield msg["bytes"]


def _parse_frame_message(raw) -> Optional[tuple[bytes, dict]]:
    """
    Parse the incoming client frame message.
    Supports:
      JSON: {"frame": "<base64>", "user_intent": ..., "velocity": ..., "location": {lat, lng}}
      Raw bytes: treated as JPEG/PNG frame with no metadata.
    """
    try:
        if isinstance(raw, bytes):
            return raw, {}

        payload = json.loads(raw)

        frame_b64 = payload.get("frame")
        if frame_b64:
            frame_bytes = base64.b64decode(frame_b64)
        else:
            return None

        meta = {
            "user_intent": payload.get("user_intent", "walking"),
            "velocity":    float(payload.get("velocity", 0.0)),
            "lat":         float(payload.get("location", {}).get("lat", 0.0)),
            "lng":         float(payload.get("location", {}).get("lng", 0.0)),
        }
        return frame_bytes, meta

    except Exception as exc:
        log.warning("ws.parse_error", exc=str(exc))
        return None


async def _send_json(ws: WebSocket, data: dict) -> None:
    await ws.send_text(json.dumps(data, default=str))


async def _send_error(ws: WebSocket, code: str, message: str) -> None:
    await _send_json(ws, asdict(ErrorResponse(code=code, message=message)))
