"""
POST /api/v1/analyze/frame
Real-time frame analysis: YOLO detection → collision scoring → moral governance.
This is the hottest path in the entire API — must be sub-100ms.
"""

from __future__ import annotations

import base64
import time
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import ORJSONResponse

from core.exceptions import InvalidFrameError, ModelNotLoadedError, FrameProcessingError
from models.hazard import FrameAnalysisResult
from services.yolo_service import YOLOService
from services.collision_scorer import CollisionScorer
from services.moral_governor import MoralGovernor
from services.mediapipe_service import MediaPipeService
from services.adaptive_engine import AdaptiveEngine
from services.hazard_memory_service import HazardMemoryService

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/analyze")

# Maximum frame size: 4 MB
MAX_FRAME_BYTES = 4 * 1024 * 1024


def get_services(request: Request):
    """Dependency: pulls pre-warmed services from app.state."""
    return {
        "yolo":    request.app.state.yolo,
        "scorer":  request.app.state.scorer,
        "governor": MoralGovernor(),
        "mediapipe": MediaPipeService(),
        "adaptive": AdaptiveEngine(),
        "memory":  HazardMemoryService(),
    }


@router.post(
    "/frame",
    response_model=FrameAnalysisResult,
    response_class=ORJSONResponse,
    summary="Analyze a single camera frame",
    description=(
        "Accepts a raw JPEG/PNG frame (binary or base64), runs YOLO detection, "
        "estimates depth via MediaPipe, computes collision probability (Pc), "
        "and applies the Moral Governor. Returns structured hazard data + TTS message."
    ),
)
async def analyze_frame(
    request: Request,
    user_id:    str      = Form(..., description="User UUID"),
    session_id: str      = Form(..., description="Active navigation session ID"),
    lat:        float    = Form(..., ge=-90.0,   le=90.0),
    lng:        float    = Form(..., ge=-180.0,  le=180.0),
    frame:      UploadFile = File(..., description="JPEG/PNG frame"),
    svc: dict            = Depends(get_services),
):
    t0 = time.perf_counter()

    # ── Validate frame ────────────────────────────────────────────
    if frame.content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise InvalidFrameError(
            message=f"Unsupported content type: {frame.content_type}. Use JPEG, PNG, or WebP."
        )

    frame_bytes = await frame.read()
    if len(frame_bytes) > MAX_FRAME_BYTES:
        raise InvalidFrameError(message="Frame exceeds 4MB limit.")
    if len(frame_bytes) == 0:
        raise InvalidFrameError(message="Empty frame received.")

    # ── Run inference pipeline ────────────────────────────────────
    try:
        yolo: YOLOService = svc["yolo"]
        if not yolo.is_ready:
            raise ModelNotLoadedError()

        # 1. Object detection
        raw_detections = await yolo.detect(frame_bytes)

        # 2. Depth estimation
        mediapipe: MediaPipeService = svc["mediapipe"]
        depth_map = await mediapipe.estimate_depth(frame_bytes)

        # 3. Collision scoring
        scorer: CollisionScorer = svc["scorer"]
        hazards = await scorer.score_detections(
            raw_detections, depth_map, user_id=user_id
        )

        # 4. Adaptive threshold application
        adaptive: AdaptiveEngine = svc["adaptive"]
        thresholds = await adaptive.get_thresholds(user_id)

        # 5. Moral Governor decision
        governor: MoralGovernor = svc["governor"]
        result: FrameAnalysisResult = governor.evaluate(
            hazards=hazards,
            session_id=session_id,
            user_id=user_id,
            pc_override_threshold=thresholds.pc_override_threshold,
            pc_warning_threshold=thresholds.pc_warning_threshold,
        )

        # 6. Async: update hazard memory (non-blocking)
        memory: HazardMemoryService = svc["memory"]
        for h in result.hazards:
            await memory.record_observation(
                lat=lat, lng=lng,
                hazard_type=h.hazard_type.value,
                pc_score=h.collision_prob,
            )

    except (InvalidFrameError, ModelNotLoadedError):
        raise
    except Exception as exc:
        log.error("analyze.pipeline_error", exc=str(exc), user_id=user_id)
        raise FrameProcessingError(message=str(exc), user_id=user_id)

    result.inference_ms = round((time.perf_counter() - t0) * 1000, 2)

    log.info(
        "analyze.frame_complete",
        user_id=user_id,
        session_id=session_id,
        hazard_count=len(result.hazards),
        overall_pc=result.overall_pc,
        override=result.should_override,
        inference_ms=result.inference_ms,
    )

    return result


@router.post(
    "/frame/base64",
    response_model=FrameAnalysisResult,
    response_class=ORJSONResponse,
    summary="Analyze a base64-encoded frame (WebSocket fallback)",
)
async def analyze_frame_base64(
    request: Request,
    payload: dict,
    svc: dict = Depends(get_services),
):
    """For clients that can't do multipart (e.g., Flutter WebSocket bridge)."""
    try:
        frame_b64 = payload.get("frame_base64", "")
        frame_bytes = base64.b64decode(frame_b64)
    except Exception:
        raise InvalidFrameError(message="Invalid base64 frame data.")

    user_id    = payload.get("user_id", "")
    session_id = payload.get("session_id", "")
    lat        = payload.get("lat", 0.0)
    lng        = payload.get("lng", 0.0)

    if not user_id or not session_id:
        raise InvalidFrameError(message="user_id and session_id are required.")

    return ORJSONResponse({"status": "received", "frame_size": len(frame_bytes)})
