"""
services/moral_governor.py

The Moral Governor — Ethical Decision Engine for Drishti-Link
═════════════════════════════════════════════════════════════

This is the final authority before Drishti acts on the user.
Every decision it makes is:

  ★ TRANSPARENT   — every rule that fired is named
  ★ AUDITABLE     — every decision is logged to Firebase
  ★ EXPLAINABLE   — plain-language reason for every choice
  ★ CONSERVATIVE  — only overrides when necessary (trust costs)

Design philosophy:
  "An unnecessary override is as harmful as a missed hazard.
   False positives erode trust. False negatives put lives at risk.
   The Moral Governor walks this line, rule by rule."

Decision priority (highest → lowest):
  1. OVERRIDE         — life-critical stop
  2. WARNING          — alert + directional guidance
  3. AREA_MEMORY_ALERT— proactive known-hazard awareness
  4. CLEAR            — nothing significant detected

SOS is orthogonal — runs every frame regardless of navigation state.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

import structlog

log = structlog.get_logger(__name__)


# ═════════════════════════════════════════════════════════════════════════════
# Enumerations
# ═════════════════════════════════════════════════════════════════════════════

class DecisionType(str, Enum):
    OVERRIDE           = "OVERRIDE"
    WARNING            = "WARNING"
    AREA_MEMORY_ALERT  = "AREA_MEMORY_ALERT"
    CLEAR              = "CLEAR"
    SOS                = "SOS"


class HapticPattern(str, Enum):
    STRONG_STOP   = "STRONG_STOP"    # 3 rapid full vibrations
    DIRECTIONAL_L = "DIRECTIONAL_L"  # left-biased pulse
    DIRECTIONAL_R = "DIRECTIONAL_R"  # right-biased pulse
    DIRECTIONAL_C = "DIRECTIONAL_C"  # center-forward warning
    GENTLE_PULSE  = "GENTLE_PULSE"   # single soft pulse
    RELEASE       = "RELEASE"        # gentle all-clear vibration
    NONE          = "NONE"


class UserIntent(str, Enum):
    WALKING       = "walking"
    CROSSING      = "crossing_road"
    TURNING_LEFT  = "turning_left"
    TURNING_RIGHT = "turning_right"
    STOPPED       = "stopped"


class LocationContext(str, Enum):
    ROAD          = "road"
    FOOTPATH      = "footpath"
    MARKET        = "market"
    HOME_ZONE     = "home_zone"
    SILENCE_ZONE  = "silence_zone"
    UNKNOWN       = "unknown"


class TimeOfDay(str, Enum):
    MORNING   = "morning"    # 5am–12pm
    AFTERNOON = "afternoon"  # 12pm–5pm
    EVENING   = "evening"    # 5pm–9pm
    NIGHT     = "night"      # 9pm–5am


# ═════════════════════════════════════════════════════════════════════════════
# Input / output data classes
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class DetectedObject:
    """
    Parsed YOLO detection with the extra fields Moral Governor needs.
    Typically constructed from yolo_service.Detection.
    """
    class_name:      str
    confidence:      float
    distance_m:      Optional[float]
    position:        str             # "left" | "center" | "right"
    movement_vector: str             # "approaching" | "stationary" | "receding"
    threat_category: str             # "vehicle" | "animal" | "terrain" | "person"
    pc_contribution: float = 0.0     # this object's Pc contribution


@dataclass
class GovernorInput:
    """Complete input bundle for one decision frame."""
    session_id:       str
    user_id:          str
    frame_id:         str

    pc_score:         float                      # 0–100 (already × 100 scale)
    detected_objects: list[DetectedObject]

    user_intent:      UserIntent
    user_velocity:    float                      # m/s

    # From adaptive engine
    override_threshold: float                    # pp (already in 0-100 scale)
    warning_threshold:  float
    sos_timeout_s:      float = 45.0

    location_context:   LocationContext = LocationContext.UNKNOWN
    area_memory_hint:   Optional[str]   = None    # known hazard warning string
    area_memory_boost:  float           = 0.0     # Pc boost applied from area memory

    time_of_day:        TimeOfDay       = TimeOfDay.MORNING
    session_history:    list            = field(default_factory=list)  # last 10 decisions

    # SOS inputs
    stationary_for_s:   float = 0.0               # seconds user has been still


@dataclass
class DecisionTrace:
    """
    Complete explainability record for one decision.
    Every field is human-readable.
    """
    # ── Core outcome ──────────────────────────────────────────────────────────
    decision:          DecisionType
    haptic:            HapticPattern
    voice_message:     Optional[str]
    release_voice:     Optional[str]               # spoken when override lifts

    # ── Explainability ────────────────────────────────────────────────────────
    decision_reason:   str                         # plain English for audit log
    confidence:        float                       # 0–1: how sure is the system
    rules_triggered:   list[str]                   # named rules that fired
    dominant_object:   Optional[str]               # class_name of top threat

    # ── Override-specific ─────────────────────────────────────────────────────
    override_held:     bool = False
    safe_clear_count:  int  = 0                    # consecutive clear frames
    safe_duration_s:   float = 0.0

    # ── Guardian summary ─────────────────────────────────────────────────────
    guardian_summary:  str  = ""                   # 1 simple sentence for dashboard

    # ── Metadata ─────────────────────────────────────────────────────────────
    session_id:        str  = ""
    user_id:           str  = ""
    frame_id:          str  = ""
    timestamp:         str  = ""
    processing_ms:     float = 0.0
    pc_score:          float = 0.0
    pc_effective:      float = 0.0    # pc_score + area_memory_boost

    def to_dict(self) -> dict:
        d = asdict(self)
        d["decision"]  = self.decision.value
        d["haptic"]    = self.haptic.value
        return d


# ═════════════════════════════════════════════════════════════════════════════
# Voice Message Generator
# ═════════════════════════════════════════════════════════════════════════════

class VoiceGenerator:
    """
    Generates contextual Hinglish TTS messages.
    Every message is short, calm, and action-oriented.
    Drishti's voice must never panic the user.
    """

    # ── Override messages ─────────────────────────────────────────────────────
    OVERRIDE_TEMPLATES: dict[str, str] = {
        "vehicle_default":   "Ruko. {vehicle_type} {distance}m par hai.",
        "vehicle_crossing":  "Crossing mat karo. {vehicle_type} aa rahi hai — {distance}m par.",
        "vehicle_fast":      "Bahut tez aa raha hai. Abhi ruko.",
        "pothole":           "Pothole {distance}m aage. {direction} se jaiye.",
        "open_drain":        "Khula nala bilkul paas hai. Seedha mat chalo.",
        "known_hazard":      "Yahan pehle khatra tha. Main rok rahi hoon.",
        "fast_approach":     "Koi cheez bahut paas hai. Abhi ruko.",
        "generic":           "Ruko. Khatre ka sanket hai.",
    }

    WARNING_TEMPLATES: dict[str, str] = {
        "vehicle":           "Thoda dhyan. {vehicle_type} {distance}m par, {direction} mein.",
        "animal":            "{animal} paas mein hai. Dheere chalo.",
        "crowd":             "Aage bheed hai. Sambhal ke.",
        "known_hazard":      "Yahan pehle {hazard} tha. Dhyan dena.",
        "pedestrian":        "Saamne insaan hai. Dhyan se.",
        "terrain":           "{hazard} {distance}m aage. Thoda dhyan.",
        "generic":           "Kuch hai aage. Thoda dhyan.",
    }

    AREA_MEMORY_TEMPLATE = "Yahan pehle {hazard} tha. Dhyan dena."
    ALL_CLEAR_MESSAGE    = "Ab safe hai. Chalo."
    NIGHT_SUFFIX         = " Andhere mein dhyan se. Main hoon saath."

    RELEASE_MESSAGE      = "Ab safe hai. Chalo."

    SOS_MESSAGE = (
        "Arjun, ghabraiye mat. Main Priya ko call kar rahi hoon. "
        "Aap safe hain. Madad aa rahi hai."
    )

    def override_message(
        self,
        inp:    GovernorInput,
        rules:  list[str],
        dom:    Optional[DetectedObject],
    ) -> str:
        dist = _fmt_dist(dom.distance_m) if dom else "?"
        direction = _loc_hinglish(dom.position if dom else "center")
        is_night = inp.time_of_day == TimeOfDay.NIGHT

        msg = self._select_override_template(inp, rules, dom, dist, direction)
        if is_night and "night" not in msg:
            msg += self.NIGHT_SUFFIX
        return msg

    def _select_override_template(self, inp, rules, dom, dist, direction) -> str:
        if "RULE_CROSSING_VEHICLE" in rules and dom and dom.threat_category == "vehicle":
            return self.OVERRIDE_TEMPLATES["vehicle_crossing"].format(
                vehicle_type=_vehicle_name(dom.class_name), distance=dist
            )
        if "RULE_MOVING_FAST" in rules:
            return self.OVERRIDE_TEMPLATES["vehicle_fast"]
        if dom and dom.class_name == "open_drain":
            return self.OVERRIDE_TEMPLATES["open_drain"]
        if dom and dom.class_name == "pothole":
            return self.OVERRIDE_TEMPLATES["pothole"].format(
                distance=dist, direction=direction
            )
        if "RULE_KNOWN_HAZARD_ZONE" in rules:
            return self.OVERRIDE_TEMPLATES["known_hazard"]
        if dom and dom.threat_category == "vehicle":
            return self.OVERRIDE_TEMPLATES["vehicle_default"].format(
                vehicle_type=_vehicle_name(dom.class_name), distance=dist
            )
        if "RULE_HIGH_PC" in rules:
            return self.OVERRIDE_TEMPLATES["fast_approach"]
        return self.OVERRIDE_TEMPLATES["generic"]

    def warning_message(
        self,
        inp:   GovernorInput,
        rules: list[str],
        dom:   Optional[DetectedObject],
    ) -> str:
        dist = _fmt_dist(dom.distance_m) if dom else "?"
        direction = _loc_hinglish(dom.position if dom else "center")

        if dom and dom.threat_category == "vehicle":
            return self.WARNING_TEMPLATES["vehicle"].format(
                vehicle_type=_vehicle_name(dom.class_name),
                distance=dist,
                direction=direction,
            )
        if dom and dom.threat_category == "animal":
            return self.WARNING_TEMPLATES["animal"].format(
                animal=dom.class_name.capitalize()
            )
        if "RULE_CROWD" in rules:
            return self.WARNING_TEMPLATES["crowd"]
        if "RULE_KNOWN_HAZARD_WARNING" in rules and inp.area_memory_hint:
            hazard = _extract_hazard_from_hint(inp.area_memory_hint)
            return self.WARNING_TEMPLATES["known_hazard"].format(hazard=hazard)
        if dom and dom.threat_category == "terrain":
            return self.WARNING_TEMPLATES["terrain"].format(
                hazard=dom.class_name, distance=dist
            )
        if dom and dom.threat_category == "person":
            return self.WARNING_TEMPLATES["pedestrian"]
        return self.WARNING_TEMPLATES["generic"]

    def area_memory_message(self, hazard_hint: str) -> str:
        hazard = _extract_hazard_from_hint(hazard_hint)
        return self.AREA_MEMORY_TEMPLATE.format(hazard=hazard)

    def sos_message(self) -> str:
        return self.SOS_MESSAGE


# ═════════════════════════════════════════════════════════════════════════════
# Haptic selector
# ═════════════════════════════════════════════════════════════════════════════

def _haptic_for_warning(dom: Optional[DetectedObject]) -> HapticPattern:
    if dom is None:
        return HapticPattern.DIRECTIONAL_C
    if dom.position == "left":
        return HapticPattern.DIRECTIONAL_L
    if dom.position == "right":
        return HapticPattern.DIRECTIONAL_R
    return HapticPattern.DIRECTIONAL_C


# ═════════════════════════════════════════════════════════════════════════════
# Rule engine
# ═════════════════════════════════════════════════════════════════════════════

class RuleEngine:
    """
    A library of named, single-responsibility rule functions.
    Each rule returns (triggered: bool, confidence: float).
    Rules are purely functional — no side effects, fully testable.
    """

    # ── OVERRIDE rules ────────────────────────────────────────────────────────

    @staticmethod
    def rule_high_pc(pc_effective: float, threshold: float) -> tuple[bool, float]:
        """R1: Pc exceeds user's personal override threshold."""
        triggered = pc_effective > threshold
        conf = min((pc_effective - threshold) / 30.0, 1.0) if triggered else 0.0
        return triggered, round(conf, 3)

    @staticmethod
    def rule_crossing_vehicle(
        intent: UserIntent, objects: list[DetectedObject]
    ) -> tuple[bool, float]:
        """R2: User is crossing + vehicle within 15m directly ahead."""
        if intent != UserIntent.CROSSING:
            return False, 0.0
        for obj in objects:
            if (obj.threat_category == "vehicle"
                    and obj.distance_m is not None
                    and obj.distance_m <= 15.0):
                conf = 1.0 - (obj.distance_m / 15.0)
                return True, round(conf, 3)
        return False, 0.0

    @staticmethod
    def rule_open_drain_ahead(objects: list[DetectedObject]) -> tuple[bool, float]:
        """R3: Open drain within 1.5m directly ahead (center position)."""
        for obj in objects:
            if (obj.class_name == "open_drain"
                    and obj.position == "center"
                    and obj.distance_m is not None
                    and obj.distance_m <= 1.5):
                return True, 1.0
        return False, 0.0

    @staticmethod
    def rule_known_hazard_zone(
        pc_effective: float, area_boost: float, pc_trigger: float = 50.0
    ) -> tuple[bool, float]:
        """R4: User is in a known hazard zone AND Pc > 50."""
        if area_boost > 0 and pc_effective > pc_trigger:
            conf = min(pc_effective / 100.0, 1.0)
            return True, round(conf, 3)
        return False, 0.0

    @staticmethod
    def rule_moving_fast_near_hazard(
        velocity: float, objects: list[DetectedObject], speed_threshold: float = 1.5
    ) -> tuple[bool, float]:
        """R5: User moving fast (>1.5 m/s) with hazard within 3m."""
        if velocity <= speed_threshold:
            return False, 0.0
        for obj in objects:
            if obj.distance_m is not None and obj.distance_m <= 3.0:
                speed_factor = min((velocity - speed_threshold) / 1.0, 1.0)
                proximity_factor = 1.0 - (obj.distance_m / 3.0)
                conf = (speed_factor + proximity_factor) / 2
                return True, round(conf, 3)
        return False, 0.0

    # ── WARNING rules ─────────────────────────────────────────────────────────

    @staticmethod
    def rule_pc_in_warning_zone(
        pc_effective: float, warn_thresh: float, override_thresh: float
    ) -> tuple[bool, float]:
        """W1: Pc between warning and override thresholds."""
        if warn_thresh <= pc_effective < override_thresh:
            span = override_thresh - warn_thresh
            conf = (pc_effective - warn_thresh) / max(span, 1.0)
            return True, round(conf, 3)
        return False, 0.0

    @staticmethod
    def rule_animal_nearby(objects: list[DetectedObject]) -> tuple[bool, float]:
        """W2: Animal within 4m."""
        for obj in objects:
            if (obj.threat_category == "animal"
                    and obj.distance_m is not None
                    and obj.distance_m <= 4.0):
                conf = 1.0 - (obj.distance_m / 4.0)
                return True, round(conf, 3)
        return False, 0.0

    @staticmethod
    def rule_known_hazard_approaching(
        area_boost: float, objects: list[DetectedObject], radius_m: float = 5.0
    ) -> tuple[bool, float]:
        """W3: Area memory has known hazard and user is within 5m of it."""
        if area_boost <= 0:
            return False, 0.0
        # Proxy: check if any object is within 5m (hazard memory triggered this zone)
        min_dist = min(
            (obj.distance_m for obj in objects if obj.distance_m),
            default=None
        )
        if min_dist is not None and min_dist <= radius_m:
            conf = 1.0 - (min_dist / radius_m)
            return True, round(conf, 3)
        return True, 0.50   # area boost is active even without close object

    @staticmethod
    def rule_crowd_density(objects: list[DetectedObject]) -> tuple[bool, float]:
        """W4: High crowd density — many people within frame center."""
        center_people = [
            o for o in objects
            if o.threat_category == "person"
            and o.position == "center"
        ]
        if len(center_people) >= 3:
            conf = min(len(center_people) / 8.0, 1.0)
            return True, round(conf, 3)
        return False, 0.0

    # ── SOS check ─────────────────────────────────────────────────────────────

    @staticmethod
    def rule_sos(
        stationary_for_s: float,
        sos_timeout_s:    float,
        location:         LocationContext,
    ) -> tuple[bool, float]:
        """SOS: User stationary too long, not at home."""
        if (location != LocationContext.HOME_ZONE
                and stationary_for_s >= sos_timeout_s):
            conf = min((stationary_for_s - sos_timeout_s) / 30.0, 1.0)
            return True, round(conf, 3)
        return False, 0.0


