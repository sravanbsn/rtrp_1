'''
tests/test_moral_governor.py  — comprehensive unit tests for the Moral Governor.

Tests cover:
  ★ All 5 OVERRIDE rule functions (individually)
  ★ All 4 WARNING rule functions
  ★ SOS rule
  ★ Decision priority ordering (OVERRIDE beats WARNING beats AREA_MEMORY_ALERT)
  ★ Override hold / release state machine (2-frame gate)
  ★ VoiceGenerator message content
  ★ Haptic pattern selection (directional)
  ★ Confidence aggregation
  ★ Explainability fields populated on every trace
  ★ CLEAR when nothing is active
  ★ Night mode voice suffix
'''
import asyncio
import unittest
from unittest.mock import patch, AsyncMock, MagicMock
import sys

# Mock structlog
sys.modules['structlog'] = MagicMock()

from services.moral_governor import (
    MoralGovernor,
    GovernorInput,
    DetectedObject,
    DecisionType,
    HapticPattern,
    UserIntent,
    LocationContext,
    TimeOfDay,
    OverrideState,
    RuleEngine,
    VoiceGenerator,
    _aggregate_confidence,
    _haptic_for_warning,
    _loc_hinglish,
    _vehicle_name,
)


# ═════════════════════════════════════════════════════════════════════════════
# Fixtures
# ═════════════════════════════════════════════════════════════════════════════

def _obj(
    cls="car", dist=5.0, pos="center",
    mv="approaching", cat="vehicle", conf=0.88
) -> DetectedObject:
    return DetectedObject(
        class_name=cls, confidence=conf,
        distance_m=dist, position=pos,
        movement_vector=mv, threat_category=cat,
    )


def _inp(
    pc=30.0,
    objects=None,
    intent=UserIntent.WALKING,
    velocity=0.8,
    override_thresh=70.0,
    warning_thresh=40.0,
    location=LocationContext.FOOTPATH,
    area_boost=0.0,
    area_hint=None,
    stationary_s=0.0,
    tod=TimeOfDay.MORNING,
) -> GovernorInput:
    return GovernorInput(
        session_id="sess-test",
        user_id="user-test",
        frame_id="f-1",
        pc_score=pc,
        detected_objects=objects or [],
        user_intent=intent,
        user_velocity=velocity,
        override_threshold=override_thresh,
        warning_threshold=warning_thresh,
        location_context=location,
        area_memory_boost=area_boost,
        area_memory_hint=area_hint,
        stationary_for_s=stationary_s,
        time_of_day=tod,
    )


# ═════════════════════════════════════════════════════════════════════════════
# RuleEngine — unit tests (pure functions, no side effects)
# ═════════════════════════════════════════════════════════════════════════════

