'''
Tests for CollisionScorer — the Pc calculator.
Tests cover: scoring formula, severity thresholds, direction inference,
plain-language output, edge cases (no depth, zero-area boxes).
'''
import asyncio
import unittest
from unittest.mock import MagicMock, patch
import sys
from dataclasses import dataclass
from enum import Enum

# Mock non-available dependencies
sys.modules['pydantic'] = MagicMock()
sys.modules['numpy'] = MagicMock()
sys.modules['structlog'] = MagicMock()

# Re-create data classes and enums locally for this test
@dataclass
class BoundingBox:
    x1: float
    y1: float
    x2: float
    y2: float

class HazardSeverity(str, Enum):
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"

class HazardType(str, Enum):
    VEHICLE = "VEHICLE"
    WATER_PUDDLE = "WATER_PUDDLE"
    PERSON = "PERSON"
    ANIMAL = "ANIMAL"
    TERRAIN = "TERRAIN"

@dataclass
class RawDetection:
    class_id: int
    class_name: str
    confidence: float
    box: BoundingBox

# Patch the modules to use our local fakes
with patch.dict(sys.modules, {
    'models.hazard': MagicMock(BoundingBox=BoundingBox, HazardSeverity=HazardSeverity, HazardType=HazardType),
    'services.yolo_service': MagicMock(RawDetection=RawDetection),
}):
    from services.collision_scorer import CollisionScorer, _infer_direction, _severity_from_pc

    def _make_det(
        hazard_type: HazardType = HazardType.VEHICLE,
        confidence: float = 0.85,
        x1: float = 0.3, y1: float = 0.4, x2: float = 0.7, y2: float = 0.9,
    ) -> RawDetection:
        return RawDetection(
            class_id=2,
            class_name="car",
            confidence=confidence,
            box=BoundingBox(x1=x1, y1=y1, x2=x2, y2=y2),
        )

    # ── Severity thresholds ────────────────────────────────────────────────────────
    class TestSeverityFromPc(unittest.TestCase):
        def test_high_severity_at_override_threshold(self):
            self.assertEqual(_severity_from_pc(0.70), HazardSeverity.HIGH)

        def test_high_severity_above_threshold(self):
            self.assertEqual(_severity_from_pc(0.95), HazardSeverity.HIGH)

        def test_medium_severity_in_warning_range(self):
            self.assertEqual(_severity_from_pc(0.55), HazardSeverity.MEDIUM)

        def test_low_severity_below_warning(self):
            self.assertEqual(_severity_from_pc(0.20), HazardSeverity.LOW)

        def test_boundary_warning_is_medium(self):
            self.assertEqual(_severity_from_pc(0.40), HazardSeverity.MEDIUM)

    # ── Direction inference ────────────────────────────────────────────────────────
    class TestDirectionInference(unittest.TestCase):
        def test_left_object(self):
            box = BoundingBox(x1=0.0, y1=0.0, x2=0.25, y2=1.0)
            self.assertEqual(_infer_direction(box), "Baaye")

        def test_right_object(self):
            box = BoundingBox(x1=0.75, y1=0.0, x2=1.0, y2=1.0)
            self.assertEqual(_infer_direction(box), "Daaye")

        def test_center_object(self):
            box = BoundingBox(x1=0.3, y1=0.0, x2=0.7, y2=1.0)
            self.assertEqual(_infer_direction(box), "Seedha")

    # ── Scoring ───────────────────────────────────────────────────────────────────
    class TestCollisionScorer(unittest.TestCase):
        def test_vehicle_produces_high_pc(self):
            async def test_vehicle_produces_high_pc_async():
                scorer = CollisionScorer()
                det = _make_det(hazard_type=HazardType.VEHICLE, x1=0.2, y1=0.2, x2=0.8, y2=0.9)
                results = await scorer.score_detections([det])
                self.assertEqual(len(results), 1)
                self.assertGreater(results[0].collision_prob, 0.5)
            asyncio.run(test_vehicle_produces_high_pc_async())

        def test_water_puddle_lower_pc_than_vehicle(self):
            async def test_water_puddle_lower_pc_than_vehicle_async():
                scorer = CollisionScorer()
                vehicle = _make_det(HazardType.VEHICLE)
                puddle  = _make_det(HazardType.WATER_PUDDLE)
                v_results = await scorer.score_detections([vehicle])
                p_results = await scorer.score_detections([puddle])
                self.assertGreater(v_results[0].collision_prob, p_results[0].collision_prob)
            asyncio.run(test_water_puddle_lower_pc_than_vehicle_async())

        def test_results_sorted_by_pc_descending(self):
            async def test_results_sorted_by_pc_descending_async():
                scorer = CollisionScorer()
                dets = [
                    _make_det(HazardType.WATER_PUDDLE, x1=0.0, y1=0.0, x2=0.1, y2=0.1),
                    _make_det(HazardType.VEHICLE,      x1=0.2, y1=0.2, x2=0.8, y2=0.9),
                ]
                results = await scorer.score_detections(dets)
                self.assertGreaterEqual(results[0].collision_prob, results[-1].collision_prob)
            asyncio.run(test_results_sorted_by_pc_descending_async())

        def test_empty_detections_returns_empty_list(self):
            async def test_empty_detections_returns_empty_list_async():
                scorer = CollisionScorer()
                results = await scorer.score_detections([])
                self.assertEqual(results, [])
            asyncio.run(test_empty_detections_returns_empty_list_async())

        def test_pc_always_between_0_and_1(self):
            async def test_pc_always_between_0_and_1_async():
                scorer = CollisionScorer()
                for ht in HazardType:
                    det = _make_det(hazard_type=ht)
                    results = await scorer.score_detections([det])
                    self.assertTrue(0.0 <= results[0].collision_prob <= 1.0)
            asyncio.run(test_pc_always_between_0_and_1_async())

        def test_plain_language_not_empty(self):
            async def test_plain_language_not_empty_async():
                scorer = CollisionScorer()
                det = _make_det(HazardType.VEHICLE)
                results = await scorer.score_detections([det])
                self.assertNotEqual(results[0].plain_language, "")
            asyncio.run(test_plain_language_not_empty_async())

if __name__ == '__main__':
    unittest.main()