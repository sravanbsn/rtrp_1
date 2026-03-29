"""
monitoring/metrics.py

Professional Monitoring System — Drishti-Link
══════════════════════════════════════════════

Thread-safe, zero-dependency metrics collector.
Exposes a JSON snapshot at GET /api/v1/admin/metrics.

Three metric domains:

  PERFORMANCE  — frame latency, WS connections, frames/sec, API times
  AI           — override rate, FP rate, model inference time, confidence
  BUSINESS     — active sessions, DAU proxy, SOS events, distance, hazards avoided
"""

from __future__ import annotations

import math
import statistics
import threading
import time
from collections import deque, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


# ═════════════════════════════════════════════════════════════════════════════
# Thread-safe ring-buffer for latency samples
# ═════════════════════════════════════════════════════════════════════════════

class _RingBuffer:
    """Fixed-size FIFO for computing rolling statistics."""

    def __init__(self, maxlen: int = 500) -> None:
        self._buf:  deque[float] = deque(maxlen=maxlen)
        self._lock  = threading.Lock()

    def add(self, value: float) -> None:
        with self._lock:
            self._buf.append(value)

    def snapshot(self) -> list[float]:
        with self._lock:
            return list(self._buf)

    def stats(self) -> dict:
        data = self.snapshot()
        if not data:
            return {"count": 0, "mean": 0, "p50": 0, "p95": 0, "p99": 0, "max": 0}
        s = sorted(data)
        n = len(s)
        return {
            "count": n,
            "mean":  round(statistics.mean(s), 2),
            "p50":   round(s[int(n * 0.50)], 2),
            "p95":   round(s[min(int(n * 0.95), n - 1)], 2),
            "p99":   round(s[min(int(n * 0.99), n - 1)], 2),
            "max":   round(s[-1], 2),
        }


# ═════════════════════════════════════════════════════════════════════════════
# Thread-safe counter
# ═════════════════════════════════════════════════════════════════════════════

class _Counter:
    def __init__(self) -> None:
        self._val  = 0
        self._lock = threading.Lock()

    def inc(self, n: int = 1) -> None:
        with self._lock:
            self._val += n

    def dec(self, n: int = 1) -> None:
        with self._lock:
            self._val = max(0, self._val - n)

    def get(self) -> int:
        with self._lock:
            return self._val

    def reset(self) -> int:
        with self._lock:
            v = self._val
            self._val = 0
            return v


# ═════════════════════════════════════════════════════════════════════════════
# Frames-per-second tracker
# ═════════════════════════════════════════════════════════════════════════════

class _FPSTracker:
    """Sliding-window FPS: counts frames in the last N seconds."""

    def __init__(self, window_s: float = 5.0) -> None:
        self._window = window_s
        self._times:  deque[float] = deque()
        self._lock    = threading.Lock()

    def mark(self) -> None:
        now = time.monotonic()
        with self._lock:
            self._times.append(now)
            cutoff = now - self._window
            while self._times and self._times[0] < cutoff:
                self._times.popleft()

    def fps(self) -> float:
        now = time.monotonic()
        with self._lock:
            cutoff = now - self._window
            while self._times and self._times[0] < cutoff:
                self._times.popleft()
            count = len(self._times)
        return round(count / self._window, 2)


# ═════════════════════════════════════════════════════════════════════════════
# Per-endpoint latency tracker
# ═════════════════════════════════════════════════════════════════════════════

class _EndpointLatency:
    def __init__(self) -> None:
        self._endpoints: dict[str, _RingBuffer] = defaultdict(lambda: _RingBuffer(200))
        self._lock = threading.Lock()

    def record(self, path: str, ms: float) -> None:
        with self._lock:
            self._endpoints[path].add(ms)

    def snapshot(self) -> dict:
        with self._lock:
            return {path: buf.stats() for path, buf in self._endpoints.items()}


# ═════════════════════════════════════════════════════════════════════════════
# Confidence distribution tracker
# ═════════════════════════════════════════════════════════════════════════════

class _ConfidenceDistribution:
    """Histogram: 10 buckets from 0–100%."""

    def __init__(self) -> None:
        self._buckets = [0] * 10   # [0-10, 10-20, ..., 90-100]
        self._lock    = threading.Lock()

    def record(self, confidence: float) -> None:
        bucket = min(int(confidence * 10), 9)
        with self._lock:
            self._buckets[bucket] += 1

    def snapshot(self) -> dict:
        with self._lock:
            total = sum(self._buckets)
            buckets = list(self._buckets)
        labels = [f"{i*10}-{i*10+10}%" for i in range(10)]
        return {
            "total": total,
            "buckets": {labels[i]: buckets[i] for i in range(10)},
        }


# ═════════════════════════════════════════════════════════════════════════════
# MetricsCollector — main class
# ═════════════════════════════════════════════════════════════════════════════

