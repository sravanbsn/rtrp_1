"""
services/cache_service.py

Unified cache layer for Drishti-Link.
════════════════════════════════════
Provides a single CacheService interface that works with either:
  ● Redis (when REDIS_ENABLED=True and Redis is reachable)
  ● In-memory TTL dict (fallback — always works, local dev)

The app NEVER crashes because Redis is unavailable.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Optional

from core.config import settings

log = logging.getLogger(__name__)


# ── In-memory TTL store ───────────────────────────────────────────────────────

class _MemoryStore:
    """Simple thread-safe TTL key-value store. No external dependencies."""

    def __init__(self) -> None:
        self._data: dict[str, tuple[Any, float]] = {}   # key → (value, expiry_ts)

    def get(self, key: str) -> Optional[Any]:
        entry = self._data.get(key)
        if entry is None:
            return None
        value, expiry = entry
        if time.monotonic() > expiry:
            del self._data[key]
            return None
        return value

    def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        self._data[key] = (value, time.monotonic() + ttl_seconds)

    def delete(self, key: str) -> None:
        self._data.pop(key, None)

    def flush(self) -> None:
        self._data.clear()

    # Evict expired entries (call periodically if needed)
    def evict_expired(self) -> int:
        now = time.monotonic()
        expired = [k for k, (_, exp) in self._data.items() if now > exp]
        for k in expired:
            del self._data[k]
        return len(expired)


# ── Redis wrapper (lazy import — only used if REDIS_ENABLED=True) ────────────

class _RedisStore:
    """Thin async wrapper around redis-py."""

    def __init__(self, url: str) -> None:
        self._url = url
        self._client = None
        self._available = False

    async def connect(self) -> bool:
        try:
            import redis.asyncio as aioredis  # type: ignore
            self._client = aioredis.from_url(
                self._url,
                socket_connect_timeout=2,
                socket_timeout=2,
                decode_responses=True,
            )
            await self._client.ping()
            self._available = True
            log.info("✅ Redis connected: %s", self._url)
            return True
        except Exception as exc:
            log.warning(
                "⚠️  Redis unavailable — falling back to in-memory cache. "
                "Error: %s", exc
            )
            self._available = False
            return False

    async def get(self, key: str) -> Optional[Any]:
        if not self._available or not self._client:
            return None
        try:
            import json
            raw = await self._client.get(key)
            return json.loads(raw) if raw else None
        except Exception as exc:
            log.debug("Redis GET error for %s: %s", key, exc)
            return None

    async def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        if not self._available or not self._client:
            return
        try:
            import json
            await self._client.setex(key, ttl_seconds, json.dumps(value, default=str))
        except Exception as exc:
            log.debug("Redis SET error for %s: %s", key, exc)

    async def delete(self, key: str) -> None:
        if not self._available or not self._client:
            return
        try:
            await self._client.delete(key)
        except Exception as exc:
            log.debug("Redis DELETE error for %s: %s", key, exc)


# ── Public CacheService ───────────────────────────────────────────────────────

class CacheService:
    """
    Unified cache interface.

    Usage:
        cache = CacheService()
        await cache.initialize()          # call once at startup
        val = await cache.get("my_key")
        await cache.set("my_key", {"data": 1}, ttl_seconds=60)
        await cache.delete("my_key")

    Falls back to in-memory automatically if Redis is unavailable.
    """

    def __init__(self) -> None:
        self._memory = _MemoryStore()
        self._redis:  Optional[_RedisStore] = None
        self._use_redis = False
        self.backend: str = "memory"

    async def initialize(self) -> None:
        """
        Set up the cache backend.
        Called once at app startup in main.py lifespan.
        """
        if settings.REDIS_ENABLED:
            redis_store = _RedisStore(settings.REDIS_URL)
            ok = await redis_store.connect()
            if ok:
                self._redis = redis_store
                self._use_redis = True
                self.backend = "redis"
                return
            # Fall through to memory
        self.backend = "memory"
        log.info("CacheService using in-memory backend (REDIS_ENABLED=%s).", settings.REDIS_ENABLED)

    # ── Unified async interface ───────────────────────────────────────────────

    async def get(self, key: str) -> Optional[Any]:
        if self._use_redis and self._redis:
            val = await self._redis.get(key)
            if val is None:
                # Redis miss — check memory L1 (short-lived hot data)
                return self._memory.get(key)
            return val
        return self._memory.get(key)

    async def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        if self._use_redis and self._redis:
            await self._redis.set(key, value, ttl_seconds)
        # Always write to memory as L1 hot cache
        self._memory.set(key, value, min(ttl_seconds, 60))

    async def delete(self, key: str) -> None:
        self._memory.delete(key)
        if self._use_redis and self._redis:
            await self._redis.delete(key)

    def get_sync(self, key: str) -> Optional[Any]:
        """Synchronous get — always uses memory store (for non-async contexts)."""
        return self._memory.get(key)

    def set_sync(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        """Synchronous set — always uses memory store."""
        self._memory.set(key, value, ttl_seconds)

    @property
    def is_redis_active(self) -> bool:
        return self._use_redis and self._redis is not None and self._redis._available

    def status(self) -> dict:
        return {
            "backend": self.backend,
            "redis_active": self.is_redis_active,
            "memory_keys": len(self._memory._data),
        }


# ── Singleton ─────────────────────────────────────────────────────────────────
# Modules can import this directly; initialize() is called from app lifespan.
cache = CacheService()
