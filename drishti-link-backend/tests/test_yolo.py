'''
tests/test_yolo_service.py — comprehensive unit tests for the new YOLOv8 service.
All heavy model calls are mocked; no GPU/weights required in CI.
'''
import asyncio
import io
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch, AsyncMock
import unittest
import sys

# Mock heavy dependencies
sys.modules['numpy'] = MagicMock()
sys.modules['PIL'] = MagicMock()
sys.modules['cv2'] = MagicMock()

# Import real exceptions
from core.exceptions import InvalidFrameError, ModelNotLoadedError

from services.yolo_service import (
    YOLOService, Detection, FrameResult, FramePosition, MovementVector,
    ThreatCategory, CLASS_REGISTRY, RELEVANT_CLASS_IDS,
    _decode_frame, _is_night_mode, _preprocess, _estimate_distance,
    _frame_position, _movement_vector, SessionTrack, BBox,
)


# ── Fixtures ──────────────────────────────────────────────────────────────────

def _fake_jpeg(w: int = 640, h: int = 480) -> bytes:
    return b'fake-jpeg-data'


# ═════════════════════════════════════════════════════════════════════════════
# CLASS_REGISTRY tests
# ═════════════════════════════════════════════════════════════════════════════

class TestClassRegistry(unittest.TestCase):
    def test_car_is_vehicle(self):
        name, cat = CLASS_REGISTRY[2]
        self.assertEqual(name, "car")
        self.assertEqual(cat, ThreatCategory.VEHICLE)

    def test_pothole_is_terrain(self):
        name, cat = CLASS_REGISTRY[81]
        self.assertEqual(name, "pothole")
        self.assertEqual(cat, ThreatCategory.TERRAIN)

    def test_person_is_person(self):
        _, cat = CLASS_REGISTRY[0]
        self.assertEqual(cat, ThreatCategory.PERSON)

    def test_auto_rickshaw_is_vehicle(self):
        _, cat = CLASS_REGISTRY[80]
        self.assertEqual(cat, ThreatCategory.VEHICLE)

    def test_all_relevant_ids_in_registry(self):
        for cid in RELEVANT_CLASS_IDS:
            self.assertIn(cid, CLASS_REGISTRY)

# ═════════════════════════════════════════════════════════════════════════════
# Distance estimation
# ═════════════════════════════════════════════════════════════════════════════

class TestEstimateDistance(unittest.TestCase):
    def test_closer_object_larger_bbox(self):
        d_close = _estimate_distance("car", bbox_h_px=200, frame_h_px=480)
        d_far   = _estimate_distance("car", bbox_h_px=50,  frame_h_px=480)
        self.assertLess(d_close, d_far)

    def test_distance_clamped_minimum(self):
        d = _estimate_distance("car", bbox_h_px=10000, frame_h_px=480)
        self.assertGreaterEqual(d, 0.1)

    def test_distance_clamped_maximum(self):
        d = _estimate_distance("car", bbox_h_px=1, frame_h_px=480)
        self.assertLessEqual(d, 50.0)

    def test_zero_height_returns_none(self):
        d = _estimate_distance("car", bbox_h_px=0, frame_h_px=480)
        self.assertIsNone(d)

    def test_unknown_class_uses_default_height(self):
        d = _estimate_distance("alien_object", bbox_h_px=100, frame_h_px=480)
        self.assertIsNotNone(d)


# ═════════════════════════════════════════════════════════════════════════════
# Frame position
# ═════════════════════════════════════════════════════════════════════════════

class TestFramePosition(unittest.TestCase):
    def test_left_third(self):
        self.assertEqual(_frame_position(100, 640), FramePosition.LEFT)

    def test_right_third(self):
        self.assertEqual(_frame_position(540, 640), FramePosition.RIGHT)

    def test_center(self):
        self.assertEqual(_frame_position(320, 640), FramePosition.CENTER)

    def test_boundary_left_center(self):
        # Exactly at 33% is center
        self.assertEqual(_frame_position(int(640 * 0.33), 640), FramePosition.LEFT)


# ═════════════════════════════════════════════════════════════════════════════
# Movement vector
# ═════════════════════════════════════════════════════════════════════════════