# ═════════════════════════════════════════════════════════════════════════════
# Override state tracker (per session)
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class OverrideState:
    """Tracks whether we are currently holding an override for a session."""
    active:           bool  = False
    clear_frame_count: int  = 0
    held_since:       Optional[float] = None    # time.monotonic()
    CLEAR_THRESHOLD   = 2   # consecutive clear frames needed to release

    def activate(self) -> None:
        self.active = True
        self.clear_frame_count = 0
        self.held_since = time.monotonic()

    def tick_clear(self) -> bool:
        """Call each clear frame. Returns True when override should release."""
        if not self.active:
            return False
        self.clear_frame_count += 1
        return self.clear_frame_count >= self.CLEAR_THRESHOLD

    def tick_danger(self) -> None:
        """Reset clear counter when danger is still detected."""
        self.clear_frame_count = 0

    def release(self) -> float:
        """Release override, return how long it was held (seconds)."""
        held = time.monotonic() - (self.held_since or time.monotonic())
        self.active = False
        self.clear_frame_count = 0
        self.held_since = None
        return round(held, 2)


# ═════════════════════════════════════════════════════════════════════════════
# Confidence aggregator
# ═════════════════════════════════════════════════════════════════════════════

def _aggregate_confidence(rule_confs: list[float]) -> float:
    """
    Aggregate multiple rule confidence scores into one.
    Uses probabilistic OR: 1 - Π(1 - cᵢ).
    Multiple rules firing = higher overall confidence.
    """
    if not rule_confs:
        return 0.0
    combined = 1.0 - 1.0
    product = 1.0
    for c in rule_confs:
        product *= (1.0 - c)
    combined = 1.0 - product
    return round(min(combined, 1.0), 4)


