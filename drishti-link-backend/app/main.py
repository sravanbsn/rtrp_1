"""
Drishti-Link API — main application entry point.
Production-grade FastAPI app for AI-powered navigation
assistance for visually impaired users.
"""

from __future__ import annotations

try:
    import torch
    from ultralytics.nn.tasks import DetectionModel
    torch.serialization.add_safe_globals([DetectionModel])
except ImportError:
    pass

import time
import uuid
from contextlib import asynccontextmanager

import structlog
import uvicorn
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse

from core.config import settings
from core.exceptions import (
    DrshtiBaseException,
    drishti_exception_handler,
    validation_exception_handler,
    http_exception_handler,
    unhandled_exception_handler,
)
from core.logging_config import configure_logging
from core.middleware import register_middleware
from monitoring.health import router as health_router
from routers import analyze, navigation, sos, routes, adaptive, admin
from ws_routes.live_stream import router as ws_router

# ── Bootstrap structured logging ──────────────────────────────────
configure_logging()
log = structlog.get_logger(__name__)


# ── Lifespan (startup / shutdown) ────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage startup and graceful shutdown of heavy resources."""
    log.info("drishti.startup", version=settings.APP_VERSION, env=settings.APP_ENV)

    # Warm up AI models on first request (lazy) — or eagerly here
    from services.yolo_service import YOLOService
    from services.collision_scorer import CollisionScorer
    from services.adaptive_engine import AdaptiveEngine
    from services.mediapipe_service import MediaPipeService
    from services.moral_governor import MoralGovernor
    from services.firebase_admin_service import FirebaseAdminService
    from monitoring.metrics import MetricsCollector
    from ml.model_manager import ModelManager

    # Initialize Firebase
    FirebaseAdminService.initialize()
    app.state.firebase = FirebaseAdminService

    # Set up application state singletons
    app.state.metrics   = MetricsCollector()
    app.state.yolo      = YOLOService()
    app.state.mediapipe = MediaPipeService()
    app.state.scorer    = CollisionScorer()
    app.state.adaptive  = AdaptiveEngine()
    app.state.governor  = MoralGovernor()
    app.state.models    = ModelManager()

    await app.state.models.load_active_model(app.state.yolo)
    log.info("drishti.models_ready", model=app.state.models.active_version)

    yield  # ← application runs here

    # Shutdown
    log.info("drishti.shutdown")
    await app.state.models.unload()


# ── App factory ───────────────────────────────────────────────────
def create_app() -> FastAPI:
    app = FastAPI(
        title="Drishti-Link API",
        description=(
            "Production backend for Drishti-Link — an AI navigation system "
            "for visually impaired users. Provides real-time hazard detection, "
            "collision scoring, moral governance, and guardian alerts."
        ),
        version=settings.APP_VERSION,
        docs_url="/docs" if settings.APP_ENV != "production" else None,
        redoc_url="/redoc" if settings.APP_ENV != "production" else None,
        openapi_url="/openapi.json" if settings.APP_ENV != "production" else None,
        lifespan=lifespan,
    )

    # ── Middleware stack (order matters — outermost first) ─────────
    app.add_middleware(GZipMiddleware, minimum_size=1000)
    register_middleware(app)
    
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
        allow_headers=["Authorization", "Content-Type", "X-Requested-With"],
        expose_headers=["X-Request-ID", "X-Process-Time"],
    )

    # ── Exception handlers ────────────────────────────────────────
    app.add_exception_handler(DrshtiBaseException, drishti_exception_handler)
    app.add_exception_handler(422, validation_exception_handler)
    app.add_exception_handler(404, http_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)

    # ── Routers ───────────────────────────────────────────────────
    V1 = "/api/v1"
    app.include_router(health_router,           prefix="",      tags=["Health"])
    app.include_router(ws_router,               prefix="/ws",   tags=["WebSocket"])
    app.include_router(analyze.router,          prefix=V1,      tags=["Analysis"])
    app.include_router(navigation.router,       prefix=V1,      tags=["Navigation"])
    app.include_router(sos.router,              prefix=V1,      tags=["SOS"])
    app.include_router(routes.router,           prefix=V1,      tags=["Routes"])
    app.include_router(adaptive.router,         prefix=V1,      tags=["Adaptive AI"])
    app.include_router(admin.router,            prefix=V1,      tags=["Admin"])

    # ── Root endpoint ─────────────────────────────────────────────
    @app.get("/", tags=["Health"], summary="App info")
    async def root():
        return {
            "app": "Drishti-Link",
            "status": "running",
            "version": settings.APP_VERSION,
            "docs": "/docs",
        }

    return app


app = create_app()


if __name__ == "__main__":
    import os
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