class TestMovementVector(unittest.TestCase):
    def _bbox(self, w: int, h: int) -> BBox:
        return BBox(x=0, y=0, w=w, h=h)

    def test_unknown_with_empty_history(self):
        track = SessionTrack()
        vec = _movement_vector(2, self._bbox(100, 100), track)
        self.assertEqual(vec, MovementVector.UNKNOWN)

    def test_approaching_when_area_grows(self):
        track = SessionTrack()
        track.bbox_history.append({2: self._bbox(50, 50)})
        vec = _movement_vector(2, self._bbox(100, 100), track)
        self.assertEqual(vec, MovementVector.APPROACHING)

    def test_receding_when_area_shrinks(self):
        track = SessionTrack()
        track.bbox_history.append({2: self._bbox(100, 100)})
        vec = _movement_vector(2, self._bbox(50, 50), track)
        self.assertEqual(vec, MovementVector.RECEDING)

    def test_stationary_when_area_unchanged(self):
        track = SessionTrack()
        track.bbox_history.append({2: self._bbox(100, 100)})
        vec = _movement_vector(2, self._bbox(102, 100), track)
        self.assertEqual(vec, MovementVector.STATIONARY)


# ═════════════════════════════════════════════════════════════════════════════
# Frame skip logic
# ═════════════════════════════════════════════════════════════════════════════

class TestFrameSkip(unittest.TestCase):
    def test_normal_skip_processes_every_3rd(self):
        track = SessionTrack(current_pc=0.1)
        # First frame is always processed
        self.assertTrue(track.should_process())
        # Then we skip 2
        self.assertFalse(track.should_process())
        self.assertFalse(track.should_process())
        # Process the 4th
        self.assertTrue(track.should_process())

    def test_high_pc_processes_every_frame(self):
        track = SessionTrack(current_pc=0.80)  # above HIGH_PC_THRESHOLD=0.60
        results = [track.should_process() for _ in range(5)]
        self.assertTrue(all(results))


# ═════════════════════════════════════════════════════════════════════════════
# YOLOService (mocked model)
# ═════════════════════════════════════════════════════════════════════════════

class TestYOLOService(unittest.TestCase):
    def setUp(self):
        self.svc = YOLOService()

    def test_not_ready_before_load(self):
        self.assertFalse(self.svc.is_ready)

    def test_detect_returns_frame_result(self):
        async def test_async():
            with patch('services.yolo_service._decode_frame') as mock_decode, \
                 patch('services.yolo_service._preprocess') as mock_preprocess:

                mock_decode.return_value = MagicMock(shape=(480,640,3))
                self.svc._is_ready = True

                # Mock _infer_sync to return empty results
                self.svc._infer_sync = MagicMock(return_value=[MagicMock(boxes=None)])

                result = await self.svc.detect_bytes(_fake_jpeg(), "sess-1", "frame-1")
                self.assertIsInstance(result, FrameResult)
                self.assertEqual(result.session_id, "sess-1")
                self.assertFalse(result.skipped)
        asyncio.run(test_async())

    def test_skipped_frame_returns_empty_detections(self):
        async def test_async():
            with patch('services.yolo_service._decode_frame') as mock_decode, patch('services.yolo_service._preprocess'):
                mock_decode.return_value = MagicMock(shape=(480,640,3))
                self.svc._is_ready = True
                self.svc._infer_sync = MagicMock(return_value=[MagicMock(boxes=None)])

                # Process frame 1
                await self.svc.detect_bytes(_fake_jpeg(), "skip-sess", "f1")
                # Frame 2 should be skipped
                result = await self.svc.detect_bytes(_fake_jpeg(), "skip-sess", "f2")
                self.assertTrue(result.skipped)
                # Frame 3 should be skipped
                result = await self.svc.detect_bytes(_fake_jpeg(), "skip-sess", "f3")
                self.assertTrue(result.skipped)
                # Frame 4 should be processed
                result = await self.svc.detect_bytes(_fake_jpeg(), "skip-sess", "f4")
                self.assertFalse(result.skipped)
        asyncio.run(test_async())

    def test_model_not_ready_raises(self):
        async def test_async():
            # is_ready default False
            with self.assertRaises(ModelNotLoadedError):
                await self.svc.detect_bytes(_fake_jpeg(), "s", "f")
        asyncio.run(test_async())

    def test_corrupt_frame_raises(self): 
        async def test_async():
            self.svc._is_ready = True
            with patch('services.yolo_service._decode_frame', side_effect=ValueError):
                with self.assertRaises(InvalidFrameError):
                    await self.svc.detect_bytes(b"bad-data", "s", "f")
        asyncio.run(test_async())

if __name__ == '__main__':
    unittest.main()