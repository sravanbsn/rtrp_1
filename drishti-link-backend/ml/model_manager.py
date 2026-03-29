"""
ml/model_manager.py

Zero-Downtime Model Version Manager — Drishti-Link
════════════════════════════════════════════════════

Maintains a registry of YOLOv8 model versions.
Supports hot-swap: load new → switch → keep old as fallback.
Automatic rollback if new model error rate exceeds 5% in the first N frames.

Version metadata stored in: models/registry.json
  {
    "versions": {
      "v1.0.0": { "path": "...", "accuracy": 0.891, ... },
      ...
    },
    "active": "v1.0.0",
    "previous": null
  }

Endpoints (wired in routers/admin.py):
  GET  /api/v1/admin/models              → list_versions()
  POST /api/v1/admin/models/activate/{v} → activate_version(v)
  POST /api/v1/admin/models/rollback      → rollback()
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import structlog

log = structlog.get_logger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
REGISTRY_PATH       = Path("models/registry.json")
MODELS_DIR          = Path("models")
ROLLBACK_ERROR_RATE = 0.05       # auto-rollback if new model errors > 5%
ROLLBACK_WINDOW     = 200        # frames to observe before declaring new model safe


# ═════════════════════════════════════════════════════════════════════════════
# Data classes
# ═════════════════════════════════════════════════════════════════════════════

@dataclass
class ModelVersion:
    version:         str
    path:            str
    accuracy_map50:  float        # mAP@50 on validation set
    accuracy_map95:  float        # mAP@50-95
    training_date:   str
    indian_classes:  list[str]    # custom classes included (pothole, drain, etc.)
    notes:           str    = ""
    file_size_mb:    float  = 0.0
    is_active:       bool   = False
    added_at:        str    = ""

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class ActivationResult:
    success:         bool
    version:        str
    previous:       Optional[str]
    message:        str
    activated_at:   str = ""


@dataclass
class _ErrorTracker:
    """Tracks error rate during new-model observation window."""
    total: int = 0
    errors: int = 0

    @property
    def rate(self) -> float:
        return self.errors / max(self.total, 1)

    def record(self, is_error: bool) -> None:
        self.total += 1
        if is_error:
            self.errors += 1

    @property
    def window_complete(self) -> bool:
        return self.total >= ROLLBACK_WINDOW


# ═════════════════════════════════════════════════════════════════════════════
# ModelManager
# ═════════════════════════════════════════════════════════════════════════════

class ModelManager:
    """
    Zero-downtime model version manager.

    Usage:
        mgr = ModelManager()
        await mgr.load_registry()
        app.state.model_manager = mgr

        # Hot-swap a new version:
        result = await mgr.activate_version("v1.2.0", yolo_service)
    """

    def __init__(self) -> None:
        self._versions:  dict[str, ModelVersion] = {}
        self._active:    Optional[str]            = None
        self._previous:  Optional[str]            = None
        self._lock       = asyncio.Lock()
        self._err_tracker: Optional[_ErrorTracker] = None
        self._observing  = False

    # ── Registry persistence ──────────────────────────────────────────────────

    async def load_registry(self) -> None:
        """Load registry from disk. Creates default registry if absent."""
        async with self._lock:
            if REGISTRY_PATH.exists():
                try:
                    data = json.loads(REGISTRY_PATH.read_text())
                    self._active   = data.get("active")
                    self._previous = data.get("previous")
                    for v, meta in data.get("versions", {}).items():
                        self._versions[v] = ModelVersion(**meta)
                    log.info("model_mgr.registry_loaded",
                             versions=len(self._versions), active=self._active)
                    return
                except Exception as exc:
                    log.warning("model_mgr.registry_load_failed", exc=str(exc))

            # No registry — build a minimal default entry
            self._build_default_registry()

    @property
    def active_version(self) -> Optional[str]:
        return self._active

    async def load_active_model(self, yolo_service) -> None:
        """Load the active YOLOv8 model upon startup."""
        await self.load_registry()
        active_version = await self.get_active()
        if active_version and yolo_service:
            log.info("model_mgr.loading_active_model", version=active_version.version, path=active_version.path)
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, yolo_service.load_sync, active_version.path)

    async def unload(self) -> None:
        """Clean up on shutdown."""
        log.info("model_mgr.unloaded")

    def _build_default_registry(self) -> None:
        default_path = str(MODELS_DIR / "yolov8n.pt")
        v = ModelVersion(
            version="v1.0.0",
            path=default_path,
            accuracy_map50=0.652,
            accuracy_map95=0.421,
            training_date="2025-01-01",
            indian_classes=["pothole", "open_drain", "speed_bump",
                            "construction_barrier", "loose_wire", "wet_floor",
                            "auto_rickshaw", "goat"],
            notes="Initial COCO + Indian street classes baseline",
            file_size_mb=6.2,
            is_active=True,
            added_at=datetime.now(timezone.utc).isoformat(),
        )
        self._versions["v1.0.0"] = v
        self._active = "v1.0.0"
        self._save_registry_sync()
        log.info("model_mgr.default_registry_created")

    def _save_registry_sync(self) -> None:
        REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "active":   self._active,
            "previous": self._previous,
            "versions": {v: m.to_dict() for v, m in self._versions.items()},
        }
        REGISTRY_PATH.write_text(json.dumps(data, indent=2))

    # ── Public API ────────────────────────────────────────────────────────────

    async def list_versions(self) -> list[dict]:
        """Return all registered model versions with active flag."""
        async with self._lock:
            return [
                {**m.to_dict(), "is_active": (v == self._active)}
                for v, m in sorted(self._versions.items())
            ]

    async def get_active(self) -> Optional[ModelVersion]:
        async with self._lock:
            if self._active and self._active in self._versions:
                return self._versions[self._active]
            return None

    async def register_version(self, meta: dict) -> ModelVersion:
        """
        Register a new model version in the registry without activating it.
        Call this after uploading a new .pt file.
        """
        async with self._lock:
            version = meta["version"]
            if version in self._versions:
                raise ValueError(f"Version {version} already exists")

            mv = ModelVersion(
                version=version,
                path=meta.get("path", str(MODELS_DIR / f"yolov8_{version}.pt")),
                accuracy_map50=float(meta.get("accuracy_map50", 0.0)),
                accuracy_map95=float(meta.get("accuracy_map95", 0.0)),
                training_date=meta.get("training_date", datetime.now(timezone.utc).date().isoformat()),
                indian_classes=meta.get("indian_classes", []),
                notes=meta.get("notes", ""),
                file_size_mb=float(meta.get("file_size_mb", 0.0)),
                added_at=datetime.now(timezone.utc).isoformat(),
            )
            self._versions[version] = mv
            self._save_registry_sync()
            log.info("model_mgr.version_registered", version=version)
            return mv

    async def activate_version(
        self,
        version:      str,
        yolo_service,           # YOLOService instance
    ) -> ActivationResult:
        """
        Hot-swap to a new model version.

        Process:
          1. Validate version exists and .pt file is present
          2. Load new model in background (non-blocking)
          3. Atomically swap into YOLOService
          4. Begin observation window for auto-rollback
          5. Old model kept as fallback in case rollback is needed
        """
        async with self._lock:
            if version not in self._versions:
                return ActivationResult(
                    success=False, version=version, previous=self._active,
                    message=f"Version {version} not in registry"
                )

            mv = self._versions[version]
            if not Path(mv.path).exists():
                return ActivationResult(
                    success=False, version=version, previous=self._active,
                    message=f"Model file not found: {mv.path}"
                )

            if version == self._active:
                return ActivationResult(
                    success=True, version=version, previous=self._active,
                    message="Already active", activated_at=datetime.now(timezone.utc).isoformat()
                )

        log.info("model_mgr.activation_started", new=version, current=self._active)

        # Load in background thread so event loop stays responsive
        try:
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, yolo_service.load_sync, mv.path)
        except Exception as exc:
            log.error("model_mgr.load_failed", version=version, exc=str(exc))
            return ActivationResult(
                success=False, version=version, previous=self._active,
                message=f"Model load failed: {exc}"
            )

        async with self._lock:
            # Atomically promote new version
            self._previous = self._active
            self._active   = version

            # Mark active flags
            for v, m in self._versions.items():
                m.is_active = (v == version)

            # Begin observation window
            self._err_tracker = _ErrorTracker()
            self._observing   = True

            self._save_registry_sync()

        log.info("model_mgr.activated", new=version, previous=self._previous)
        return ActivationResult(
            success=True,
            version=version,
            previous=self._previous,
            message=f"Model {version} activated. Observing for {ROLLBACK_WINDOW} frames.",
            activated_at=datetime.now(timezone.utc).isoformat(),
        )

    async def rollback(self, yolo_service) -> ActivationResult:
        """
        Roll back to the previous model version.
        Can be called manually (admin endpoint) or automatically.
        """
        async with self._lock:
            prev = self._previous
            if not prev or prev not in self._versions:
                return ActivationResult(
                    success=False, version="",
                    previous=self._active,
                    message="No previous version available for rollback"
                )
            rollback_target = prev

        log.warning("model_mgr.rolling_back", target=rollback_target, current=self._active)
        return await self.activate_version(rollback_target, yolo_service)

    async def record_frame_outcome(self, is_error: bool, yolo_service) -> None:
        """
        Called after each frame inference during the observation window.
        Triggers auto-rollback if error rate breaches threshold.
        """
        if not self._observing:
            return

        async with self._lock:
            if self._err_tracker is None:
                return
            self._err_tracker.record(is_error)
            rate    = self._err_tracker.rate
            window  = self._err_tracker.window_complete

        if not window:
            return   # still in observation

        # Window complete — evaluate
        async with self._lock:
            self._observing = False

        if rate > ROLLBACK_ERROR_RATE:
            log.error(
                "model_mgr.auto_rollback_triggered",
                error_rate=round(rate, 4),
                threshold=ROLLBACK_ERROR_RATE,
            )
            await self.rollback(yolo_service)
        else:
            log.info(
                "model_mgr.observation_passed",
                error_rate=round(rate, 4),
                version=self._active,
            )

    async def status(self) -> dict:
        async with self._lock:
            active_meta = self._versions.get(self._active)
            return {
                "active_version":  self._active,
                "previous_version": self._previous,
                "total_versions":  len(self._versions),
                "observing":       self._observing,
                "observation_frames": (
                    self._err_tracker.total if self._err_tracker else 0
                ),
                "observation_error_rate": (
                    round(self._err_tracker.rate, 4) if self._err_tracker else None
                ),
                "active_accuracy_map50": (
                    active_meta.accuracy_map50 if active_meta else None
                ),
                "active_indian_classes": (
                    active_meta.indian_classes if active_meta else []
                ),
            }
