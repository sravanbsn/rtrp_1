"""
Custom exception hierarchy and FastAPI exception handlers.
All errors returned as structured JSON with machine-readable codes.
"""

from __future__ import annotations

import traceback
from typing import Any

import structlog
from fastapi import Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import ORJSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = structlog.get_logger(__name__)


# ════════════════════════════════════════════════════════════════
# Exception hierarchy
# ════════════════════════════════════════════════════════════════

class DrshtiBaseException(Exception):
    """Base class for all Drishti-Link domain errors."""

    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR
    error_code: str = "INTERNAL_ERROR"
    message: str = "An unexpected error occurred."

    def __init__(
        self,
        message: str | None = None,
        details: Any | None = None,
        *,
        user_id: str | None = None,
    ) -> None:
        self.message  = message or self.__class__.message
        self.details  = details
        self.user_id  = user_id
        super().__init__(self.message)

    def to_dict(self) -> dict:
        payload: dict = {
            "error": {
                "code": self.error_code,
                "message": self.message,
            }
        }
        if self.details:
            payload["error"]["details"] = self.details
        return payload


# ── Authentication & Authorization ───────────────────────────────
class AuthenticationError(DrshtiBaseException):
    status_code = status.HTTP_401_UNAUTHORIZED
    error_code  = "AUTHENTICATION_FAILED"
    message     = "Authentication credentials are missing or invalid."


class TokenExpiredError(AuthenticationError):
    error_code = "TOKEN_EXPIRED"
    message    = "Your session has expired. Please log in again."


class PermissionDeniedError(DrshtiBaseException):
    status_code = status.HTTP_403_FORBIDDEN
    error_code  = "PERMISSION_DENIED"
    message     = "You do not have permission to perform this action."


# ── Resource Errors ───────────────────────────────────────────────
class ResourceNotFoundError(DrshtiBaseException):
    status_code = status.HTTP_404_NOT_FOUND
    error_code  = "RESOURCE_NOT_FOUND"
    message     = "The requested resource was not found."


class ResourceConflictError(DrshtiBaseException):
    status_code = status.HTTP_409_CONFLICT
    error_code  = "RESOURCE_CONFLICT"
    message     = "A resource conflict occurred."


# ── AI / Model Errors ────────────────────────────────────────────
class ModelNotLoadedError(DrshtiBaseException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    error_code  = "MODEL_NOT_LOADED"
    message     = "AI model is not ready. Retrying in a moment."


class FrameProcessingError(DrshtiBaseException):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code  = "FRAME_PROCESSING_FAILED"
    message     = "Failed to process the provided frame."


class InvalidFrameError(DrshtiBaseException):
    status_code = status.HTTP_400_BAD_REQUEST
    error_code  = "INVALID_FRAME"
    message     = "Frame data is malformed or unsupported."


# ── Navigation Errors ────────────────────────────────────────────
class SessionNotFoundError(ResourceNotFoundError):
    error_code = "SESSION_NOT_FOUND"
    message    = "Navigation session not found."


class SessionAlreadyActiveError(ResourceConflictError):
    error_code = "SESSION_ALREADY_ACTIVE"
    message    = "A navigation session is already active for this user."


# ── SOS Errors ────────────────────────────────────────────────────
class GuardianNotConfiguredError(DrshtiBaseException):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code  = "GUARDIAN_NOT_CONFIGURED"
    message     = "No guardian is configured for this user."


class NotificationDeliveryError(DrshtiBaseException):
    status_code = status.HTTP_502_BAD_GATEWAY
    error_code  = "NOTIFICATION_DELIVERY_FAILED"
    message     = "Failed to deliver notification to guardian."


# ── Rate Limiting ────────────────────────────────────────────────
class RateLimitExceededError(DrshtiBaseException):
    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    error_code  = "RATE_LIMIT_EXCEEDED"
    message     = "Too many requests. Please slow down."


# ════════════════════════════════════════════════════════════════
# Exception handlers (registered in main.py)
# ════════════════════════════════════════════════════════════════

async def drishti_exception_handler(
    request: Request, exc: DrshtiBaseException
) -> ORJSONResponse:
    log.warning(
        "drishti.exception",
        code=exc.error_code,
        message=exc.message,
        path=request.url.path,
        user_id=getattr(exc, "user_id", None),
    )
    return ORJSONResponse(
        status_code=exc.status_code,
        content=exc.to_dict(),
    )


async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> ORJSONResponse:
    errors = [
        {
            "field": ".".join(str(loc) for loc in err["loc"]),
            "message": err["msg"],
            "type": err["type"],
        }
        for err in exc.errors()
    ]
    log.info("drishti.validation_error", path=request.url.path, errors=errors)
    return ORJSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": "Request validation failed.",
                "details": errors,
            }
        },
    )


async def http_exception_handler(
    request: Request, exc: StarletteHTTPException
) -> ORJSONResponse:
    return ORJSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": f"HTTP_{exc.status_code}",
                "message": exc.detail,
            }
        },
    )


async def unhandled_exception_handler(
    request: Request, exc: Exception
) -> ORJSONResponse:
    log.error(
        "drishti.unhandled_exception",
        path=request.url.path,
        exc_type=type(exc).__name__,
        exc=str(exc),
        traceback=traceback.format_exc(),
    )
    return ORJSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "An internal error occurred. Our team has been notified.",
            }
        },
    )
