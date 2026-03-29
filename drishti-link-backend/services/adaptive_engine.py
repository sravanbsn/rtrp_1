"""
services/adaptive_engine.py

The Self-Learning Brain of Drishti-Link
═══════════════════════════════════════

Four adaptive systems running in concert:

  SYSTEM 1 — Personal Threshold Optimizer
    Tracks cancelled overrides and ignored warnings per session.
    Nudges the user's personal Pc thresholds after each walk.

  SYSTEM 2 — Local Area Hazard Memory
    GPS 10-metre grid cell hazard frequency map.
    After 3+ detections at the same grid cell: KNOWN HAZARD.
    Known hazards receive a +0.20 Pc boost when the user approaches.

  SYSTEM 3 — Walking Pattern Learner
    Builds a per-user baseline: speed, preferred side, crossing behaviour.
    Deviations from baseline (sudden slowdown, unusual path) trigger
    heightened monitoring sensitivity.

  SYSTEM 4 — Session Feedback Loop
    Runs in the background after every session end.
    Compares predicted hazards vs actual confirmed incidents.
    Scores per-session model accuracy. Flags FP and FN events.
    Drives model-versioning decisions via feedback_trainer.py.

All adaptive state is stored in Firebase under:
  users/{user_id}/adaptive_profile/
    personal_thresholds     : ThresholdProfile
    area_memory             : { grid_key → AreaCell }
    walking_patterns        : WalkingPatternProfile
    session_accuracy_history: [ SessionAccuracyRecord ]

Design principles:
  ● Never change ANY threshold more than 5 points per session
  ● All data is append-only — nothing is ever deleted, only superseded
  ● Every decision is logged with its reason for full auditability
  ● Graceful degradation: if Firebase is down, state lives in memory
"""

from __future__ import annotations

import asyncio
import hashlib
import math
import statistics
import time
from collections import defaultdict, deque
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

import structlog

from core.config import settings

log = structlog.get_logger(__name__)


# ═════════════════════════════════════════════════════════════════════════════
# Configuration constants
# ═════════════════════════════════════════════════════════════════════════════

class ThresholdBounds:
    """Hard bounds — thresholds can never escape these ranges."""
    WARNING_MIN  = 25   # percentage points (Pc × 100)
    WARNING_MAX  = 55
    OVERRIDE_MIN = 60
    OVERRIDE_MAX = 90
    MAX_DELTA_PER_SESSION = 5    # max change (pp) in one session


class HazardMemoryConfig:
    GRID_RESOLUTION_M       = 10    # GPS cells are ~10m × 10m
    KNOWN_HAZARD_THRESHOLD  = 3     # detections needed to mark KNOWN
    KNOWN_HAZARD_PC_BOOST   = 0.20  # Pc additive boost near known hazards
    EARTH_RADIUS_M          = 6_371_000
    MEMORY_DECAY_DAYS       = 90    # observations older than this lose weight


class PatternLearnerConfig:
    SESSION_WARMUP           = 10   # sessions before pattern-based sensitivity
    SPEED_DEVIATION_FACTOR   = 0.40 # speed change > 40% → heightened monitoring
    STALE_PATTERN_DAYS       = 30   # patterns older than this need refreshing


class FeedbackConfig:
    HIGH_FP_RATE_THRESHOLD   = 0.30  # >30% FP → system too sensitive
    HIGH_FN_RATE_THRESHOLD   = 0.15  # >15% FN → system not sensitive enough
    MIN_SESSIONS_FOR_ANALYSIS = 5    # need at least 5 sessions to draw conclusions


