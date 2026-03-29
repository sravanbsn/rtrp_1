'''
tests/test_mediapipe_service.py — unit tests for the MediaPipe motion service.
Mocks mediapipe to allow CI without the library installed.
'''
import asyncio
import io
import unittest
import sys
from unittest.mock import MagicMock, patch

# Mock heavy dependencies
sys.modules['numpy'] = MagicMock()
sys.modules['PIL'] = MagicMock()
sys.modules['cv2'] = MagicMock()

from services.mediapipe_service import (
    MediaPipeService,
    MotionResult,
    _SessionPoseState,
    _LandmarkSnap,
    _decode_dual,
    _heuristic_depth,
    _elapsed_ms,
    STUMBLE_HIP_DROP_THRESHOLD,
    TURN_ANGLE_THRESHOLD_DEG,
)

def _fake_jpeg(w: int = 320, h: int = 240) -> bytes:
    return b'fake-jpeg-data'

class TestLandmarkSnap(unittest.TestCase):
    def _snap(self, **kwargs):
        defaults = dict(
            nose_y=0.1, left_shoulder_y=0.3, right_shoulder_y=0.3,
            left_hip_y=0.6, right_hip_y=0.6,
            left_ankle_y=0.9, right_ankle_y=0.9,
            left_shoulder_x=0.3, right_shoulder_x=0.7,
            visibility=0.9,
        )
        defaults.update(kwargs)
        return _LandmarkSnap(**defaults)

    def test_mid_hip_y(self):
        snap = self._snap(left_hip_y=0.5, right_hip_y=0.7)
        self.assertAlmostEqual(snap.mid_hip_y, 0.6)

    def test_avg_ankle_y(self):
        snap = self._snap(left_ankle_y=0.8, right_ankle_y=0.9)
        self.assertAlmostEqual(snap.avg_ankle_y, 0.85)

    def test_shoulder_tilt_horizontal(self):
        snap = self._snap(
            left_shoulder_x=0.3, right_shoulder_x=0.7,
            left_shoulder_y=0.3, right_shoulder_y=0.3,
        )
        self.assertAlmostEqual(snap.shoulder_tilt_deg, 0.0, delta=1.0)

    def test_shoulder_tilt_positive_right_higher(self):
        snap = self._snap(
            left_shoulder_x=0.3, right_shoulder_x=0.7,
            left_shoulder_y=0.3, right_shoulder_y=0.5,
        )
        self.assertGreater(snap.shoulder_tilt_deg, TURN_ANGLE_THRESHOLD_DEG)

class TestKinematics(unittest.TestCase):
    def _snap(self, hip_y=0.6, ankle_y=0.9, lsx=0.3, rsx=0.7, lsy=0.3, rsy=0.3):
        return _LandmarkSnap(
            nose_y=0.1,
            left_shoulder_y=lsy, right_shoulder_y=rsy,
            left_hip_y=hip_y, right_hip_y=hip_y,
            left_ankle_y=ankle_y, right_ankle_y=ankle_y,
            left_shoulder_x=lsx, right_shoulder_x=rsx,
            visibility=0.9,
        )

    def test_stumble_detected_on_hip_drop(self):
        svc = MediaPipeService.__new__(MediaPipeService)
        svc._pose_available = False
        svc._sessions = {}

        state = _SessionPoseState()
        snap_prev = self._snap(hip_y=0.4)
        snap_curr = self._snap(hip_y=0.4 + STUMBLE_HIP_DROP_THRESHOLD + 0.01)

        state.snap_history.append(snap_prev)
        result = MotionResult()
        # Call the kinematic computation directly
        svc._compute_kinematics = MediaPipeService._compute_kinematics.__get__(svc)
        state.snap_history.append(snap_prev)
        result = MotionResult()
        result = MediaPipeService._compute_kinematics(svc, snap_curr, state, result)
        self.assertTrue(result.stumble_detected)

    def test_no_stumble_on_normal_walk(self):
        svc = MediaPipeService.__new__(MediaPipeService)
        state = _SessionPoseState()
        snap_prev = self._snap(hip_y=0.6)
        snap_curr = self._snap(hip_y=0.61)

        state.snap_history.append(snap_prev)
        result = MotionResult()
        result = MediaPipeService._compute_kinematics(svc, snap_curr, state, result)
        self.assertFalse(result.stumble_detected)

    def test_turn_detected_on_large_shoulder_tilt(self):
        svc = MediaPipeService.__new__(MediaPipeService)
        state = _SessionPoseState()
        snap = self._snap(lsx=0.3, rsx=0.7, lsy=0.3, rsy=0.55)
        result = MotionResult()
        result = MediaPipeService._compute_kinematics(svc, snap, state, result)
        self.assertTrue(result.turn_detected)
        self.assertIn(result.turn_direction, ("left", "right"))

    def test_direction_stopped_when_low_velocity(self):
        svc = MediaPipeService.__new__(MediaPipeService)
        state = _SessionPoseState()
        for _ in range(5):
            state.snap_history.append(self._snap(ankle_y=0.9))
        snap = self._snap(ankle_y=0.9)
        result = MotionResult()
        result = MediaPipeService._compute_kinematics(svc, snap, state, result)
        self.assertEqual(result.user_direction, "stopped")

class TestMediaPipeServiceDegraded(unittest.TestCase):
    def test_analyze_returns_motion_result_without_mediapipe(self):
        async def test_async():
            with patch('services.mediapipe_service._decode_dual') as mock_decode_dual:
                mock_decode_dual.return_value = (MagicMock(), MagicMock())
                svc = MediaPipeService.__new__(MediaPipeService)
                svc._pose_available = False
                svc._pose_model     = None
                svc._sessions       = {}

                result = await svc.analyze(_fake_jpeg(), "s1")
                self.assertIsInstance(result, MotionResult)
                self.assertFalse(result.pose_available)
        asyncio.run(test_async())

    def test_estimate_depth_returns_dict(self):
        async def test_async():
            with patch('services.mediapipe_service._heuristic_depth') as mock_heuristic_depth, \
                 patch('PIL.Image') as mock_Image:
                
                mock_img = MagicMock()
                mock_img.size = (320, 240)
                mock_Image.open.return_value = mock_img

                mock_depth_map = MagicMock()
                mock_depth_map.tolist.return_value = [[1.0] * 320] * 240
                mock_heuristic_depth.return_value = mock_depth_map

                svc = MediaPipeService.__new__(MediaPipeService)
                svc._pose_available = False
                svc._sessions       = {}

                depth = await svc.estimate_depth(_fake_jpeg())
                self.assertIn("width", depth)
                self.assertIn("height", depth)
                self.assertIn("data", depth)
        asyncio.run(test_async())

    def test_cleanup_session(self):
        svc = MediaPipeService.__new__(MediaPipeService)
        svc._sessions = {"s1": _SessionPoseState()}
        svc.cleanup_session("s1")
        self.assertNotIn("s1", svc._sessions)

if __name__ == '__main__':
    unittest.main()