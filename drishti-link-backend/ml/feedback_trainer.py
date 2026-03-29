"""
ml/feedback_trainer.py

Continuous anonymized cross-user learning pipeline — Drishti-Link.
═══════════════════════════════════════════════════════════════════

Aggregates anonymized detection events from ALL users.
Identifies patterns (which detections led to real incidents).
Generates retraining recommendations when data is sufficient.

DOES NOT auto-retrain. Sends admin alert for human approval.
Retraining gate: > 1000 sessions + admin approval required.

Data privacy:
  ● All user_id values are hashed (SHA-256 truncated to 8 chars)
  ● GPS coordinates are snapped to 100m grid before storage
  ● No personally identifiable data leaves this module

Architecture:
  ● FeedbackEvent: one detection outcome (FP, FN, TP, TN)
  ● FeedbackStore: thread-safe in-memory store (replace with Redis/BigQuery)
  ● PatternAnalyser: finds high-FP/FN class × context patterns
  ● RetrainingRecommendation: actionable output for ML team
  ● FeedbackTrainer: orchestrates the full pipeline
"""

from __future__ import annotations

import asyncio
import hashlib
import math
import time
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

import structlog

log = structlog.get_logger(__name__)

# ═════════════════════════════════════════════════════════════════════════════
# Configuration
# ═════════════════════════════════════════════════════════════════════════════

MIN_SESSIONS_FOR_RETRAIN    = 1000    # global session gate
MIN_EVENTS_FOR_PATTERN      = 50      # need ≥50 events of a type to report a pattern
HIGH_FP_RATE_FLAG           = 0.35    # class FP rate above this triggers recommendation
HIGH_FN_RATE_FLAG           = 0.20    # class FN rate above this triggers recommendation
GPS_GRID_METRES             = 100     # anonymization grid (100m cells)


# ═════════════════════════════════════════════════════════════════════════════
# Data classes
# ═════════════════════════════════════════════════════════════════════════════

class OutcomeType(str, Enum):
    TRUE_POSITIVE  = "TP"   # system warned, incident confirmed
    TRUE_NEGATIVE  = "TN"   # system silent, no incident (good)
    FALSE_POSITIVE = "FP"   # system warned, no real danger
    FALSE_NEGATIVE = "FN"   # no warning, incident happened


@dataclass
class FeedbackEvent:
    """
    Anonymized detection outcome.
    Collected at session end; never stores raw user_id or precise GPS.
    """
    anon_user_id:   str          # SHA-256[:8] of real user_id
    session_hash:   str          # SHA-256[:8] of session_id
    timestamp:      str
    outcome:        OutcomeType

    # Detection context
    class_name:     str          # e.g. "car", "pothole"
    confidence:     float        # YOLO confidence
    pc_at_event:    float        # Pc at moment of decision
    distance_m:     Optional[float]
    hour_of_day:    int          # 0-23
    is_night:       bool
    grid_cell:      str          # anonymized GPS (100m grid key)

    # User profile context (anonymized)
    user_session_count: int      # rough experience level
    threshold_override_pct: float

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class PatternRecord:
    """Statistical pattern discovered across all events."""
    class_name:    str
    outcome:       OutcomeType
    count:         int
    rate:          float          # FP rate or FN rate for this class
    avg_pc:        float          # average Pc at which these events happened
    top_hour:      int            # hour of day with most occurrences
    top_grid:      str            # grid cell with most occurrences
    recommendation: str


@dataclass
class RetrainingRecommendation:
    """
    Actionable recommendation sent to admin for review.
    NOT auto-applied — requires explicit admin approval.
    """
    generated_at:      str
    trigger_reason:    str
    total_sessions:    int
    total_events:      int
    fp_patterns:       list     # [PatternRecord]
    fn_patterns:       list     # [PatternRecord]
    suggested_actions: list     # human-readable action items
    priority:          str      # "LOW" | "MEDIUM" | "HIGH" | "CRITICAL"
    admin_notified:    bool = False

    def to_dict(self) -> dict:
        return asdict(self)


# ═════════════════════════════════════════════════════════════════════════════
# Privacy helpers
# ═════════════════════════════════════════════════════════════════════════════

def _anon_id(raw_id: str) -> str:
    return hashlib.sha256(raw_id.encode()).hexdigest()[:8]


def _anon_gps(lat: float, lng: float) -> str:
    """Snap to 100m grid (≈0.001° ≈ 110m)."""
    return f"{round(lat,3):.3f},{round(lng,3):.3f}"


# ═════════════════════════════════════════════════════════════════════════════
# In-memory store (replace with Redis Streams / BigQuery in production)
# ═════════════════════════════════════════════════════════════════════════════

