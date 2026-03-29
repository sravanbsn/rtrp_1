"""
services/mediapipe_service.py

MediaPipe depth + motion tracking service — Drishti-Link.

Provides:
  ● User body pose estimation  → walking velocity, direction, stumble
  ● Dense optical flow         → per-object motion field
  ● Turn detection             → left/right from shoulder orientation
  ● Stumble detection          → sudden vertical drop in hip landmarks

All heavy processing runs in a dedicated single-threaded executor
to keep MediaPipe's internal state consistent between frames.
"""

from __future__ import annotations

import asyncio
import dataclasses
import io
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from typing import Optional

import cv2
import numpy as np
import structlog
from PIL import Image

log = structlog.get_logger(__name__)

# Single-threaded executor: MediaPipe graph is NOT thread-safe
_MP_EXECUTOR = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mediapipe")


# ═════════════════════════════════════════════════════════════════════════════
# Constants
# ═════════════════════════════════════════════════════════════════════════════

# Pose landmarks we care about (MediaPipe Pose full-body indices)
MP_NOSE           = 0
MP_LEFT_SHOULDER  = 11
MP_RIGHT_SHOULDER = 12
MP_LEFT_HIP       = 23
MP_RIGHT_HIP      = 24
MP_LEFT_KNEE      = 25
MP_RIGHT_KNEE     = 26
MP_LEFT_ANKLE     = 27
MP_RIGHT_ANKLE    = 28

# Stumble: hip drops more than this fraction of frame height in one frame
STUMBLE_HIP_DROP_THRESHOLD = 0.08

# Turn: shoulder tilt > this angle (degrees) → turning
TURN_ANGLE_THRESHOLD_DEG = 15.0

# Velocity smoothing window (frames)
VELOCITY_WINDOW = 10


# ═════════════════════════════════════════════════════════════════════════════
# Data classes
# ═════════════════════════════════════════════════════════════════════════════

@dataclasses.dataclass
class MotionResult:
    """Complete motion analysis result for one frame pair."""

    # ── User body kinematics ────────────────────────────────────────────────
    user_velocity_mps:   float              = 0.0    # walking speed estimate (m/s)
    user_direction:      str                = "forward"  # "forward" | "left" | "right" | "stopped"
    turn_detected:       bool               = False
    turn_direction:      Optional[str]      = None   # "left" | "right"
    stumble_detected:    bool               = False
    pose_confidence:     float              = 0.0    # 0-1, median landmark visibility

    # ── Optical flow ─────────────────────────────────────────────────────────
    global_flow_magnitude: float            = 0.0   # average pixel displacement
    dominant_flow_vector:  tuple[float, float] = (0.0, 0.0)   # (dx, dy) per frame

    # ── Processing metadata ──────────────────────────────────────────────────
    pose_available:      bool               = False
    flow_available:      bool               = False
    processing_ms:       float              = 0.0

    def to_dict(self) -> dict:
        return dataclasses.asdict(self)


@dataclasses.dataclass
class _LandmarkSnap:
    """Lightweight snapshot of key pose landmarks (normalized 0-1)."""
    nose_y:          float
    left_shoulder_y: float
    right_shoulder_y:float
    left_hip_y:      float
    right_hip_y:     float
    left_ankle_y:    float
    right_ankle_y:   float
    left_shoulder_x: float
    right_shoulder_x:float
    visibility:      float   # median visibility of all tracked landmarks

    @property
    def mid_hip_y(self) -> float:
        return (self.left_hip_y + self.right_hip_y) / 2

    @property
    def shoulder_tilt_deg(self) -> float:
        """Signed angle of shoulder line relative to horizontal (degrees)."""
        dy = self.right_shoulder_y - self.left_shoulder_y
        dx = self.right_shoulder_x - self.left_shoulder_x
        if abs(dx) < 1e-6:
            return 0.0
        return float(np.degrees(np.arctan2(dy, dx)))

    @property
    def avg_ankle_y(self) -> float:
        return (self.left_ankle_y + self.right_ankle_y) / 2


# ═════════════════════════════════════════════════════════════════════════════
# Per-session pose + flow state
# ═════════════════════════════════════════════════════════════════════════════

@dataclasses.dataclass
class _SessionPoseState:
    snap_history:       deque = dataclasses.field(default_factory=lambda: deque(maxlen=VELOCITY_WINDOW))
    prev_gray:          Optional[np.ndarray] = None
    prev_flow_pts:      Optional[np.ndarray] = None


# ═════════════════════════════════════════════════════════════════════════════
# MediaPipeService
# ═════════════════════════════════════════════════════════════════════════════

