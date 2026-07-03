"""Redis client using redis.asyncio."""

import redis.asyncio as redis
from redis.asyncio import Redis

from app.config import config

# Global redis instance
_redis: Redis | None = None


async def init_redis() -> None:
    """Initialize the Redis connection."""
    global _redis
    _redis = redis.from_url(
        config.REDIS_URL,
        encoding="utf-8",
        decode_responses=True,
    )


async def close_redis() -> None:
    """Close the Redis connection."""
    global _redis
    if _redis:
        await _redis.close()
        _redis = None


def get_redis() -> Redis:
    """Get the global Redis instance."""
    if _redis is None:
        raise RuntimeError("Redis not initialized")
    return _redis
