"""Saved route management endpoints."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

import structlog
from fastapi import APIRouter, status
from pydantic import BaseModel, Field

from core.exceptions import ResourceNotFoundError
from models.session import GeoPoint

log = structlog.get_logger(__name__)
router = APIRouter(prefix="/routes")

_routes: dict[str, dict] = {}


class RouteWaypoint(BaseModel):
    point:       GeoPoint
    label:       Optional[str] = None
    known_hazard: Optional[str] = None


class SavedRoute(BaseModel):
    route_id:        str
    user_id:         str
    name:            str
    description:     Optional[str] = None
    origin:          GeoPoint
    destination:     GeoPoint
    waypoints:       list[RouteWaypoint] = Field(default_factory=list)
    distance_m:      float = 0.0
    est_duration_min: float = 0.0
    safety_score:    float = Field(5.0, ge=0.0, le=5.0)
    known_hazards:   int   = 0
    times_navigated: int   = 0
    last_used_at:    Optional[datetime] = None
    is_favorite:     bool  = False
    created_at:      datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class RouteCreateRequest(BaseModel):
    user_id:     str
    name:        str
    description: Optional[str] = None
    origin:      GeoPoint
    destination: GeoPoint
    waypoints:   list[RouteWaypoint] = Field(default_factory=list)


class RouteNavigateRequest(BaseModel):
    session_id: str


@router.post(
    "/",
    response_model=SavedRoute,
    status_code=status.HTTP_201_CREATED,
    summary="Save a new route",
)
async def create_route(body: RouteCreateRequest) -> SavedRoute:
    import shortuuid
    route = SavedRoute(
        route_id=shortuuid.uuid()[:8],
        user_id=body.user_id,
        name=body.name,
        description=body.description,
        origin=body.origin,
        destination=body.destination,
        waypoints=body.waypoints,
    )
    _routes[route.route_id] = route.model_dump()
    log.info("routes.created", route_id=route.route_id, user_id=body.user_id)
    return route


@router.get(
    "/",
    response_model=list[SavedRoute],
    summary="List routes for a user",
)
async def list_routes(
    user_id: str,
    favorites_only: bool = False,
    limit: int = 20,
    offset: int = 0,
) -> list[SavedRoute]:
    user_routes = [
        SavedRoute(**r) for r in _routes.values()
        if r["user_id"] == user_id
    ]
    if favorites_only:
        user_routes = [r for r in user_routes if r.is_favorite]
    return user_routes[offset : offset + limit]


@router.get(
    "/{route_id}",
    response_model=SavedRoute,
    summary="Get route details",
)
async def get_route(route_id: str) -> SavedRoute:
    data = _routes.get(route_id)
    if not data:
        raise ResourceNotFoundError(message=f"Route {route_id!r} not found.")
    return SavedRoute(**data)


@router.patch(
    "/{route_id}/favorite",
    response_model=SavedRoute,
    summary="Toggle favorite",
)
async def toggle_favorite(route_id: str) -> SavedRoute:
    data = _routes.get(route_id)
    if not data:
        raise ResourceNotFoundError(message=f"Route {route_id!r} not found.")
    data["is_favorite"] = not data["is_favorite"]
    return SavedRoute(**data)


@router.delete(
    "/{route_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a saved route",
)
async def delete_route(route_id: str) -> None:
    if route_id not in _routes:
        raise ResourceNotFoundError(message=f"Route {route_id!r} not found.")
    del _routes[route_id]
    log.info("routes.deleted", route_id=route_id)