class MetricsCollector:
    """
    Central thread-safe metrics collector.

    Usage:
        # At startup:
        metrics = MetricsCollector()
        app.state.metrics = metrics

        # In middleware:
        metrics.record_api_latency(request.url.path, ms)

        # In WS handler:
        metrics.ws_connected()
        metrics.record_frame(processing_ms)
        metrics.record_override()
    """

    def __init__(self) -> None:
        self._started_at = time.monotonic()
        self._started_iso = datetime.now(timezone.utc).isoformat()

        # ── Performance ───────────────────────────────────────────────────────
        self._frame_latency    = _RingBuffer(1000)
        self._inference_latency = _RingBuffer(1000)
        self._api_latency      = _EndpointLatency()
        self._fps              = _FPSTracker(window_s=5.0)
        self._ws_active        = _Counter()

        # ── AI metrics ────────────────────────────────────────────────────────
        self._overrides        = _Counter()
        self._warnings         = _Counter()
        self._frames_total     = _Counter()
        self._overrides_cancelled = _Counter()   # FP indicator
        self._confidence_dist  = _ConfidenceDistribution()

        # ── Business metrics ──────────────────────────────────────────────────
        self._sos_count        = _Counter()
        self._hazards_avoided  = _Counter()
        self._total_distance_m = _Counter()

        # Daily user set (approximate) — resets at midnight
        self._dau_set: set[str] = set()
        self._dau_lock = threading.Lock()
        self._dau_date: str = datetime.now(timezone.utc).date().isoformat()

    # ── WebSocket events ──────────────────────────────────────────────────────

    def ws_connected(self) -> None:
        self._ws_active.inc()

    def ws_disconnected(self) -> None:
        self._ws_active.dec()

    # ── Frame events ──────────────────────────────────────────────────────────

    def record_frame(self, processing_ms: float) -> None:
        """Call after each frame is processed and response sent."""
        self._frame_latency.add(processing_ms)
        self._fps.mark()
        self._frames_total.inc()

    def record_inference(self, inference_ms: float) -> None:
        """Call after YOLO inference completes."""
        self._inference_latency.add(inference_ms)

    def record_confidence(self, confidence: float) -> None:
        """Call with per-detection confidence."""
        self._confidence_dist.record(confidence)

    # ── AI events ─────────────────────────────────────────────────────────────

    def record_override(self) -> None:
        self._overrides.inc()
        self._hazards_avoided.inc()   # override = hazard avoided

    def record_warning(self) -> None:
        self._warnings.inc()

    def record_cancelled_override(self) -> None:
        """User manually dismissed an override (FP signal)."""
        self._overrides_cancelled.inc()

    # ── Business events ───────────────────────────────────────────────────────

    def record_sos(self) -> None:
        self._sos_count.inc()

    def record_distance(self, metres: float) -> None:
        self._total_distance_m.inc(int(metres))

    def record_user_active(self, user_id: str) -> None:
        today = datetime.now(timezone.utc).date().isoformat()
        with self._dau_lock:
            if today != self._dau_date:
                self._dau_set.clear()
                self._dau_date = today
            self._dau_set.add(user_id)

    # ── API latency (call from middleware) ────────────────────────────────────

    def record_api_latency(self, path: str, ms: float) -> None:
        self._api_latency.record(path, ms)

    # ── Snapshot (for /admin/metrics endpoint) ────────────────────────────────

    def snapshot(self) -> dict:
        """Return the full metrics dashboard as a JSON-safe dict."""
        uptime_s = time.monotonic() - self._started_at

        frame_stats = self._frame_latency.stats()
        inf_stats   = self._inference_latency.stats()

        # Override FP rate
        total_overrides = self._overrides.get()
        total_cancelled = self._overrides_cancelled.get()
        fp_rate = round(total_cancelled / max(total_overrides, 1), 4)

        with self._dau_lock:
            dau = len(self._dau_set)

        return {
            "collected_at":  datetime.now(timezone.utc).isoformat(),
            "uptime_seconds": round(uptime_s, 0),
            "started_at":    self._started_iso,

            "performance": {
                "frame_processing_ms": frame_stats,
                "model_inference_ms":  inf_stats,
                "frames_per_second":   self._fps.fps(),
                "total_frames":        self._frames_total.get(),
                "ws_connections_active": self._ws_active.get(),
                "api_latency_ms":      self._api_latency.snapshot(),
                "target_p95_ms":       80,
                "p95_ok":              frame_stats.get("p95", 9999) <= 80,
            },

            "ai": {
                "total_overrides":        self._overrides.get(),
                "total_warnings":         self._warnings.get(),
                "overrides_cancelled_fp": total_cancelled,
                "false_positive_rate":    fp_rate,
                "confidence_distribution": self._confidence_dist.snapshot(),
                "model_inference_ms":     inf_stats,
            },

            "business": {
                "active_navigation_sessions": self._ws_active.get(),
                "daily_active_users":         dau,
                "sos_alerts_triggered":       self._sos_count.get(),
                "total_distance_km":          round(self._total_distance_m.get() / 1000, 2),
                "hazards_avoided":            self._hazards_avoided.get(),
            },
        }
