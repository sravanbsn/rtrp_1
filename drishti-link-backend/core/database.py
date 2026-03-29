"""
Database connection management.
- Async SQLAlchemy engine + session factory
- Redis connection pool
- Dependency-injectable session getter
"""

from __future__ import annotations

from typing import AsyncGenerator

import structlog
from redis.asyncio import ConnectionPool, Redis
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from core.config import settings

log = structlog.get_logger(__name__)


# ════════════════════════════════════════════════════════════════
# SQLAlchemy async engine
# ════════════════════════════════════════════════════════════════

engine: AsyncEngine = create_async_engine(
    settings.DATABASE_URL,
    pool_size=settings.DATABASE_POOL_SIZE,
    max_overflow=settings.DATABASE_MAX_OVERFLOW,
    pool_timeout=settings.DATABASE_POOL_TIMEOUT,
    pool_pre_ping=True,          # verify connections before use
    echo=settings.DATABASE_ECHO,
    future=True,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """Declarative base for all ORM models."""
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency: yields an async DB session, auto-commits or rolls back."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


# ════════════════════════════════════════════════════════════════
# Redis connection pool
# ════════════════════════════════════════════════════════════════

_redis_pool: ConnectionPool | None = None


def get_redis_pool() -> ConnectionPool:
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = ConnectionPool.from_url(
            settings.REDIS_URL,
            max_connections=20,
            decode_responses=True,
        )
    return _redis_pool


async def get_redis() -> AsyncGenerator[Redis, None]:
    """FastAPI dependency: yields an async Redis client."""
    pool = get_redis_pool()
    client = Redis(connection_pool=pool)
    try:
        yield client
    finally:
        await client.aclose()


# ════════════════════════════════════════════════════════════════
# Database lifecycle helpers
# ════════════════════════════════════════════════════════════════

async def create_all_tables() -> None:
    """Create all tables (dev only — use Alembic in production)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    log.info("db.tables_created")


async def dispose_engine() -> None:
    """Gracefully close all DB connections."""
    await engine.dispose()
    log.info("db.engine_disposed")