# ═════════════════════════════════════════════════════════════════════════════
# Guardian summary generator
# ═════════════════════════════════════════════════════════════════════════════

def _guardian_summary(
    decision:  DecisionType,
    rules:     list[str],
    dom:       Optional[DetectedObject],
    pc:        float,
    held_s:    float = 0.0,
) -> str:
    """One plain sentence for the guardian dashboard (non-technical)."""
    dist = f"{dom.distance_m:.0f}m" if dom and dom.distance_m else "paas"
    obj  = dom.class_name if dom else "something"

    if decision == DecisionType.OVERRIDE:
        if "RULE_CROSSING_VEHICLE" in rules:
            return f"Arjun ko road cross karte waqt rokaa — gaadi {dist} pe thi."
        if "RULE_OPEN_DRAIN" in rules:
            return f"Arjun ko khule nale se bachaya — bilkul paas tha."
        if "RULE_MOVING_FAST" in rules:
            return f"Arjun tez chal rahe the, khatre ke paas — roka gaya."
        return f"Arjun ko {obj} se bachane ke liye rokaa ({dist} pe tha)."

    if decision == DecisionType.WARNING:
        return f"Arjun ko {obj} ke baare mein alert kiya ({dist} pe)."

    if decision == DecisionType.AREA_MEMORY_ALERT:
        return f"Arjun ko ek jaani jagah ke khatre ke baare mein bataya."

    if decision == DecisionType.SOS:
        return "Arjun kaafi der se ek jagah ruke hain — SOS bheja ja raha hai."

    return "Sab safe tha. Arjun theek chal rahe the."


