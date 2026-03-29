'''
Tests for AdaptiveEngine — per-user threshold tuning.
Tests cover: feedback processing, threshold nudging,
sample gate enforcement, EMA convergence, get/set thresholds.
'''
import asyncio
import unittest
from unittest.mock import MagicMock, patch

# Mock pydantic_settings and structlog
import sys
sys.modules['pydantic_settings'] = MagicMock()
sys.modules['structlog'] = MagicMock()
sys.modules['pydantic'] = MagicMock()

from services.adaptive_engine import AdaptiveEngine, _user_states

def _reset(user_id: str):
    _user_states.pop(user_id, None)

class TestAdaptiveEngine(unittest.TestCase):
    def test_initial_thresholds_are_defaults(self):
        async def test_initial_thresholds_are_defaults_async():
            _reset("u-init")
            engine = AdaptiveEngine()
            t = await engine.get_thresholds("u-init")
            self.assertEqual(t.pc_override_threshold, 0.7)
            self.assertEqual(t.pc_warning_threshold, 0.4)
        asyncio.run(test_initial_thresholds_are_defaults_async())

    def test_feedback_increments_sample_count(self):
        async def test_feedback_increments_sample_count_async():
            _reset("u-count")
            engine = AdaptiveEngine()
            result = await engine.process_feedback("u-count", "false_positive", pc_at_event=0.72)
            self.assertEqual(result["samples"], 1)
        asyncio.run(test_feedback_increments_sample_count_async())

    def test_no_threshold_update_below_min_samples(self):
        async def test_no_threshold_update_below_min_samples_async():
            _reset("u-gate")
            engine = AdaptiveEngine()
            # Send fewer events than MIN_FEEDBACK_SAMPLES
            for _ in range(5):
                r = await engine.process_feedback("u-gate", "false_positive", pc_at_event=0.80)
            self.assertIs(r["updated"], False)
        asyncio.run(test_no_threshold_update_below_min_samples_async())

    def test_false_positive_lowers_override_threshold(self):
        async def test_false_positive_lowers_override_threshold_async():
            '''After enough FP feedback, override threshold should decrease.'''
            _reset("u-fp")
            engine = AdaptiveEngine()
            initial = (await engine.get_thresholds("u-fp")).pc_override_threshold

            for _ in range(15):
                r = await engine.process_feedback("u-fp", "false_positive", pc_at_event=0.75)

            final = (await engine.get_thresholds("u-fp")).pc_override_threshold
            self.assertLess(final, initial)
        asyncio.run(test_false_positive_lowers_override_threshold_async())

    def test_false_negative_raises_override_threshold(self):
        async def test_false_negative_raises_override_threshold_async():
            '''After FN feedback, override threshold should increase.'''
            _reset("u-fn")
            engine = AdaptiveEngine()
            initial = (await engine.get_thresholds("u-fn")).pc_override_threshold

            for _ in range(15):
                r = await engine.process_feedback("u-fn", "false_negative", pc_at_event=0.30)

            final = (await engine.get_thresholds("u-fn")).pc_override_threshold
            self.assertGreater(final, initial)
        asyncio.run(test_false_negative_raises_override_threshold_async())

    def test_warning_always_less_than_override(self):
        async def test_warning_always_less_than_override_async():
            _reset("u-order")
            engine = AdaptiveEngine()
            for _ in range(30):
                await engine.process_feedback("u-order", "too_sensitive", pc_at_event=0.80)
            t = await engine.get_thresholds("u-order")
            self.assertLess(t.pc_warning_threshold, t.pc_override_threshold)
        asyncio.run(test_warning_always_less_than_override_async())

    def test_manual_set_thresholds(self):
        async def test_manual_set_thresholds_async():
            _reset("u-set")
            engine = AdaptiveEngine()
            t = await engine.set_thresholds("u-set", override=0.80, warning=0.45)
            self.assertEqual(t.pc_override_threshold, 0.80)
            self.assertEqual(t.pc_warning_threshold, 0.45)
        asyncio.run(test_manual_set_thresholds_async())

    def test_fp_rate_computed_correctly(self):
        async def test_fp_rate_computed_correctly_async():
            _reset("u-fpr")
            engine = AdaptiveEngine()
            await engine.process_feedback("u-fpr", "false_positive",  pc_at_event=0.8)
            await engine.process_feedback("u-fpr", "correct_override", pc_at_event=0.9)
            r = await engine.process_feedback("u-fpr", "false_positive", pc_at_event=0.7)
            self.assertAlmostEqual(r["thresholds"]["false_positive_rate"], 2 / 3, delta=0.01)
        asyncio.run(test_fp_rate_computed_correctly_async())

if __name__ == '__main__':
    unittest.main()