class MediaPipeService:
    """
    Stateful per-session pose + optical-flow analyser.
    Thread-safe for multiple concurrent sessions (each session owns its state dict).
    """

    def __init__(self) -> None:
        self._sessions: dict[str, _SessionPoseState] = {}
        self._pose_available = False
        self._pose_model: Optional[object] = None
        self._try_init_pose()

    # ── Startup ──────────────────────────────────────────────────────────────
    def _try_init_pose(self) -> None:
        """Attempt to load MediaPipe Pose. Gracefully degrades if unavailable."""
        try:
            import mediapipe as mp
            self._mp_pose    = mp.solutions.pose
            self._pose_model = self._mp_pose.Pose(
                static_image_mode=False,
                model_complexity=1,          # 0=lite, 1=full, 2=heavy
                smooth_landmarks=True,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            )
            self._pose_available = True
            log.info("mediapipe.pose_ready")
        except ImportError:
            log.warning("mediapipe.not_installed", fallback="heuristic_mode")
        except Exception as exc:
            log.error("mediapipe.init_failed", exc=str(exc))

    # ── Public API ────────────────────────────────────────────────────────────
    async def analyze(
        self,
        frame_bytes: bytes,
        session_id:  str,
    ) -> MotionResult:
        """
        Full async motion analysis for one frame.
        Runs pose estimation + optical flow in the single-threaded executor.
        """
        t0 = time.perf_counter()

        # Decode once; reuse for both pose and flow
        try:
            img_rgb, img_gray = await asyncio.get_running_loop().run_in_executor(
                _MP_EXECUTOR, _decode_dual, frame_bytes
            )
        except Exception as exc:
            log.error("mediapipe.decode_error", exc=str(exc), session_id=session_id)
            return MotionResult(processing_ms=_elapsed_ms(t0))

        state = self._get_state(session_id)

        # Run both analyses in the executor
        result: MotionResult = await asyncio.get_running_loop().run_in_executor(
            _MP_EXECUTOR,
            self._analyze_sync,
            img_rgb, img_gray, state,
        )
        result.processing_ms = _elapsed_ms(t0)

        log.debug(
            "mediapipe.analyzed",
            session_id=session_id,
            velocity=result.user_velocity_mps,
            turn=result.turn_detected,
            stumble=result.stumble_detected,
            ms=result.processing_ms,
        )
        return result

    async def estimate_depth(self, frame_bytes: bytes) -> dict:
        """
        Simple monocular depth map (compatible with existing collision scorer).
        Uses MediaPipe or falls back to vertical-heuristic.
        """
        try:
            img_rgb, img_gray = await asyncio.get_running_loop().run_in_executor(
                _MP_EXECUTOR, _decode_dual, frame_bytes
            )
        except Exception:
            return {}

        h, w = img_gray.shape
        depth_data = _heuristic_depth(h, w)
        return {"width": w, "height": h, "data": depth_data.tolist()}

    def cleanup_session(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)

    # ── Internal (runs in _MP_EXECUTOR) ──────────────────────────────────────
    def _analyze_sync(
        self,
        img_rgb:  np.ndarray,
        img_gray: np.ndarray,
        state:    _SessionPoseState,
    ) -> MotionResult:
        result = MotionResult()

        # ── Pose estimation ───────────────────────────────────────────────
        if self._pose_available and self._pose_model is not None:
            snap = self._run_pose(img_rgb)
            if snap is not None:
                result.pose_available  = True
                result.pose_confidence = snap.visibility
                result = self._compute_kinematics(snap, state, result)

        # ── Dense optical flow ────────────────────────────────────────────
        if state.prev_gray is not None:
            result = self._compute_optical_flow(img_gray, state.prev_gray, result)
            result.flow_available = True

        # Update state for next frame
        state.prev_gray = img_gray.copy()

        return result

    def _run_pose(self, img_rgb: np.ndarray) -> Optional[_LandmarkSnap]:
        """Run MediaPipe Pose and extract key landmark snapshot."""
        try:
            mp_result = self._pose_model.process(img_rgb)
            if not mp_result.pose_landmarks:
                return None

            lm = mp_result.pose_landmarks.landmark

            def y(idx: int) -> float:
                return float(lm[idx].y)

            def x(idx: int) -> float:
                return float(lm[idx].x)

            def vis(idx: int) -> float:
                return float(lm[idx].visibility)

            tracked_indices = [
                MP_NOSE, MP_LEFT_SHOULDER, MP_RIGHT_SHOULDER,
                MP_LEFT_HIP, MP_RIGHT_HIP,
                MP_LEFT_ANKLE, MP_RIGHT_ANKLE,
            ]
            median_vis = float(np.median([vis(i) for i in tracked_indices]))

            return _LandmarkSnap(
                nose_y=y(MP_NOSE),
                left_shoulder_y=y(MP_LEFT_SHOULDER),
                right_shoulder_y=y(MP_RIGHT_SHOULDER),
                left_hip_y=y(MP_LEFT_HIP),
                right_hip_y=y(MP_RIGHT_HIP),
                left_ankle_y=y(MP_LEFT_ANKLE),
                right_ankle_y=y(MP_RIGHT_ANKLE),
                left_shoulder_x=x(MP_LEFT_SHOULDER),
                right_shoulder_x=x(MP_RIGHT_SHOULDER),
                visibility=median_vis,
            )

        except Exception as exc:
            log.warning("mediapipe.pose_error", exc=str(exc))
            return None

    def _compute_kinematics(
        self,
        snap:   _LandmarkSnap,
        state:  _SessionPoseState,
        result: MotionResult,
    ) -> MotionResult:
        """
        Infer walking velocity, direction, stumble, and turn from pose snapshots.
        """
        state.snap_history.append(snap)
        n = len(state.snap_history)

        # ── Velocity: ankle vertical oscillation amplitude → speed ──────────
        if n >= 2:
            ankle_ys = [s.avg_ankle_y for s in state.snap_history]
            # Walking produces periodic ankle oscillation; amplitude ∝ speed
            amplitude = float(np.ptp(ankle_ys))   # peak-to-peak
            # Calibration: amplitude of 0.05 ≈ 1 m/s walking
            result.user_velocity_mps = round(min(amplitude * 20.0, 3.0), 2)

        # ── Stumble: sudden hip drop ─────────────────────────────────────────
        if n >= 2:
            prev_snap = state.snap_history[-2]
            hip_drop = snap.mid_hip_y - prev_snap.mid_hip_y
            if hip_drop > STUMBLE_HIP_DROP_THRESHOLD:
                result.stumble_detected = True
                log.warning("mediapipe.stumble_detected")

        # ── Turn: shoulder tilt ───────────────────────────────────────────────
        tilt = snap.shoulder_tilt_deg
        if abs(tilt) > TURN_ANGLE_THRESHOLD_DEG:
            result.turn_detected   = True
            result.turn_direction  = "right" if tilt > 0 else "left"
            result.user_direction  = result.turn_direction
        elif result.user_velocity_mps < 0.1:
            result.user_direction = "stopped"
        else:
            result.user_direction = "forward"

        return result

    def _compute_optical_flow(
        self,
        current_gray: np.ndarray,
        prev_gray:    np.ndarray,
        result:       MotionResult,
    ) -> MotionResult:
        """
        Dense Farneback optical flow.
        Returns global flow magnitude and dominant flow vector.
        """
        try:
            flow = cv2.calcOpticalFlowFarneback(
                prev_gray, current_gray,
                None,
                pyr_scale=0.5, levels=3, winsize=15,
                iterations=3, poly_n=5, poly_sigma=1.1,
                flags=0,
            )
            # flow shape: (H, W, 2) → (dx, dy) per pixel
            magnitude, angle = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            result.global_flow_magnitude = float(np.mean(magnitude))

            # Dominant direction = mean flow vector
            mean_dx = float(np.mean(flow[..., 0]))
            mean_dy = float(np.mean(flow[..., 1]))
            result.dominant_flow_vector = (round(mean_dx, 2), round(mean_dy, 2))

        except cv2.error as exc:
            log.warning("mediapipe.flow_error", exc=str(exc))

        return result

    # ── Session management ────────────────────────────────────────────────────
    def _get_state(self, session_id: str) -> _SessionPoseState:
        if session_id not in self._sessions:
            self._sessions[session_id] = _SessionPoseState()
        return self._sessions[session_id]


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

def _decode_dual(frame_bytes: bytes) -> tuple[np.ndarray, np.ndarray]:
    """Decode bytes → (RGB ndarray, Gray ndarray). Runs in executor."""
    arr = np.frombuffer(frame_bytes, dtype=np.uint8)
    bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if bgr is None:
        raise ValueError("Could not decode frame — corrupt or unsupported format")
    rgb  = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    return rgb, gray


def _heuristic_depth(h: int, w: int) -> np.ndarray:
    """
    Fallback depth map when MediaPipe depth is unavailable.
    Objects at the bottom of the frame (on flat ground) are closer.
    depth[y, x] = 1.0 + (1 - y/H) * 14   → range: 1m (bottom) to 15m (top)
    """
    y_indices = np.arange(h, dtype=np.float32).reshape(h, 1)
    depth = 1.0 + (1.0 - y_indices / max(h, 1)) * 14.0
    return np.tile(depth, (1, w))


def _elapsed_ms(t0: float) -> float:
    return round((time.perf_counter() - t0) * 1000, 2)