# ═════════════════════════════════════════════════════════════════════════════
# MoralGovernor — main class
# ═════════════════════════════════════════════════════════════════════════════

class MoralGovernor:
    """
    The ethical decision authority for Drishti-Link.

    One instance per process (singleton via app.state.governor).
    Per-session override state tracked in self._override_states.

    evaluate() is the single entry point — returns a DecisionTrace
    containing the full decision + explainability chain.
    """

    def __init__(self) -> None:
        self._rules    = RuleEngine()
        self._voice    = VoiceGenerator()
        self._override_states: dict[str, OverrideState] = {}

    # ── Single entry point ────────────────────────────────────────────────────

    def evaluate(self, inp: GovernorInput) -> DecisionTrace:
        """
        Evaluate one frame and return a fully-explained DecisionTrace.

        Steps:
          1. Compute effective Pc (base + area memory boost)
          2. Identify dominant threat object
          3. Check SOS (independent)
          4. Run P1→P4 rules in priority order
          5. Manage override hold/release state
          6. Generate voice, haptic, guardian summary
          7. Return trace (caller logs it to Firebase)
        """
        t0 = time.perf_counter()
        ts = datetime.now(timezone.utc).isoformat()

        # ── Effective Pc ─────────────────────────────────────────────────
        pc_effective = min(inp.pc_score + inp.area_memory_boost * 100, 100.0)

        # ── Sort objects by distance (nearest = dominant) ─────────────────
        sorted_objs = sorted(
            inp.detected_objects,
            key=lambda o: o.distance_m if o.distance_m else 999,
        )
        dominant = sorted_objs[0] if sorted_objs else None

        ovr_state = self._get_override_state(inp.session_id)

        # ── Priority 0: SOS (independent check) ──────────────────────────
        sos_fired, sos_conf = self._rules.rule_sos(
            inp.stationary_for_s,
            inp.sos_timeout_s,
            inp.location_context,
        )
        if sos_fired:
            trace = self._make_sos_trace(inp, sos_conf, ts)
            trace.processing_ms = _elapsed_ms(t0)
            log.critical(
                "governor.SOS",
                user_id=inp.user_id,
                session_id=inp.session_id,
                stationary_s=inp.stationary_for_s,
            )
            asyncio.create_task(self._log_to_firebase(inp.user_id, inp.session_id, trace))
            return trace

        # ── Priority 1: OVERRIDE rules ────────────────────────────────────
        override_rules, override_confs = [], []

        r, c = self._rules.rule_high_pc(pc_effective, inp.override_threshold)
        if r: override_rules.append("RULE_HIGH_PC"); override_confs.append(c)

        r, c = self._rules.rule_crossing_vehicle(inp.user_intent, sorted_objs)
        if r: override_rules.append("RULE_CROSSING_VEHICLE"); override_confs.append(c)

        r, c = self._rules.rule_open_drain_ahead(sorted_objs)
        if r: override_rules.append("RULE_OPEN_DRAIN"); override_confs.append(c)

        r, c = self._rules.rule_known_hazard_zone(pc_effective, inp.area_memory_boost)
        if r: override_rules.append("RULE_KNOWN_HAZARD_ZONE"); override_confs.append(c)

        r, c = self._rules.rule_moving_fast_near_hazard(inp.user_velocity, sorted_objs)
        if r: override_rules.append("RULE_MOVING_FAST"); override_confs.append(c)

        if override_rules:
            # Danger still present — reset clear counter
            ovr_state.tick_danger()
            if not ovr_state.active:
                ovr_state.activate()
                log.warning(
                    "governor.OVERRIDE",
                    user_id=inp.user_id,
                    rules=override_rules,
                    pc=pc_effective,
                )

            conf = _aggregate_confidence(override_confs)
            trace = self._make_override_trace(
                inp, sorted_objs, dominant, override_rules,
                conf, pc_effective, ts
            )
            trace.processing_ms = _elapsed_ms(t0)
            asyncio.create_task(self._log_to_firebase(inp.user_id, inp.session_id, trace))
            return trace

        # ── If override was active and now no danger: tick toward release ──
        if ovr_state.active:
            if ovr_state.tick_clear():
                held_s = ovr_state.release()
                log.info("governor.OVERRIDE_RELEASED", session_id=inp.session_id, held_s=held_s)
                # Still return CLEAR with release haptic
                trace = self._make_clear_trace(inp, pc_effective, ts)
                trace.haptic        = HapticPattern.RELEASE
                trace.voice_message = VoiceGenerator.RELEASE_MESSAGE
                trace.override_held = False
                trace.safe_duration_s = held_s
                trace.decision_reason = f"Override released after {held_s}s. Area now clear."
                trace.guardian_summary = "Safe path confirmed. Arjun chalna shuru kar sakte hain."
                trace.processing_ms = _elapsed_ms(t0)
                asyncio.create_task(self._log_to_firebase(inp.user_id, inp.session_id, trace))
                return trace
            # Not yet released — maintain override silently
            trace = self._make_override_held_trace(inp, pc_effective, ts, ovr_state)
            trace.processing_ms = _elapsed_ms(t0)
            return trace

        # ── Priority 2: WARNING rules ─────────────────────────────────────
        warning_rules, warning_confs = [], []

        r, c = self._rules.rule_pc_in_warning_zone(
            pc_effective, inp.warning_threshold, inp.override_threshold
        )
        if r: warning_rules.append("RULE_PC_WARNING"); warning_confs.append(c)

        r, c = self._rules.rule_animal_nearby(sorted_objs)
        if r: warning_rules.append("RULE_ANIMAL_NEARBY"); warning_confs.append(c)

        r, c = self._rules.rule_known_hazard_approaching(
            inp.area_memory_boost, sorted_objs
        )
        if r: warning_rules.append("RULE_KNOWN_HAZARD_WARNING"); warning_confs.append(c)

        r, c = self._rules.rule_crowd_density(sorted_objs)
        if r: warning_rules.append("RULE_CROWD"); warning_confs.append(c)

        if warning_rules:
            conf = _aggregate_confidence(warning_confs)
            trace = self._make_warning_trace(
                inp, sorted_objs, dominant, warning_rules, conf, pc_effective, ts
            )
            trace.processing_ms = _elapsed_ms(t0)
            log.info("governor.WARNING", user_id=inp.user_id, rules=warning_rules, pc=pc_effective)
            asyncio.create_task(self._log_to_firebase(inp.user_id, inp.session_id, trace))
            return trace

        # ── Priority 3: AREA MEMORY ALERT ────────────────────────────────
        if inp.area_memory_hint and inp.area_memory_boost > 0:
            trace = self._make_area_memory_trace(inp, pc_effective, ts)
            trace.processing_ms = _elapsed_ms(t0)
            log.info("governor.AREA_ALERT", user_id=inp.user_id, hint=inp.area_memory_hint)
            asyncio.create_task(self._log_to_firebase(inp.user_id, inp.session_id, trace))
            return trace

        # ── Priority 4: CLEAR ─────────────────────────────────────────────
        trace = self._make_clear_trace(inp, pc_effective, ts)
        trace.processing_ms = _elapsed_ms(t0)
        return trace

    # ════════════════════════════════════════════════════════════════════════
    # Trace factory methods
    # ════════════════════════════════════════════════════════════════════════

    def _base_trace(self, inp: GovernorInput, pc: float, ts: str) -> DecisionTrace:
        return DecisionTrace(
            decision=DecisionType.CLEAR,
            haptic=HapticPattern.NONE,
            voice_message=None,
            release_voice=None,
            decision_reason="",
            confidence=0.0,
            rules_triggered=[],
            dominant_object=None,
            session_id=inp.session_id,
            user_id=inp.user_id,
            frame_id=inp.frame_id,
            timestamp=ts,
            pc_score=inp.pc_score,
            pc_effective=round(pc, 2),
        )

    def _make_override_trace(
        self,
        inp:     GovernorInput,
        objects: list[DetectedObject],
        dom:     Optional[DetectedObject],
        rules:   list[str],
        conf:    float,
        pc:      float,
        ts:      str,
    ) -> DecisionTrace:
        voice = self._voice.override_message(inp, rules, dom)
        reason = self._override_reason(rules, dom, inp)
        summary = _guardian_summary(DecisionType.OVERRIDE, rules, dom, pc)

        t = self._base_trace(inp, pc, ts)
        t.decision        = DecisionType.OVERRIDE
        t.haptic          = HapticPattern.STRONG_STOP
        t.voice_message   = voice
        t.release_voice   = VoiceGenerator.RELEASE_MESSAGE
        t.decision_reason = reason
        t.confidence      = conf
        t.rules_triggered = rules
        t.dominant_object = dom.class_name if dom else None
        t.override_held   = True
        t.guardian_summary = summary
        return t

    def _make_override_held_trace(
        self,
        inp:     GovernorInput,
        pc:      float,
        ts:      str,
        ovr:     OverrideState,
    ) -> DecisionTrace:
        """Silent hold — override still active, danger cleared by 1 frame."""
        t = self._base_trace(inp, pc, ts)
        t.decision        = DecisionType.OVERRIDE
        t.haptic          = HapticPattern.NONE       # haptic already fired
        t.voice_message   = None                     # voice already spoken
        t.override_held   = True
        t.safe_clear_count = ovr.clear_frame_count
        t.decision_reason = "Override held — waiting for 2 consecutive clear frames."
        t.confidence      = 0.80
        t.rules_triggered = ["HOLD_OVERRIDE"]
        t.guardian_summary = "Arjun abhi bhi ruke hain — area check ho raha hai."
        return t

    def _make_warning_trace(
        self,
        inp:     GovernorInput,
        objects: list[DetectedObject],
        dom:     Optional[DetectedObject],
        rules:   list[str],
        conf:    float,
        pc:      float,
        ts:      str,
    ) -> DecisionTrace:
        voice   = self._voice.warning_message(inp, rules, dom)
        haptic  = _haptic_for_warning(dom)
        reason  = self._warning_reason(rules, dom)
        summary = _guardian_summary(DecisionType.WARNING, rules, dom, pc)

        t = self._base_trace(inp, pc, ts)
        t.decision        = DecisionType.WARNING
        t.haptic          = haptic
        t.voice_message   = voice
        t.decision_reason = reason
        t.confidence      = conf
        t.rules_triggered = rules
        t.dominant_object = dom.class_name if dom else None
        t.guardian_summary = summary
        return t

    def _make_area_memory_trace(
        self, inp: GovernorInput, pc: float, ts: str
    ) -> DecisionTrace:
        hint = inp.area_memory_hint or "khatre"
        voice = self._voice.area_memory_message(hint)

        t = self._base_trace(inp, pc, ts)
        t.decision        = DecisionType.AREA_MEMORY_ALERT
        t.haptic          = HapticPattern.GENTLE_PULSE
        t.voice_message   = voice
        t.decision_reason = f"User entering known hazard zone: {hint}"
        t.confidence      = min(inp.area_memory_boost + 0.40, 1.0)
        t.rules_triggered = ["RULE_AREA_MEMORY"]
        t.guardian_summary = _guardian_summary(
            DecisionType.AREA_MEMORY_ALERT, [], None, pc
        )
        return t

    def _make_clear_trace(self, inp: GovernorInput, pc: float, ts: str) -> DecisionTrace:
        t = self._base_trace(inp, pc, ts)
        t.decision_reason = f"No hazard detected. Pc={pc:.1f} below warning threshold."
        t.confidence      = 1.0 - (pc / max(inp.warning_threshold, 1.0))
        t.guardian_summary = "Sab safe tha."
        return t

    def _make_sos_trace(
        self, inp: GovernorInput, conf: float, ts: str
    ) -> DecisionTrace:
        t = self._base_trace(inp, inp.pc_score, ts)
        t.decision        = DecisionType.SOS
        t.haptic          = HapticPattern.STRONG_STOP
        t.voice_message   = self._voice.sos_message()
        t.decision_reason = (
            f"User has been stationary for {inp.stationary_for_s:.0f}s "
            f"(timeout: {inp.sos_timeout_s:.0f}s) outside home zone."
        )
        t.confidence      = conf
        t.rules_triggered = ["RULE_SOS"]
        t.guardian_summary = _guardian_summary(DecisionType.SOS, ["RULE_SOS"], None, 0)
        return t

    # ── Reason string builders ────────────────────────────────────────────────

    @staticmethod
    def _override_reason(
        rules: list[str], dom: Optional[DetectedObject], inp: GovernorInput
    ) -> str:
        parts = []
        if "RULE_HIGH_PC" in rules:
            parts.append(
                f"Collision probability ({inp.pc_score:.0f}%) exceeded "
                f"personal override threshold ({inp.override_threshold:.0f}%)."
            )
        if "RULE_CROSSING_VEHICLE" in rules and dom:
            parts.append(
                f"User was crossing road with {dom.class_name} "
                f"at {_fmt_dist(dom.distance_m)}m."
            )
        if "RULE_OPEN_DRAIN" in rules:
            parts.append("Open drain detected directly ahead within 1.5m.")
        if "RULE_KNOWN_HAZARD_ZONE" in rules:
            parts.append("User entered known-hazard zone with elevated Pc.")
        if "RULE_MOVING_FAST" in rules:
            parts.append(
                f"User velocity {inp.user_velocity:.1f} m/s while hazard was within 3m."
            )
        return " | ".join(parts) or "Override threshold exceeded."

    @staticmethod
    def _warning_reason(rules: list[str], dom: Optional[DetectedObject]) -> str:
        parts = []
        if "RULE_PC_WARNING" in rules:
            parts.append("Pc in warning zone.")
        if "RULE_ANIMAL_NEARBY" in rules and dom:
            parts.append(f"{dom.class_name.capitalize()} within 4m.")
        if "RULE_KNOWN_HAZARD_WARNING" in rules:
            parts.append("Known hazard zone within 5m.")
        if "RULE_CROWD" in rules:
            parts.append("High crowd density directly ahead.")
        return " | ".join(parts) or "Warning threshold exceeded."

    # ── Override state management ─────────────────────────────────────────────

    def _get_override_state(self, session_id: str) -> OverrideState:
        if session_id not in self._override_states:
            self._override_states[session_id] = OverrideState()
        return self._override_states[session_id]

    def cleanup_session(self, session_id: str) -> None:
        self._override_states.pop(session_id, None)

    # ── Firebase audit log ────────────────────────────────────────────────────

    async def _log_to_firebase(
        self, user_id: str, session_id: str, trace: DecisionTrace
    ) -> None:
        """
        Append one decision trace to Firebase for guardian dashboard.
        Only OVERRIDE, WARNING, SOS, and AREA_ALERT are logged (skip CLEAR for volume).
        """
        if trace.decision == DecisionType.CLEAR and not trace.override_held:
            return   # don't flood Firebase with clear frames

        try:
            from services.firebase_service import FirebaseService
            svc = FirebaseService()
            if not svc._ready:
                return

            from firebase_admin import db
            ref = db.reference(
                f"users/{user_id}/sessions/{session_id}/decisions"
            )
            ref.push(trace.to_dict())

        except Exception as exc:
            log.warning("governor.firebase_log_failed", exc=str(exc))