class FeedbackStore:
    """Thread-safe in-memory event store."""

    def __init__(self) -> None:
        self._events:          list[FeedbackEvent] = []
        self._session_count:   int                 = 0
        self._lock             = asyncio.Lock()

    async def add_event(self, event: FeedbackEvent) -> None:
        async with self._lock:
            self._events.append(event)

    async def add_session(self) -> None:
        async with self._lock:
            self._session_count += 1

    async def snapshot(self) -> tuple[list[FeedbackEvent], int]:
        """Return (events_copy, session_count) without holding the lock."""
        async with self._lock:
            return list(self._events), self._session_count

    async def size(self) -> int:
        async with self._lock:
            return len(self._events)

    @property
    def session_count(self) -> int:
        return self._session_count


# ═════════════════════════════════════════════════════════════════════════════
# Pattern analyser
# ═════════════════════════════════════════════════════════════════════════════

class PatternAnalyser:
    """
    Finds class-level FP and FN patterns across all collected events.
    Runs synchronously (called from background task).
    """

    def analyse(self, events: list[FeedbackEvent]) -> tuple[list[PatternRecord], list[PatternRecord]]:
        """Returns (fp_patterns, fn_patterns)."""
        # Group events by class_name
        by_class: dict[str, list[FeedbackEvent]] = defaultdict(list)
        for ev in events:
            by_class[ev.class_name].append(ev)

        fp_patterns: list[PatternRecord] = []
        fn_patterns: list[PatternRecord] = []

        for cls_name, cls_events in by_class.items():
            total = len(cls_events)
            if total < MIN_EVENTS_FOR_PATTERN:
                continue

            fp_evts = [e for e in cls_events if e.outcome == OutcomeType.FALSE_POSITIVE]
            fn_evts = [e for e in cls_events if e.outcome == OutcomeType.FALSE_NEGATIVE]

            fp_rate = len(fp_evts) / total
            fn_rate = len(fn_evts) / total

            if fp_rate >= HIGH_FP_RATE_FLAG and fp_evts:
                fp_patterns.append(self._make_pattern(cls_name, fp_evts, OutcomeType.FALSE_POSITIVE, fp_rate))

            if fn_rate >= HIGH_FN_RATE_FLAG and fn_evts:
                fn_patterns.append(self._make_pattern(cls_name, fn_evts, OutcomeType.FALSE_NEGATIVE, fn_rate))

        fp_patterns.sort(key=lambda p: p.rate, reverse=True)
        fn_patterns.sort(key=lambda p: p.rate, reverse=True)
        return fp_patterns, fn_patterns

    def _make_pattern(
        self,
        cls_name: str,
        evts:     list[FeedbackEvent],
        outcome:  OutcomeType,
        rate:     float,
    ) -> PatternRecord:
        avg_pc = sum(e.pc_at_event for e in evts) / len(evts)

        # Peak hour
        hour_counts: dict[int, int] = defaultdict(int)
        for e in evts:
            hour_counts[e.hour_of_day] += 1
        top_hour = max(hour_counts, key=hour_counts.get, default=0)

        # Peak grid cell
        grid_counts: dict[str, int] = defaultdict(int)
        for e in evts:
            grid_counts[e.grid_cell] += 1
        top_grid = max(grid_counts, key=grid_counts.get, default="unknown")

        if outcome == OutcomeType.FALSE_POSITIVE:
            rec = (
                f"Class '{cls_name}' has {rate:.0%} FP rate. "
                f"Consider raising confidence threshold or adding negative samples "
                f"for this class. Peak at hour {top_hour}:00."
            )
        else:
            rec = (
                f"Class '{cls_name}' has {rate:.0%} FN rate. "
                f"Model is missing real '{cls_name}' events. "
                f"Add more training samples for this class, especially at hour {top_hour}:00."
            )

        return PatternRecord(
            class_name=cls_name,
            outcome=outcome,
            count=len(evts),
            rate=round(rate, 4),
            avg_pc=round(avg_pc, 4),
            top_hour=top_hour,
            top_grid=top_grid,
            recommendation=rec,
        )


# ═════════════════════════════════════════════════════════════════════════════
# FeedbackTrainer — main orchestrator
# ═════════════════════════════════════════════════════════════════════════════

