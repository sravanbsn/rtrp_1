"""User profile CRUD service."""
from __future__ import annotations
import structlog
from core.exceptions import ResourceNotFoundError
from models.user_profile import UserProfile, UserProfileCreate

log = structlog.get_logger(__name__)
_profiles: dict[str, UserProfile] = {}


class UserProfileService:
    async def create(self, req: UserProfileCreate) -> UserProfile:
        profile = UserProfile(**req.model_dump())
        _profiles[profile.user_id] = profile
        log.info("profile.created", user_id=profile.user_id)
        return profile

    async def get(self, user_id: str) -> UserProfile:
        p = _profiles.get(user_id)
        if not p:
            raise ResourceNotFoundError(message=f"User {user_id!r} not found.")
        return p

    async def update_stats(self, user_id: str, *, sessions: int = 0, distance_m: float = 0, hazards: int = 0, overrides: int = 0) -> UserProfile:
        p = await self.get(user_id)
        p.total_sessions        += sessions
        p.total_distance_m      += distance_m
        p.total_hazards_avoided += hazards
        p.total_overrides       += overrides
        return p