class TestRuleHighPc(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_above_threshold(self):
        ok, _ = self.r.rule_high_pc(75.0, 70.0)
        self.assertTrue(ok)

    def test_does_not_fire_at_threshold(self):
        ok, _ = self.r.rule_high_pc(70.0, 70.0)
        self.assertFalse(ok)

    def test_does_not_fire_below(self):
        ok, _ = self.r.rule_high_pc(60.0, 70.0)
        self.assertFalse(ok)

    def test_confidence_increases_with_pc(self):
        _, c1 = self.r.rule_high_pc(72.0, 70.0)
        _, c2 = self.r.rule_high_pc(90.0, 70.0)
        self.assertGreater(c2, c1)


class TestRuleCrossingVehicle(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_crossing_with_vehicle_within_15m(self):
        objs = [_obj("car", dist=10.0)]
        ok, conf = self.r.rule_crossing_vehicle(UserIntent.CROSSING, objs)
        self.assertTrue(ok)
        self.assertTrue(0.0 < conf <= 1.0)

    def test_fires_at_exactly_15m(self):
        objs = [_obj("car", dist=15.0)]
        ok, _ = self.r.rule_crossing_vehicle(UserIntent.CROSSING, objs)
        self.assertTrue(ok)

    def test_not_firing_when_not_crossing(self):
        objs = [_obj("car", dist=5.0)]
        ok, _ = self.r.rule_crossing_vehicle(UserIntent.WALKING, objs)
        self.assertFalse(ok)

    def test_not_firing_when_vehicle_too_far(self):
        objs = [_obj("car", dist=20.0)]
        ok, _ = self.r.rule_crossing_vehicle(UserIntent.CROSSING, objs)
        self.assertFalse(ok)

    def test_not_firing_for_non_vehicle(self):
        objs = [_obj("dog", dist=5.0, cat="animal")]
        ok, _ = self.r.rule_crossing_vehicle(UserIntent.CROSSING, objs)
        self.assertFalse(ok)


class TestRuleOpenDrain(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_drain_center_within_1_5m(self):
        objs = [_obj("open_drain", dist=1.0, pos="center", cat="terrain")]
        ok, _ = self.r.rule_open_drain_ahead(objs)
        self.assertTrue(ok)

    def test_not_firing_drain_on_left(self):
        objs = [_obj("open_drain", dist=1.0, pos="left", cat="terrain")]
        ok, _ = self.r.rule_open_drain_ahead(objs)
        self.assertFalse(ok)

    def test_not_firing_drain_too_far(self):
        objs = [_obj("open_drain", dist=2.0, pos="center", cat="terrain")]
        ok, _ = self.r.rule_open_drain_ahead(objs)
        self.assertFalse(ok)


class TestRuleKnownHazardZone(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_with_boost_and_high_pc(self):
        ok, _ = self.r.rule_known_hazard_zone(pc_effective=60.0, area_boost=0.20)
        self.assertTrue(ok)

    def test_not_firing_without_boost(self):
        ok, _ = self.r.rule_known_hazard_zone(pc_effective=60.0, area_boost=0.0)
        self.assertFalse(ok)

    def test_not_firing_with_boost_but_low_pc(self):
        ok, _ = self.r.rule_known_hazard_zone(pc_effective=30.0, area_boost=0.20)
        self.assertFalse(ok)


class TestRuleMovingFast(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_fast_and_close(self):
        objs = [_obj("car", dist=2.0)]
        ok, _ = self.r.rule_moving_fast_near_hazard(velocity=2.0, objects=objs)
        self.assertTrue(ok)

    def test_not_firing_slow_speed(self):
        objs = [_obj("car", dist=2.0)]
        ok, _ = self.r.rule_moving_fast_near_hazard(velocity=1.0, objects=objs)
        self.assertFalse(ok)

    def test_not_firing_hazard_too_far(self):
        objs = [_obj("car", dist=5.0)]
        ok, _ = self.r.rule_moving_fast_near_hazard(velocity=2.0, objects=objs)
        self.assertFalse(ok)


class TestRuleAnimalNearby(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_within_4m(self):
        objs = [_obj("dog", dist=3.0, cat="animal")]
        ok, _ = self.r.rule_animal_nearby(objs)
        self.assertTrue(ok)

    def test_not_firing_beyond_4m(self):
        objs = [_obj("dog", dist=5.0, cat="animal")]
        ok, _ = self.r.rule_animal_nearby(objs)
        self.assertFalse(ok)


class TestRuleCrowd(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_with_3_center_people(self):
        objs = [_obj("person", dist=3.0, pos="center", cat="person") for _ in range(3)]
        ok, _ = self.r.rule_crowd_density(objs)
        self.assertTrue(ok)

    def test_not_firing_with_fewer_people(self):
        objs = [_obj("person", dist=3.0, pos="center", cat="person") for _ in range(2)]
        ok, _ = self.r.rule_crowd_density(objs)
        self.assertFalse(ok)

    def test_not_firing_when_people_off_center(self):
        objs = [_obj("person", dist=3.0, pos="left", cat="person") for _ in range(5)]
        ok, _ = self.r.rule_crowd_density(objs)
        self.assertFalse(ok)


class TestRuleSOS(unittest.TestCase):
    def setUp(self):
        self.r = RuleEngine()

    def test_fires_when_stationary_too_long_outside_home(self):
        ok, _ = self.r.rule_sos(60.0, 45.0, LocationContext.FOOTPATH)
        self.assertTrue(ok)

    def test_not_firing_in_home_zone(self):
        ok, _ = self.r.rule_sos(60.0, 45.0, LocationContext.HOME_ZONE)
        self.assertFalse(ok)

    def test_not_firing_below_timeout(self):
        ok, _ = self.r.rule_sos(30.0, 45.0, LocationContext.FOOTPATH)
        self.assertFalse(ok)

    def test_confidence_increases_with_time(self):
        _, c1 = self.r.rule_sos(50.0, 45.0, LocationContext.ROAD)
        _, c2 = self.r.rule_sos(80.0, 45.0, LocationContext.ROAD)
        self.assertGreater(c2, c1)


# ═════════════════════════════════════════════════════════════════════════════
# OverrideState machine
# ═════════════════════════════════════════════════════════════════════════════

class TestOverrideState(unittest.TestCase):
    def test_activate_sets_active(self):
        ovr = OverrideState()
        ovr.activate()
        self.assertTrue(ovr.active)

    def test_tick_clear_returns_true_after_2_frames(self):
        ovr = OverrideState()
        ovr.activate()
        self.assertFalse(ovr.tick_clear())   # frame 1
        self.assertTrue(ovr.tick_clear())    # frame 2 → release

    def test_tick_danger_resets_clear_counter(self):
        ovr = OverrideState()
        ovr.activate()
        ovr.tick_clear()        # 1 clear frame
        ovr.tick_danger()       # danger again!
        self.assertEqual(ovr.clear_frame_count, 0)
        self.assertFalse(ovr.tick_clear())   # back to 1

    def test_release_returns_elapsed_time(self):
        import time
        ovr = OverrideState()
        ovr.activate()
        time.sleep(0.01)
        held = ovr.release()
        self.assertGreaterEqual(held, 0.0)
        self.assertFalse(ovr.active)


# ═════════════════════════════════════════════════════════════════════════════
# Confidence aggregation
# ═════════════════════════════════════════════════════════════════════════════

class TestAggregateConfidence(unittest.TestCase):
    def test_empty_returns_zero(self):
        self.assertEqual(_aggregate_confidence([]), 0.0)

    def test_single_value_passes_through(self):
        self.assertAlmostEqual(_aggregate_confidence([0.80]), 0.80, delta=0.01)

    def test_two_rules_higher_than_one(self):
        c1 = _aggregate_confidence([0.60])
        c2 = _aggregate_confidence([0.60, 0.60])
        self.assertGreater(c2, c1)

    def test_all_zero_returns_zero(self):
        self.assertAlmostEqual(_aggregate_confidence([0.0, 0.0]), 0.0, delta=0.01)

    def test_result_bounded_to_1(self):
        c = _aggregate_confidence([1.0, 1.0, 1.0])
        self.assertLessEqual(c, 1.0)


# ═════════════════════════════════════════════════════════════════════════════
# Haptic + helpers
# ═════════════════════════════════════════════════════════════════════════════

class TestHapticForWarning(unittest.TestCase):
    def test_left_object_gives_left_haptic(self):
        dom = _obj(pos="left")
        self.assertEqual(_haptic_for_warning(dom), HapticPattern.DIRECTIONAL_L)

    def test_right_object_gives_right_haptic(self):
        dom = _obj(pos="right")
        self.assertEqual(_haptic_for_warning(dom), HapticPattern.DIRECTIONAL_R)

    def test_center_object_gives_center_haptic(self):
        dom = _obj(pos="center")
        self.assertEqual(_haptic_for_warning(dom), HapticPattern.DIRECTIONAL_C)

    def test_none_object_gives_center_haptic(self):
        self.assertEqual(_haptic_for_warning(None), HapticPattern.DIRECTIONAL_C)


class TestLocHinglish(unittest.TestCase):
    def test_left(self):   self.assertEqual(_loc_hinglish("left"),   "Baaye")
    def test_right(self):  self.assertEqual(_loc_hinglish("right"),  "Daaye")
    def test_center(self): self.assertEqual(_loc_hinglish("center"), "Seedha")
    def test_unknown(self): self.assertEqual(_loc_hinglish("?"),     "Seedha")


# ═════════════════════════════════════════════════════════════════════════════
# Full decision evaluation (mocks Firebase)
# ═════════════════════════════════════════════════════════════════════════════

class TestGovernorDecisions(unittest.TestCase):
    def setUp(self):
        self.gov = MoralGovernor()
        # Patch Firebase logging to be a no-op
        self.gov._log_to_firebase = AsyncMock(return_value=None)

    def test_clear_when_no_hazard(self):
        async def test_async():
            trace = self.gov.evaluate(_inp(pc=10.0))
            self.assertEqual(trace.decision, DecisionType.CLEAR)
            self.assertEqual(trace.haptic, HapticPattern.NONE)
            self.assertIsNone(trace.voice_message)
        asyncio.run(test_async())

    def test_override_when_pc_above_threshold(self):
        async def test_async():
            trace = self.gov.evaluate(_inp(pc=80.0, override_thresh=70.0))
            self.assertEqual(trace.decision, DecisionType.OVERRIDE)
            self.assertEqual(trace.haptic, HapticPattern.STRONG_STOP)
            self.assertIsNotNone(trace.voice_message)
            self.assertIn("RULE_HIGH_PC", trace.rules_triggered)
        asyncio.run(test_async())

    def test_warning_when_pc_in_warning_zone(self):
        async def test_async():
            trace = self.gov.evaluate(_inp(pc=55.0, warning_thresh=40.0, override_thresh=70.0))
            self.assertEqual(trace.decision, DecisionType.WARNING)
            self.assertNotEqual(trace.haptic, HapticPattern.NONE)
            self.assertIn("RULE_PC_WARNING", trace.rules_triggered)
        asyncio.run(test_async())

    def test_override_beats_warning_by_priority(self):
        '''Override rules should shortcircuit before warning rules are even checked.'''
        async def test_async():
            inp = _inp(
                pc=85.0,             # above override
                objects=[_obj("dog", dist=3.0, cat="animal")],
            )
            trace = self.gov.evaluate(inp)
            self.assertEqual(trace.decision, DecisionType.OVERRIDE)
        asyncio.run(test_async())

    def test_sos_triggered_on_long_stationary(self):
        async def test_async():
            trace = self.gov.evaluate(_inp(stationary_s=60.0, location=LocationContext.ROAD))
            self.assertEqual(trace.decision, DecisionType.SOS)
            self.assertIn("RULE_SOS", trace.rules_triggered)
        asyncio.run(test_async())

    def test_sos_NOT_triggered_at_home(self):
        async def test_async():
            trace = self.gov.evaluate(_inp(stationary_s=60.0, location=LocationContext.HOME_ZONE))
            self.assertNotEqual(trace.decision, DecisionType.SOS)
        asyncio.run(test_async())

    def test_area_memory_alert_when_no_higher_priority(self):
        async def test_async():
            inp = _inp(pc=20.0, area_boost=0.20, area_hint="Yahan pehle pothole tha. Dhyan dena.")
            trace = self.gov.evaluate(inp)
            self.assertEqual(trace.decision, DecisionType.AREA_MEMORY_ALERT)
            self.assertEqual(trace.haptic, HapticPattern.GENTLE_PULSE)
        asyncio.run(test_async())

    def test_crossing_vehicle_triggers_override(self):
        async def test_async():
            inp = _inp(
                pc=30.0,                     # below normal override threshold
                intent=UserIntent.CROSSING,
                objects=[_obj("car", dist=10.0, cat="vehicle")],
                override_thresh=70.0,
            )
            trace = self.gov.evaluate(inp)
            self.assertEqual(trace.decision, DecisionType.OVERRIDE)
            self.assertIn("RULE_CROSSING_VEHICLE", trace.rules_triggered)
        asyncio.run(test_async())

    def test_explainability_fields_always_present(self):
        async def test_async():
            for pc in [10.0, 50.0, 85.0]:
                trace = self.gov.evaluate(_inp(pc=pc))
                self.assertNotEqual(trace.decision_reason, "")
                self.assertNotEqual(trace.guardian_summary, "")
                self.assertIsInstance(trace.rules_triggered, list)
                self.assertTrue(0.0 <= trace.confidence <= 1.0)
        asyncio.run(test_async())

    def test_override_hold_state_persists(self):
        '''Override should be held across frames until 2 consecutive clear frames.'''
        async def test_async():
            sess = "hold-test"
            inp_danger = GovernorInput(
                session_id=sess, user_id="u", frame_id="f",
                pc_score=85.0, detected_objects=[],
                user_intent=UserIntent.WALKING, user_velocity=0.8,
                override_threshold=70.0, warning_threshold=40.0,
            )
            inp_clear = GovernorInput(
                session_id=sess, user_id="u", frame_id="f",
                pc_score=10.0, detected_objects=[],
                user_intent=UserIntent.WALKING, user_velocity=0.8,
                override_threshold=70.0, warning_threshold=40.0,
            )

            self.gov.evaluate(inp_danger)                   # activates override
            trace = self.gov.evaluate(inp_clear)             # 1st clear → still held
            self.assertEqual(trace.decision, DecisionType.OVERRIDE)
            self.assertTrue(trace.override_held)

            trace = self.gov.evaluate(inp_clear)             # 2nd clear → released
            self.assertEqual(trace.decision, DecisionType.CLEAR)
            self.assertEqual(trace.haptic, HapticPattern.RELEASE)
        asyncio.run(test_async())

    def test_cleanup_session_removes_state(self):
        async def test_async():
            self.gov.evaluate(_inp(pc=85.0))  # creates state
            self.gov.cleanup_session("sess-test")
            self.assertNotIn("sess-test", self.gov._override_states)
        asyncio.run(test_async())

    def test_night_mode_appends_suffix(self):
        async def test_async():
            inp = _inp(pc=85.0, tod=TimeOfDay.NIGHT)
            trace = self.gov.evaluate(inp)
            self.assertIsNotNone(trace.voice_message)
            self.assertTrue("Andhere" in trace.voice_message or "andhere" in trace.voice_message)
        asyncio.run(test_async())


if __name__ == '__main__':
    unittest.main()