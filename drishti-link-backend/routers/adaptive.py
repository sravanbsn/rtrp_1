"""
Adaptive AI learning endpoints.
Accepts user feedback to tune per-user collision thresholds.
"""
from __future__ import annotations

from typing import Literal, Optional

import structlog
from fastapi import APIRouter, status
from pydantic import BaseModel, Field

from services.adaptive_engine import AdaptiveEngine
from services.user_profile_service import UserProfileService
from models.user_profile import ThresholdProfile

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/adaptive")


class FeedbackEvent(BaseModel):
    user_id:      str
    session_id:   str
    alert_id:     Optional[str] = None
    frame_id:     Optional[str] = None
    feedback_type: Literal[
        "false_positive",   # AI stopped Arjun but there was no real hazard
        "false_negative",   # AI missed a hazard
        "correct_override", # AI correctly stopped Arjun
        "correct_warning",  # AI correctly warned
        "too_sensitive",    # Warnings too frequent
        "not_sensitive_enough",
    ]
    pc_at_event:  Optional[float] = Field(None, ge=0.0, le=1.0)
    notes:        Optional[str]   = None


class FeedbackResponse(BaseModel):
    accepted:           bool
    new_thresholds:     ThresholdProfile
    samples_collected:  int
    threshold_updated:  bool
    message:            str


class ThresholdOverrideRequest(BaseModel):
    """Guardian can manually override AI sensitivity for a user."""
    user_id:               str
    pc_override_threshold: float = Field(..., ge=0.10, le=0.95)
    pc_warning_threshold:  float = Field(..., ge=0.05, le=0.80)
    reason:                Optional[str] = None


@router.post(
    "/feedback",
    response_model=FeedbackResponse,
    summary="Submit user feedback for AI threshold tuning",
    description=(
        "Accepts labeled feedback events (false positive / correct override etc.) "
        "and nudges per-user Pc thresholds via the adaptive learning engine."
    ),
)
async def submit_feedback(body: FeedbackEvent) -> FeedbackResponse:
    engine = AdaptiveEngine()
    result = await engine.process_feedback(
        user_id=body.user_id,
        feedback_type=body.feedback_type,
        pc_at_event=body.pc_at_event,
    )

    log.info(
        "adaptive.feedback_received",
        user_id=body.user_id,
        feedback_type=body.feedback_type,
        threshold_updated=result["updated"],
        samples=result["samples"],
    )
    return FeedbackResponse(
        accepted=True,
        new_thresholds=ThresholdProfile(**result["thresholds"]),
        samples_collected=result["samples"],
        threshold_updated=result["updated"],
        message=(
            "Threshold updated." if result["updated"]
            else f"Feedback recorded. Need {result['needed']} more samples before tuning."
        ),
    )


@router.get(
    "/thresholds/{user_id}",
    response_model=ThresholdProfile,
    summary="Get current AI thresholds for a user",
)
async def get_thresholds(user_id: str) -> ThresholdProfile:
    engine = AdaptiveEngine()
    return await engine.get_thresholds(user_id)


@router.put(
    "/thresholds/{user_id}",
    response_model=ThresholdProfile,
    summary="Guardian manual threshold override",
)
async def override_thresholds(
    user_id: str, body: ThresholdOverrideRequest
) -> ThresholdProfile:
    if body.pc_warning_threshold >= body.pc_override_threshold:
        from fastapi import HTTPException
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Warning threshold must be less than override threshold.",
        )
    engine = AdaptiveEngine()
    thresholds = await engine.set_thresholds(
        user_id=user_id,
        override=body.pc_override_threshold,
        warning=body.pc_warning_threshold,
    )
    log.info(
        "adaptive.manual_override",
        user_id=user_id,
        override=body.pc_override_threshold,
        warning=body.pc_warning_threshold,
        reason=body.reason,
    )
    return thresholds


@router.get(
    "/stats/{user_id}",
    summary="Get adaptive learning statistics for a user",
)
async def get_adaptive_stats(user_id: str) -> dict:
    engine = AdaptiveEngine()
    return await engine.get_stats(user_id)
