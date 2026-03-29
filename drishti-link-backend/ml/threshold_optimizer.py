"""
ml/threshold_optimizer.py

Standalone per-session threshold optimiser for Drishti-Link.
Runs as a BackgroundTask after every session end.
Max ±5 percentage-point change per session (inviolable).
Full audit trail — every change logged with reason + confidence score.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Optional

import structlog

log = structlog.get_logger(__name__)

WARNING_MIN  = 25.0;  WARNING_MAX  = 55.0
OVERRIDE_MIN = 60.0;  OVERRIDE_MAX = 90.0
MAX_DELTA    = 5.0    # max pp change per session (inviolable)
MIN_GAP      = 5.0    # warning must stay ≥ MIN_GAP below override


@dataclass
class SessionData:
    session_id:               str
    user_id:                  str
    duration_min:             float
    distance_m:               float
    avg_speed_mps:            float
    total_overrides_fired:    int
    user_cancelled_overrides: int
    ignored_warnings:         int
    confirmed_incidents:      int
    near_misses:              int
    false_negatives:          int
    speed_deviation_pct:      float = 0.0


@dataclass
class ThresholdChangeReport:
    session_id:       str
    user_id:          str
    timestamp:        str
    old_warning:      float
    old_override:     float
    new_warning:      float
    new_override:     float
    delta_warning:    float
    delta_override:   float
    changed:          bool
    rules_triggered:  list  = field(default_factory=list)
    confidence_score: float = 0.0
    recommendation:   str   = ""
    clamped_warning:  bool  = False
    clamped_override: bool  = False

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class _Proposal:
    dw: float = 0.0;  do: float = 0.0
    rules: list = field(default_factory=list)
    confidence: float = 0.0

    def add(self, dw: float, do: float, rule: str, conf: float) -> None:
        self.dw += dw;  self.do += do
        self.rules.append({"rule": rule, "dw": round(dw,2), "do": round(do,2), "conf": conf})
        self.confidence = max(self.confidence, conf)


class ThresholdOptimizer:
    """
    Stateless deterministic optimizer.
    optimize(session, cur_warning, cur_override) → ThresholdChangeReport.
    """

    def optimize(self, s: SessionData, cur_w: float, cur_o: float) -> ThresholdChangeReport:
        t0 = time.perf_counter()
        p  = _Proposal()

        # Run all 6 rules
        self._rule_cancelled_overrides(s, p)
        self._rule_ignored_warnings(s, p)
        self._rule_near_misses(s, p)
        self._rule_false_negatives(s, p)
        self._rule_comfort(s, p)
        self._rule_fp_rate(s, p)

        # Hard clamp to ±MAX_DELTA
        p.dw = _clamp(p.dw);  p.do = _clamp(p.do)
        changed = (p.dw != 0 or p.do != 0)

        new_w = cur_w + p.dw;  new_o = cur_o + p.do

        # Bounds
        cw = new_w < WARNING_MIN  or new_w > WARNING_MAX
        co = new_o < OVERRIDE_MIN or new_o > OVERRIDE_MAX
        new_w = max(WARNING_MIN,  min(WARNING_MAX,  new_w))
        new_o = max(OVERRIDE_MIN, min(OVERRIDE_MAX, new_o))
        if new_w >= new_o - MIN_GAP:
            new_w = new_o - MIN_GAP

        rec = self._recommend(s, p, cur_w, cur_o, new_w, new_o)

        report = ThresholdChangeReport(
            session_id=s.session_id, user_id=s.user_id,
            timestamp=datetime.now(timezone.utc).isoformat(),
            old_warning=cur_w,  old_override=cur_o,
            new_warning=round(new_w,2), new_override=round(new_o,2),
            delta_warning=round(new_w-cur_w,2), delta_override=round(new_o-cur_o,2),
            changed=changed, rules_triggered=p.rules,
            confidence_score=round(p.confidence,3),
            recommendation=rec, clamped_warning=cw, clamped_override=co,
        )
        log.info("optimizer.done", user_id=s.user_id, changed=changed,
                 new_w=new_w, new_o=new_o,
                 ms=round((time.perf_counter()-t0)*1000,1))
        return report

    # ── Rules ─────────────────────────────────────────────────────────────────
    def _rule_cancelled_overrides(self, s: SessionData, p: _Proposal) -> None:
        """User cancelled >3 overrides → system too aggressive → lower override."""
        if s.user_cancelled_overrides > 3:
            excess = s.user_cancelled_overrides - 3
            p.add(0, -min(excess*1.5, MAX_DELTA),
                  f"cancelled_overrides({s.user_cancelled_overrides})",
                  min(excess/5.0, 1.0))

    def _rule_ignored_warnings(self, s: SessionData, p: _Proposal) -> None:
        """User ignored >5 warnings without incident → warnings too noisy."""
        if s.ignored_warnings > 5:
            excess = s.ignored_warnings - 5
            p.add(-min(excess*0.8, MAX_DELTA), 0,
                  f"ignored_warnings({s.ignored_warnings})",
                  min(excess/10.0, 0.70))

    def _rule_near_misses(self, s: SessionData, p: _Proposal) -> None:
        """Near-miss = system should have acted sooner → raise both."""
        if s.near_misses > 0:
            p.add(min(s.near_misses*3.0, MAX_DELTA), min(s.near_misses*1.5, MAX_DELTA),
                  f"near_misses({s.near_misses})",
                  min(0.50+s.near_misses*0.25, 1.0))

    def _rule_false_negatives(self, s: SessionData, p: _Proposal) -> None:
        """Incident with no prior warning — most critical failure → aggressive raise."""
        if s.false_negatives > 0:
            p.add(min(s.false_negatives*2.5, MAX_DELTA), min(s.false_negatives*1.5, MAX_DELTA),
                  f"false_negatives({s.false_negatives})",
                  min(0.60+s.false_negatives*0.20, 1.0))

    def _rule_comfort(self, s: SessionData, p: _Proposal) -> None:
        """Clean long session at normal pace → gentle relax (-0.5pp each)."""
        if (s.near_misses == 0 and s.false_negatives == 0
                and s.confirmed_incidents == 0
                and s.speed_deviation_pct < 5.0
                and s.duration_min > 10.0):
            p.add(-0.5, -0.5, "comfort_walk", 0.30)

    def _rule_fp_rate(self, s: SessionData, p: _Proposal) -> None:
        """FP rate >40% → eroding trust → lower override."""
        if s.total_overrides_fired > 0:
            fp_rate = s.user_cancelled_overrides / s.total_overrides_fired
            if fp_rate > 0.40:
                reduction = min((fp_rate-0.40)*15.0, MAX_DELTA)
                p.add(0, -reduction, f"high_fp_rate({round(fp_rate,2)})", 0.80)

    def _recommend(self, s, p, ow, oo, nw, no) -> str:
        if not p.rules:
            return "Stable session. No threshold changes."
        parts = []
        if no < oo: parts.append(f"Override ↓ {oo:.0f}→{no:.0f}pp (too many cancellations).")
        if no > oo: parts.append(f"Override ↑ {oo:.0f}→{no:.0f}pp (near-miss/FN detected).")
        if nw < ow: parts.append(f"Warning ↓ {ow:.0f}→{nw:.0f}pp (warnings too noisy).")
        if nw > ow: parts.append(f"Warning ↑ {ow:.0f}→{nw:.0f}pp (increased sensitivity).")
        return " ".join(parts)


def _clamp(delta: float) -> float:
    return round(max(-MAX_DELTA, min(MAX_DELTA, delta)), 2)


def build_session_data(raw: dict) -> SessionData:
    return SessionData(
        session_id=raw.get("session_id",""),
        user_id=raw.get("user_id",""),
        duration_min=float(raw.get("duration_min",0)),
        distance_m=float(raw.get("distance_m",0)),
        avg_speed_mps=float(raw.get("avg_speed_mps",0)),
        total_overrides_fired=int(raw.get("total_overrides_fired",0)),
        user_cancelled_overrides=int(raw.get("cancelled_by_user",0)),
        ignored_warnings=int(raw.get("ignored_warnings",0)),
        confirmed_incidents=int(raw.get("confirmed_incidents",0)),
        near_misses=int(raw.get("near_misses",0)),
        false_negatives=int(raw.get("false_negatives",0)),
        speed_deviation_pct=float(raw.get("speed_deviation_pct",0)),
    )