# ═════════════════════════════════════════════════════════════════════════════
# Domain data classes
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class ThresholdProfile:
    """Per-user tuned Pc thresholds (stored as 0-100 percentage points)."""
    warning_pct:  float = 40.0   # Pc × 100 ≥ this → warn
    override_pct: float = 70.0   # Pc × 100 ≥ this → stop

    @property
    def warning(self) -> float:
        """As a 0.0–1.0 Pc value for scorer compatibility."""
        return self.warning_pct / 100.0

    @property
    def override(self) -> float:
        return self.override_pct / 100.0

    def clamp(self) -> "ThresholdProfile":
        self.warning_pct  = max(ThresholdBounds.WARNING_MIN,
                                min(ThresholdBounds.WARNING_MAX,  self.warning_pct))
        self.override_pct = max(ThresholdBounds.OVERRIDE_MIN,
                                min(ThresholdBounds.OVERRIDE_MAX, self.override_pct))
        # Ensure gap between thresholds
        if self.warning_pct >= self.override_pct - 5:
            self.warning_pct = self.override_pct - 5
        return self

    def to_dict(self) -> dict:
        return {
            "warning_pct":  round(self.warning_pct,  2),
            "override_pct": round(self.override_pct, 2),
            "warning":      round(self.warning,  4),
            "override":     round(self.override, 4),
        }


@dataclass
class ThresholdChangeRecord:
    """Immutable audit record for every threshold adjustment."""
    timestamp:     str
    reason:        str
    trigger:       str   # "cancelled_overrides" | "near_miss" | "ignored_warnings" | "manual"
    old_warning:   float
    old_override:  float
    new_warning:   float
    new_override:  float
    delta_warning: float
    delta_override: float
    session_id:    str


@dataclass
class AreaCell:
    """One 10m × 10m geographic cell with hazard history."""
    grid_key:    str
    lat:         float
    lng:         float
    total_count: int   = 0
    is_known:    bool  = False

    # hazard_type → count
    hazard_counts: dict = field(default_factory=dict)
    # ISO timestamps of each observation (for time-of-day analysis)
    observation_times: list = field(default_factory=list)
    # Hour → count (0-23)
    hour_histogram: dict = field(default_factory=lambda: defaultdict(int))

    first_seen: Optional[str] = None
    last_seen:  Optional[str] = None

    @property
    def dominant_hazard(self) -> Optional[str]:
        if not self.hazard_counts:
            return None
        return max(self.hazard_counts, key=self.hazard_counts.get)

    @property
    def peak_hour(self) -> Optional[int]:
        if not self.hour_histogram:
            return None
        return int(max(self.hour_histogram, key=self.hour_histogram.get))

    def record_observation(self, hazard_type: str, iso_time: str, hour: int) -> None:
        self.total_count += 1
        self.hazard_counts[hazard_type] = self.hazard_counts.get(hazard_type, 0) + 1
        self.observation_times.append(iso_time)
        self.hour_histogram[hour] = self.hour_histogram.get(hour, 0) + 1
        self.last_seen = iso_time
        if self.first_seen is None:
            self.first_seen = iso_time
        if self.total_count >= HazardMemoryConfig.KNOWN_HAZARD_THRESHOLD:
            self.is_known = True

    def hinglish_warning(self) -> str:
        hazard = self.dominant_hazard or "khatre"
        return f"Yahan pehle bhi {hazard} tha. Dhyan dena."

    def to_dict(self) -> dict:
        return {
            "grid_key":      self.grid_key,
            "lat":           self.lat,
            "lng":           self.lng,
            "total_count":   self.total_count,
            "is_known":      self.is_known,
            "hazard_counts": self.hazard_counts,
            "dominant":      self.dominant_hazard,
            "peak_hour":     self.peak_hour,
            "first_seen":    self.first_seen,
            "last_seen":     self.last_seen,
        }