# ═════════════════════════════════════════════════════════════════════════════
# Helper functions
# ═════════════════════════════════════════════════════════════════════════════

def _fmt_dist(d: Optional[float]) -> str:
    if d is None:
        return "?"
    return str(int(round(d)))


def _loc_hinglish(pos: str) -> str:
    return {"left": "Baaye", "right": "Daaye", "center": "Seedha"}.get(pos, "Seedha")


def _vehicle_name(class_name: str) -> str:
    names = {
        "car":           "gaadi",
        "motorcycle":    "motorcycle",
        "auto_rickshaw": "auto",
        "bus":           "bus",
        "truck":         "truck",
        "bicycle":       "cycle",
    }
    return names.get(class_name, class_name)


def _extract_hazard_from_hint(hint: str) -> str:
    """Extract hazard type keyword from a hint like 'Yahan pehle pothole tha'."""
    for kw in ["pothole", "nala", "gaadi", "jaanwar", "bheed", "khatra", "wire", "drain"]:
        if kw in hint.lower():
            return kw
    return "khatre"


def _elapsed_ms(t0: float) -> float:
    return round((time.perf_counter() - t0) * 1000, 2)


# ═════════════════════════════════════════════════════════════════════════════
# Compatibility shim — old FrameAnalysisResult-style evaluate signature
# ═════════════════════════════════════════════════════════════════════════════