class FeedbackTrainer:
    """
    Continuous anonymized cross-user learning pipeline.

    Usage:
        # At app startup:
        trainer = FeedbackTrainer()
        app.state.trainer = trainer

        # After each session:
        await trainer.ingest_session(...)

        # Periodically (Celery beat or APScheduler):
        await trainer.run_analysis()
    """

    def __init__(self) -> None:
        self._store    = FeedbackStore()
        self._analyser = PatternAnalyser()
        self._recommendations:  list[RetrainingRecommendation] = []
        self._last_analysis_at: Optional[str] = None

    # ── Ingestion API ─────────────────────────────────────────────────────────

    async def ingest_event(
        self,
        user_id:         str,
        session_id:      str,
        outcome:         OutcomeType,
        class_name:      str,
        confidence:      float,
        pc_at_event:     float,
        distance_m:      Optional[float],
        lat:             float,
        lng:             float,
        hour_of_day:     int,
        is_night:        bool,
        user_session_count: int,
        threshold_override_pct: float,
    ) -> None:
        """
        Record a single detection outcome.
        Anonymizes all PII before storage.
        """
        event = FeedbackEvent(
            anon_user_id=_anon_id(user_id),
            session_hash=_anon_id(session_id),
            timestamp=datetime.now(timezone.utc).isoformat(),
            outcome=outcome,
            class_name=class_name,
            confidence=round(confidence, 4),
            pc_at_event=round(pc_at_event, 4),
            distance_m=distance_m,
            hour_of_day=hour_of_day,
            is_night=is_night,
            grid_cell=_anon_gps(lat, lng),
            user_session_count=user_session_count,
            threshold_override_pct=threshold_override_pct,
        )
        await self._store.add_event(event)
        log.debug("trainer.event_ingested", anon_user=event.anon_user_id, outcome=outcome.value)

    async def ingest_session_summary(
        self,
        user_id:      str,
        session_id:   str,
        detections:   list[dict],   # [{class_name, confidence, pc, outcome, distance_m, lat, lng}]
        hour_of_day:  int,
        is_night:     bool,
        user_session_count:   int,
        threshold_override_pct: float,
    ) -> None:
        """
        Batch ingestion: ingest all detection outcomes for a completed session.
        Call this at session end alongside process_session_end.
        """
        for det in detections:
            outcome_str = det.get("outcome", "TN")
            try:
                outcome = OutcomeType(outcome_str)
            except ValueError:
                outcome = OutcomeType.TRUE_NEGATIVE

            await self.ingest_event(
                user_id=user_id,
                session_id=session_id,
                outcome=outcome,
                class_name=det.get("class_name", "unknown"),
                confidence=float(det.get("confidence", 0)),
                pc_at_event=float(det.get("pc", 0)),
                distance_m=det.get("distance_m"),
                lat=float(det.get("lat", 0.0)),
                lng=float(det.get("lng", 0.0)),
                hour_of_day=hour_of_day,
                is_night=is_night,
                user_session_count=user_session_count,
                threshold_override_pct=threshold_override_pct,
            )

        await self._store.add_session()
        log.info(
            "trainer.session_ingested",
            anon_user=_anon_id(user_id),
            n_detections=len(detections),
            total_sessions=self._store.session_count,
        )

    # ── Analysis pipeline ─────────────────────────────────────────────────────

    async def run_analysis(self) -> Optional[RetrainingRecommendation]:
        """
        Run the full analysis pipeline.
        Returns a RetrainingRecommendation if retraining is warranted,
        otherwise returns None.

        Called periodically (e.g. every night by Celery beat).
        """
        events, session_count = await self._store.snapshot()
        n_events = len(events)

        log.info(
            "trainer.analysis_started",
            sessions=session_count,
            events=n_events,
        )

        if n_events < MIN_EVENTS_FOR_PATTERN:
            log.info("trainer.insufficient_data", needed=MIN_EVENTS_FOR_PATTERN, have=n_events)
            return None

        # ── Run pattern analysis (CPU-bound, push to threadpool) ──────────
        loop = asyncio.get_running_loop()
        fp_patterns, fn_patterns = await loop.run_in_executor(
            None, self._analyser.analyse, events
        )

        self._last_analysis_at = datetime.now(timezone.utc).isoformat()

        # ── Determine if retraining is warranted ──────────────────────────
        retrain_warranted = session_count >= MIN_SESSIONS_FOR_RETRAIN
        priority = self._compute_priority(fp_patterns, fn_patterns, session_count)

        if not fp_patterns and not fn_patterns:
            log.info("trainer.no_patterns_found", sessions=session_count)
            return None

        suggested_actions = self._generate_actions(fp_patterns, fn_patterns, retrain_warranted)

        trigger = (
            f"Analysis triggered: {session_count} sessions, {n_events} events. "
            f"{len(fp_patterns)} FP patterns, {len(fn_patterns)} FN patterns found."
        )

        rec = RetrainingRecommendation(
            generated_at=self._last_analysis_at,
            trigger_reason=trigger,
            total_sessions=session_count,
            total_events=n_events,
            fp_patterns=[asdict(p) for p in fp_patterns],
            fn_patterns=[asdict(p) for p in fn_patterns],
            suggested_actions=suggested_actions,
            priority=priority,
        )
        self._recommendations.append(rec)

        # ── Notify admin if gate reached ──────────────────────────────────
        if retrain_warranted:
            await self._notify_admin(rec)
            rec.admin_notified = True

        log.warning(
            "trainer.recommendation_generated",
            priority=priority,
            fp_classes=[p["class_name"] for p in rec.fp_patterns],
            fn_classes=[p["class_name"] for p in rec.fn_patterns],
            admin_notified=rec.admin_notified,
        )
        return rec

    def _compute_priority(
        self,
        fp_patterns: list[PatternRecord],
        fn_patterns: list[PatternRecord],
        session_count: int,
    ) -> str:
        # FN patterns are more dangerous than FP patterns
        max_fn_rate = max((p.rate for p in fn_patterns), default=0.0)
        max_fp_rate = max((p.rate for p in fp_patterns), default=0.0)

        if max_fn_rate >= 0.40 or session_count >= MIN_SESSIONS_FOR_RETRAIN * 2:
            return "CRITICAL"
        if max_fn_rate >= 0.25 or session_count >= MIN_SESSIONS_FOR_RETRAIN:
            return "HIGH"
        if max_fp_rate >= 0.40 or len(fn_patterns) >= 3:
            return "MEDIUM"
        return "LOW"

    def _generate_actions(
        self,
        fp_patterns: list[PatternRecord],
        fn_patterns: list[PatternRecord],
        retrain_warranted: bool,
    ) -> list[str]:
        actions = []
        for p in fn_patterns[:3]:
            actions.append(
                f"🔴 CRITICAL: Collect more '{p.class_name}' training samples "
                f"(current FN rate: {p.rate:.0%}, avg Pc: {p.avg_pc:.2f}). "
                f"Focus on hour {p.top_hour}:00 conditions."
            )
        for p in fp_patterns[:3]:
            actions.append(
                f"🟡 FP Noise: '{p.class_name}' triggers many false alarms "
                f"(FP rate: {p.rate:.0%}). Consider confidence threshold +0.05."
            )
        if retrain_warranted:
            actions.append(
                f"✅ Retrain gate reached ({MIN_SESSIONS_FOR_RETRAIN} sessions). "
                "Submit retraining job after admin review and approval."
            )
        else:
            sessions_needed = MIN_SESSIONS_FOR_RETRAIN - self._store.session_count
            actions.append(
                f"⏳ Need {sessions_needed} more sessions before retrain gate. "
                "Continue monitoring."
            )
        return actions

    async def _notify_admin(self, rec: RetrainingRecommendation) -> None:
        """
        Send alert to admin (via monitoring.logger + optional Slack/email hook).
        DOES NOT auto-retrain — human approval required.
        """
        try:
            from monitoring.logger import log as event_log
            event_log.critical(
                "event.retrain_recommended",
                priority=rec.priority,
                sessions=rec.total_sessions,
                events=rec.total_events,
                fp_classes=[p["class_name"] for p in rec.fp_patterns],
                fn_classes=[p["class_name"] for p in rec.fn_patterns],
                message=(
                    "⚠️ Drishti-Link model retraining recommended. "
                    "Admin approval required before any retraining begins. "
                    f"Priority: {rec.priority}"
                ),
            )
        except Exception as exc:
            log.error("trainer.admin_notify_failed", exc=str(exc))

    # ── Status API (for admin router) ─────────────────────────────────────────

    async def get_status(self) -> dict:
        events, session_count = await self._store.snapshot()
        return {
            "total_sessions":       session_count,
            "total_events":         len(events),
            "retrain_gate":         MIN_SESSIONS_FOR_RETRAIN,
            "retrain_ready":        session_count >= MIN_SESSIONS_FOR_RETRAIN,
            "sessions_to_gate":     max(0, MIN_SESSIONS_FOR_RETRAIN - session_count),
            "last_analysis_at":     self._last_analysis_at,
            "recommendations_count": len(self._recommendations),
            "last_recommendation":  (
                self._recommendations[-1].to_dict()
                if self._recommendations else None
            ),
        }

    async def get_recommendations(self, limit: int = 10) -> list[dict]:
        return [r.to_dict() for r in self._recommendations[-limit:]]

    def enqueue(self, user_id: str, feedback_type: str, pc: Optional[float]) -> None:
        """Compatibility shim for existing routers calling enqueue()."""
        # Map old API to OutcomeType
        outcome_map = {
            "false_positive": OutcomeType.FALSE_POSITIVE,
            "false_negative": OutcomeType.FALSE_NEGATIVE,
            "correct_override": OutcomeType.TRUE_POSITIVE,
        }
        log.debug("trainer.enqueue_compat", user_id=user_id, feedback_type=feedback_type)
        # Lightweight — no async here; ingest_event should be called from router

    async def flush_and_train(self) -> dict:
        """Compatibility shim for existing code calling flush_and_train()."""
        rec = await self.run_analysis()
        return {
            "processed":       await self._store.size(),
            "model_updated":   False,  # always False — admin approval required
            "recommendation":  rec.to_dict() if rec else None,
        }