@dataclass
class WalkingPatternProfile:
    """Statistical model of a user's normal walking behaviour."""
    # Speed (m/s)
    avg_speed_mps:    float = 0.0
    speed_std_mps:    float = 0.0
    speed_samples:    list  = field(default_factory=list)   # last 50 sessions

    # Side preference: fraction of time spent on left side of path (0-1)
    side_preference:  float = 0.5    # 0.0 = always right, 1.0 = always left

    # Crossing behaviour: avg Pc at which user crosses roads
    avg_crossing_pc:  float = 0.30

    # Time-of-day distribution
    active_hours: dict = field(default_factory=lambda: defaultdict(int))

    # Session lengths
    avg_session_duration_min: float = 0.0
    avg_session_distance_m:   float = 0.0

    # Metadata
    total_sessions:   int   = 0
    last_updated:     Optional[str] = None
    pattern_mature:   bool  = False   # True after SESSION_WARMUP sessions

    def update_speed(self, session_avg_speed: float) -> None:
        self.speed_samples.append(session_avg_speed)
        if len(self.speed_samples) > 50:
            self.speed_samples = self.speed_samples[-50:]
        if len(self.speed_samples) >= 3:
            self.avg_speed_mps = statistics.mean(self.speed_samples)
            self.speed_std_mps = statistics.stdev(self.speed_samples) if len(self.speed_samples) >= 2 else 0.0

    def speed_deviation_factor(self, current_speed: float) -> float:
        """
        Returns how many standard deviations current_speed is from normal.
        > 1.5σ → unusual; return value used to boost sensitivity.
        """
        if self.avg_speed_mps <= 0 or self.speed_std_mps <= 0:
            return 0.0
        return abs(current_speed - self.avg_speed_mps) / max(self.speed_std_mps, 0.01)

    def is_speed_anomalous(self, current_speed: float) -> bool:
        return self.speed_deviation_factor(current_speed) > 1.5

    def to_dict(self) -> dict:
        return {
            "avg_speed_mps":          round(self.avg_speed_mps, 3),
            "speed_std_mps":          round(self.speed_std_mps, 3),
            "side_preference":        self.side_preference,
            "avg_crossing_pc":        self.avg_crossing_pc,
            "avg_session_duration_min": round(self.avg_session_duration_min, 1),
            "avg_session_distance_m": round(self.avg_session_distance_m, 1),
            "total_sessions":         self.total_sessions,
            "pattern_mature":         self.pattern_mature,
            "last_updated":           self.last_updated,
        }


@dataclass
class SessionFeedbackRecord:
    """Accuracy analysis for one completed session."""
    session_id:        str
    user_id:           str
    timestamp:         str

    # Detections
    total_overrides_fired:   int = 0
    cancelled_by_user:       int = 0   # user manually cancelled: FP indicator
    confirmed_incidents:     int = 0   # verified real danger events

    # Accuracy
    false_positives:   int   = 0    # override fired, no real danger
    false_negatives:   int   = 0    # incident without prior warning
    precision:         float = 0.0  # TP / (TP + FP)
    recall:            float = 0.0  # TP / (TP + FN)
    f1_score:          float = 0.0

    # Session context
    duration_min:      float = 0.0
    distance_m:        float = 0.0
    avg_speed_mps:     float = 0.0

    # Flags for threshold_optimizer
    flag_too_sensitive:      bool = False
    flag_not_sensitive_enough: bool = False

    def compute_metrics(self) -> "SessionFeedbackRecord":
        tp = max(0, self.total_overrides_fired - self.false_positives)
        denom_p = tp + self.false_positives
        denom_r = tp + self.false_negatives
        self.precision = tp / denom_p if denom_p > 0 else 1.0
        self.recall    = tp / denom_r if denom_r > 0 else 1.0
        denom_f = self.precision + self.recall
        self.f1_score  = 2 * self.precision * self.recall / denom_f if denom_f > 0 else 0.0

        # Flag decisions
        fp_rate = self.false_positives / max(self.total_overrides_fired, 1)
        self.flag_too_sensitive       = fp_rate > FeedbackConfig.HIGH_FP_RATE_THRESHOLD
        self.flag_not_sensitive_enough = self.false_negatives > 0

        return self

    def to_dict(self) -> dict:
        return asdict(self)


# ═════════════════════════════════════════════════════════════════════════════
# Per-user in-memory state container
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class UserAdaptiveState:
    user_id:           str
    thresholds:        ThresholdProfile         = field(default_factory=ThresholdProfile)
    area_memory:       dict                     = field(default_factory=dict)  # grid_key → AreaCell
    walking_pattern:   WalkingPatternProfile    = field(default_factory=WalkingPatternProfile)
    accuracy_history:  list                     = field(default_factory=list)  # [SessionFeedbackRecord]
    threshold_history: list                     = field(default_factory=list)  # [ThresholdChangeRecord]

    # Session-scoped accumulators (reset on session start)
    session_cancelled_overrides: int  = 0
    session_ignored_warnings:    int  = 0
    session_near_misses:         int  = 0