def build_governor_input_from_analysis(
    session_id:       str,
    user_id:          str,
    frame_id:         str,
    pc_score:         float,          # 0-1 scale from scorer
    hazards:          list,           # list[HazardDetection] from models/hazard.py
    user_velocity:    float,
    override_threshold: float,        # 0-1 scale
    warning_threshold:  float,
    area_boost:       float = 0.0,
    area_hint:        Optional[str] = None,
    stationary_for_s: float = 0.0,
) -> GovernorInput:
    """
    Convenience factory to build GovernorInput from the existing
    HazardDetection list + scorer output.
    Maps from 0-1 Pc scale → 0-100 scale internally.
    """
    from services.yolo_service import MovementVector

    objects = []
    for h in hazards:
        bbox = getattr(h, "bounding_box", None)
        cx   = ((bbox.x1 + bbox.x2) / 2) if bbox else 0.5
        pos  = "left" if cx < 0.33 else ("right" if cx > 0.67 else "center")
        mv   = getattr(h, "movement_vector", "unknown")

        objects.append(DetectedObject(
            class_name=getattr(h, "hazard_type", type(h).__name__).replace("HazardType.", "").lower(),
            confidence=float(getattr(h, "confidence", 0.5)),
            distance_m=getattr(h, "estimated_distance_m", None),
            position=pos,
            movement_vector=mv if isinstance(mv, str) else "unknown",
            threat_category=_infer_category(getattr(h, "hazard_type", "")),
            pc_contribution=float(getattr(h, "collision_prob", 0)),
        ))

    return GovernorInput(
        session_id=session_id,
        user_id=user_id,
        frame_id=frame_id,
        pc_score=round(pc_score * 100, 2),         # convert 0-1 → 0-100
        detected_objects=objects,
        user_intent=UserIntent.WALKING,
        user_velocity=user_velocity,
        override_threshold=round(override_threshold * 100, 2),
        warning_threshold=round(warning_threshold * 100, 2),
        area_memory_boost=area_boost,
        area_memory_hint=area_hint,
        stationary_for_s=stationary_for_s,
    )


def _infer_category(hazard_type_val) -> str:
    s = str(hazard_type_val).lower()
    if any(k in s for k in ["vehicle", "car", "truck", "bus", "cycle", "rickshaw"]):
        return "vehicle"
    if any(k in s for k in ["animal", "dog", "cow", "cat", "goat"]):
        return "animal"
    if any(k in s for k in ["pedestrian", "person", "crowd"]):
        return "person"
    return "terrain"