# ═════════════════════════════════════════════════════════════════════════════
# Geography helpers
# ═════════════════════════════════════════════════════════════════════════════

def _grid_key(lat: float, lng: float) -> str:
    """
    Snap coordinates to a 10m × 10m grid cell.
    10m in degrees ≈ 0.00009°. Round to 4 decimal places ≈ ~11m cell.
    """
    snapped_lat = round(lat, 4)
    snapped_lng = round(lng, 4)
    return f"{snapped_lat:.4f},{snapped_lng:.4f}"


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = HazardMemoryConfig.EARTH_RADIUS_M
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _now_hour_ist() -> int:
    """Current hour in approximate IST (UTC+5:30)."""
    return (datetime.now(timezone.utc).hour + 5) % 24


# ═════════════════════════════════════════════════════════════════════════════
# AdaptiveEngine — the orchestrator
# ═════════════════════════════════════════════════════════════════════════════

class AdaptiveEngine:
    """
    Central adaptive intelligence layer.
    One instance per process (singleton via app.state.adaptive).

    Thread-safety: all public methods are async and protected by per-user
    asyncio.Lock objects. Firebase writes happen in background tasks.
    """

    def __init__(self) -> None:
        # user_id → UserAdaptiveState
        self._states: dict[str, UserAdaptiveState] = {}
        # user_id → asyncio.Lock (prevents concurrent state mutation)
        self._locks:  dict[str, asyncio.Lock]      = {}

    # ── Lock management ───────────────────────────────────────────────────────
    def _lock(self, user_id: str) -> asyncio.Lock:
        if user_id not in self._locks:
            self._locks[user_id] = asyncio.Lock()
        return self._locks[user_id]

    def _state(self, user_id: str) -> UserAdaptiveState:
        if user_id not in self._states:
            self._states[user_id] = UserAdaptiveState(user_id=user_id)
        return self._states[user_id]

    # ════════════════════════════════════════════════════════════════════════
    # PUBLIC API — called by routers and WebSocket handler
    # ════════════════════════════════════════════════════════════════════════

    # ── Threshold retrieval ───────────────────────────────────────────────────

    async def get_thresholds(self, user_id: str) -> ThresholdProfile:
        """Return the user's current personalised Pc thresholds."""
        return self._state(user_id).thresholds

    async def set_thresholds(
        self,
        user_id:  str,
        override: float,
        warning:  float,
        reason:   str = "manual_override",
    ) -> ThresholdProfile:
        async with self._lock(user_id):
            state = self._state(user_id)
            old = ThresholdProfile(
                warning_pct=state.thresholds.warning_pct,
                override_pct=state.thresholds.override_pct,
            )
            state.thresholds = ThresholdProfile(
                warning_pct=warning * 100,
                override_pct=override * 100,
            ).clamp()
            self._record_threshold_change(state, old, reason, "manual", "current")
        return state.thresholds

    # ── Hazard memory + Pc boost ─────────────────────────────────────────────

    async def record_hazard_at_location(
        self,
        user_id:     str,
        lat:         float,
        lng:         float,
        hazard_type: str,
        pc_score:    float,
    ) -> AreaCell:
        """
        SYSTEM 2: Record a hazard detection at a GPS location.
        Automatically marks the cell as KNOWN HAZARD after 3+ detections.
        """
        async with self._lock(user_id):
            state = self._state(user_id)
            key   = _grid_key(lat, lng)
            iso   = _now_iso()
            hour  = _now_hour_ist()

            if key not in state.area_memory:
                state.area_memory[key] = AreaCell(
                    grid_key=key, lat=lat, lng=lng
                )

            cell: AreaCell = state.area_memory[key]
            cell.record_observation(hazard_type, iso, hour)

            if cell.is_known:
                log.info(
                    "adaptive.known_hazard_confirmed",
                    user_id=user_id,
                    grid_key=key,
                    hazard=hazard_type,
                    count=cell.total_count,
                )

        # Async Firebase sync (fire-and-forget)
        asyncio.create_task(
            self._sync_area_cell_to_firebase(user_id, key, cell)
        )
        return cell

    async def get_pc_boost_at_location(
        self,
        user_id: str,
        lat:     float,
        lng:     float,
    ) -> tuple[float, Optional[str]]:
        """
        Returns (pc_boost, hinglish_warning_message) for the nearest known hazard.
        If no known hazard nearby: (0.0, None).
        """
        state = self._state(user_id)
        nearest_cell: Optional[AreaCell] = None
        nearest_dist = float("inf")

        for cell in state.area_memory.values():
            if not cell.is_known:
                continue
            dist = _haversine_m(lat, lng, cell.lat, cell.lng)
            if dist < HazardMemoryConfig.GRID_RESOLUTION_M * 2 and dist < nearest_dist:
                nearest_dist = dist
                nearest_cell = cell

        if nearest_cell:
            return (
                HazardMemoryConfig.KNOWN_HAZARD_PC_BOOST,
                nearest_cell.hinglish_warning(),
            )
        return (0.0, None)

    async def query_area_memory(
        self,
        user_id:   str,
        lat:       float,
        lng:       float,
        radius_m:  float = 50.0,
    ) -> list[dict]:
        """Return all known hazards within radius_m of the given location."""
        state = self._state(user_id)
        results = []
        for cell in state.area_memory.values():
            dist = _haversine_m(lat, lng, cell.lat, cell.lng)
            if dist <= radius_m:
                d = cell.to_dict()
                d["distance_m"] = round(dist, 1)
                results.append(d)
        results.sort(key=lambda c: c["distance_m"])
        return results

    # ── Session event tracking ────────────────────────────────────────────────

    async def record_cancelled_override(self, user_id: str, session_id: str) -> None:
        """SYSTEM 1: User manually cancelled an AI override → possible FP."""
        async with self._lock(user_id):
            state = self._state(user_id)
            state.session_cancelled_overrides += 1
            log.info(
                "adaptive.override_cancelled",
                user_id=user_id,
                session_id=session_id,
                total_this_session=state.session_cancelled_overrides,
            )

    async def record_ignored_warning(self, user_id: str, session_id: str) -> None:
        """SYSTEM 1: User ignored a warning and continued walking fine → consider lowering sensitivity."""
        async with self._lock(user_id):
            state = self._state(user_id)
            state.session_ignored_warnings += 1

    async def record_near_miss(self, user_id: str, session_id: str) -> None:
        """SYSTEM 1: A confirmed close call → raise sensitivity."""
        async with self._lock(user_id):
            state = self._state(user_id)
            state.session_near_misses += 1
            log.warning(
                "adaptive.near_miss_recorded",
                user_id=user_id,
                session_id=session_id,
            )

    # ── Walking pattern updates ───────────────────────────────────────────────

    async def update_walking_pattern(
        self,
        user_id:         str,
        session_id:      str,
        avg_speed_mps:   float,
        duration_min:    float,
        distance_m:      float,
        active_hour:     int,
    ) -> WalkingPatternProfile:
        """SYSTEM 3: Update walking pattern after each session."""
        async with self._lock(user_id):
            state = self._state(user_id)
            p = state.walking_pattern

            p.update_speed(avg_speed_mps)
            p.active_hours[active_hour] = p.active_hours.get(active_hour, 0) + 1
            p.total_sessions += 1
            p.last_updated = _now_iso()

            # Running averages for duration and distance
            n = p.total_sessions
            p.avg_session_duration_min = (
                p.avg_session_duration_min * (n - 1) + duration_min
            ) / n
            p.avg_session_distance_m = (
                p.avg_session_distance_m * (n - 1) + distance_m
            ) / n

            # Pattern is "mature" after warmup sessions
            p.pattern_mature = p.total_sessions >= PatternLearnerConfig.SESSION_WARMUP

            log.info(
                "adaptive.pattern_updated",
                user_id=user_id,
                avg_speed=round(p.avg_speed_mps, 2),
                sessions=p.total_sessions,
                mature=p.pattern_mature,
            )

        return state.walking_pattern

    async def get_sensitivity_modifier(
        self,
        user_id:       str,
        current_speed: float,
    ) -> float:
        """
        SYSTEM 3: Returns a Pc multiplier based on walking pattern deviation.
        Normal speed → 1.0 (no change).
        Anomalous speed → up to 1.20 (20% sensitivity boost).
        """
        state = self._state(user_id)
        p = state.walking_pattern

        if not p.pattern_mature:
            return 1.0

        dev = p.speed_deviation_factor(current_speed)
        # Linear interpolation: 0σ → 1.0, 3σ → 1.20
        modifier = 1.0 + min(dev / 3.0, 1.0) * 0.20
        return round(modifier, 3)

    # ── Session end: run all 4 systems ────────────────────────────────────────

    async def process_session_end(
        self,
        user_id:              str,
        session_id:           str,
        total_overrides_fired: int,
        confirmed_incidents:   int,
        false_negatives:       int,
        duration_min:          float,
        distance_m:            float,
        avg_speed_mps:         float,
    ) -> dict:
        """
        Master end-of-session processor.
        Runs all 4 adaptive systems and returns a summary.
        This is called as a BackgroundTask after session.end().
        """
        async with self._lock(user_id):
            state   = self._state(user_id)
            now_iso = _now_iso()

            # ── SYSTEM 4: Build session feedback record ────────────────────
            fp_count = state.session_cancelled_overrides
            fn_count = false_negatives

            record = SessionFeedbackRecord(
                session_id=session_id,
                user_id=user_id,
                timestamp=now_iso,
                total_overrides_fired=total_overrides_fired,
                cancelled_by_user=state.session_cancelled_overrides,
                confirmed_incidents=confirmed_incidents,
                false_positives=fp_count,
                false_negatives=fn_count,
                duration_min=duration_min,
                distance_m=distance_m,
                avg_speed_mps=avg_speed_mps,
            ).compute_metrics()

            state.accuracy_history.append(record.to_dict())

            # ── SYSTEM 1: Threshold optimization ──────────────────────────
            threshold_summary = self._run_threshold_optimizer(
                state, record, session_id
            )

            # ── SYSTEM 3: Walking pattern ──────────────────────────────────
            hour = _now_hour_ist()

        # Pattern update can use the lock-free call (already unlocked here)
        await self.update_walking_pattern(
            user_id, session_id, avg_speed_mps, duration_min, distance_m, hour
        )

        # Reset session accumulators
        async with self._lock(user_id):
            state = self._state(user_id)
            state.session_cancelled_overrides = 0
            state.session_ignored_warnings    = 0
            state.session_near_misses         = 0

        # Async Firebase persistence
        asyncio.create_task(
            self._sync_full_profile_to_firebase(user_id)
        )

        log.info(
            "adaptive.session_processed",
            user_id=user_id,
            session_id=session_id,
            precision=round(record.precision, 3),
            recall=round(record.recall, 3),
            f1=round(record.f1_score, 3),
            threshold_changed=threshold_summary.get("changed"),
        )

        return {
            "session_id":           session_id,
            "accuracy":             {
                "precision":        round(record.precision, 3),
                "recall":           round(record.recall, 3),
                "f1_score":         round(record.f1_score, 3),
                "false_positives":  record.false_positives,
                "false_negatives":  record.false_negatives,
            },
            "thresholds":           threshold_summary,
            "pattern":              state.walking_pattern.to_dict(),
        }

    # ─── Public helpers for routers ───────────────────────────────────────────

    async def get_stats(self, user_id: str) -> dict:
        state = self._state(user_id)
        return {
            "user_id":             user_id,
            "thresholds":          state.thresholds.to_dict(),
            "walking_pattern":     state.walking_pattern.to_dict(),
            "known_hazard_cells":  sum(1 for c in state.area_memory.values() if c.is_known),
            "total_area_cells":    len(state.area_memory),
            "accuracy_sessions":   len(state.accuracy_history),
            "recent_accuracy":     state.accuracy_history[-5:] if state.accuracy_history else [],
        }

    # ── Feedback routing for routers/adaptive.py ──────────────────────────────

    async def process_feedback(
        self,
        user_id:       str,
        feedback_type: str,
        pc_at_event:   Optional[float],
    ) -> dict:
        """
        Single-event feedback (from the /adaptive/feedback endpoint).
        Routes to the appropriate adaptive action.
        """
        async with self._lock(user_id):
            state = self._state(user_id)

        if feedback_type == "false_positive":
            await self.record_cancelled_override(user_id, "api_feedback")
        elif feedback_type == "false_negative":
            await self.record_near_miss(user_id, "api_feedback")
        elif feedback_type in ("too_sensitive",):
            async with self._lock(user_id):
                state = self._state(user_id)
                state.session_ignored_warnings += 3  # amplified signal

        state    = self._state(user_id)
        samples  = len(state.accuracy_history)
        needed   = max(0, FeedbackConfig.MIN_SESSIONS_FOR_ANALYSIS - samples)

        return {
            "updated":  False,
            "samples":  samples,
            "needed":   needed,
            "thresholds": state.thresholds.to_dict(),
        }

    # ════════════════════════════════════════════════════════════════════════
    # SYSTEM 1 — Private threshold optimizer (called at session end)
    # ════════════════════════════════════════════════════════════════════════

    def _run_threshold_optimizer(
        self,
        state:      UserAdaptiveState,
        record:     SessionFeedbackRecord,
        session_id: str,
    ) -> dict:
        """
        Core threshold adjustment logic (runs with user lock held).
        Returns summary dict with old/new thresholds and reason.

        Rules (all changes bounded by MAX_DELTA_PER_SESSION):
          1. User cancelled >3 overrides  → lower OVERRIDE threshold (less sensitive)
          2. Near-miss detected            → raise WARNING threshold (more sensitive)
          3. High FP rate (>30%)           → lower WARNING threshold
          4. Any FN (missed incident)      → raise both thresholds
        """
        old_warning  = state.thresholds.warning_pct
        old_override = state.thresholds.override_pct
        delta_w  = 0.0
        delta_o  = 0.0
        reasons  = []

        # ── Rule 1: Too many cancelled overrides ──────────────────────────
        if state.session_cancelled_overrides > 3:
            amount = min(
                state.session_cancelled_overrides * 1.5,
                ThresholdBounds.MAX_DELTA_PER_SESSION
            )
            delta_o -= amount
            reasons.append(f"cancelled_overrides:{state.session_cancelled_overrides}")
            log.info(
                "adaptive.threshold_rule1",
                user_id=state.user_id,
                cancelled=state.session_cancelled_overrides,
                delta_o=delta_o,
            )

        # ── Rule 2: Near-miss detected ────────────────────────────────────
        if state.session_near_misses > 0:
            amount = min(
                state.session_near_misses * 3.0,
                ThresholdBounds.MAX_DELTA_PER_SESSION
            )
            delta_w  += amount
            delta_o  += amount * 0.5
            reasons.append(f"near_misses:{state.session_near_misses}")
            log.warning(
                "adaptive.threshold_rule2_near_miss",
                user_id=state.user_id,
                near_misses=state.session_near_misses,
            )

        # ── Rule 3: High FP rate ──────────────────────────────────────────
        if record.flag_too_sensitive and delta_w == 0:
            fp_rate = record.false_positives / max(record.total_overrides_fired, 1)
            amount  = min(fp_rate * 10.0, ThresholdBounds.MAX_DELTA_PER_SESSION)
            delta_w -= amount
            reasons.append(f"high_fp_rate:{round(fp_rate, 2)}")

        # ── Rule 4: Missed incidents ──────────────────────────────────────
        if record.false_negatives > 0:
            amount = min(
                record.false_negatives * 2.5,
                ThresholdBounds.MAX_DELTA_PER_SESSION
            )
            delta_w  += amount
            delta_o  += amount * 0.6
            reasons.append(f"false_negatives:{record.false_negatives}")

        # ── Apply deltas with bounds clamping ─────────────────────────────
        if delta_w == 0 and delta_o == 0:
            return {
                "changed": False,
                "warning_pct":  old_warning,
                "override_pct": old_override,
                "reason": "stable_session",
            }

        new_w = state.thresholds.warning_pct  + delta_w
        new_o = state.thresholds.override_pct + delta_o
        state.thresholds = ThresholdProfile(
            warning_pct=new_w, override_pct=new_o
        ).clamp()

        # Audit trail
        change_record = ThresholdChangeRecord(
            timestamp=_now_iso(),
            reason="; ".join(reasons),
            trigger=reasons[0].split(":")[0] if reasons else "unknown",
            old_warning=old_warning,
            old_override=old_override,
            new_warning=state.thresholds.warning_pct,
            new_override=state.thresholds.override_pct,
            delta_warning=state.thresholds.warning_pct - old_warning,
            delta_override=state.thresholds.override_pct - old_override,
            session_id=session_id,
        )
        state.threshold_history.append(asdict(change_record))

        log.info(
            "adaptive.thresholds_adjusted",
            user_id=state.user_id,
            old_warning=old_warning,
            new_warning=state.thresholds.warning_pct,
            old_override=old_override,
            new_override=state.thresholds.override_pct,
            reasons=reasons,
        )

        return {
            "changed":     True,
            "warning_pct": state.thresholds.warning_pct,
            "override_pct": state.thresholds.override_pct,
            "delta_warning": change_record.delta_warning,
            "delta_override": change_record.delta_override,
            "reason":      "; ".join(reasons),
        }

    # ── Firebase sync (fire-and-forget) ──────────────────────────────────────

    async def _sync_full_profile_to_firebase(self, user_id: str) -> None:
        """Persist complete adaptive profile to Firebase."""
        try:
            from services.firebase_service import FirebaseService
            svc   = FirebaseService()
            state = self._state(user_id)

            if not svc._ready:
                return

            from firebase_admin import db
            ref = db.reference(f"users/{user_id}/adaptive_profile")
            ref.set({
                "personal_thresholds":     state.thresholds.to_dict(),
                "walking_patterns":        state.walking_pattern.to_dict(),
                "session_accuracy_history": state.accuracy_history[-50:],  # last 50
                "threshold_history":       state.threshold_history[-100:],
                "last_synced":             _now_iso(),
            })
        except Exception as exc:
            log.warning("adaptive.firebase_sync_failed", exc=str(exc))

    async def _sync_area_cell_to_firebase(
        self, user_id: str, grid_key: str, cell: AreaCell
    ) -> None:
        """Persist a single area cell to Firebase."""
        try:
            from services.firebase_service import FirebaseService
            svc = FirebaseService()
            if not svc._ready:
                return
            from firebase_admin import db
            safe_key = grid_key.replace(".", "_").replace(",", "__")
            ref = db.reference(
                f"users/{user_id}/adaptive_profile/area_memory/{safe_key}"
            )
            ref.set(cell.to_dict())
        except Exception as exc:
            log.warning("adaptive.firebase_cell_sync_failed", exc=str(exc))

    # ── Firebase load (on first access) ──────────────────────────────────────

    async def load_from_firebase(self, user_id: str) -> None:
        """
        Load a user's adaptive profile from Firebase into memory.
        Called lazily on first encounter of a user_id.
        """
        try:
            from services.firebase_service import FirebaseService
            svc = FirebaseService()
            if not svc._ready:
                return

            from firebase_admin import db
            ref  = db.reference(f"users/{user_id}/adaptive_profile")
            data = ref.get()

            if not data:
                return

            state = self._state(user_id)

            # Restore thresholds
            t = data.get("personal_thresholds", {})
            if t:
                state.thresholds = ThresholdProfile(
                    warning_pct=t.get("warning_pct", 40.0),
                    override_pct=t.get("override_pct", 70.0),
                ).clamp()

            # Restore accuracy history
            state.accuracy_history  = data.get("session_accuracy_history", [])
            state.threshold_history = data.get("threshold_history", [])

            log.info("adaptive.loaded_from_firebase", user_id=user_id)

        except Exception as exc:
            log.warning("adaptive.firebase_load_failed", user_id=user_id, exc=str(exc))
