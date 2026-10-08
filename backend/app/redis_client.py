"""Redis client using redis.asyncio."""

import redis.asyncio as redis
from redis.asyncio import Redis

from app.config import config

# Global redis instance
_redis: Redis | None = None


async def init_redis() -> Redis:
    """Initialize the shared Redis connection pool."""
    global _redis
    if _redis is None:
        _redis = redis.from_url(
            config.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
            health_check_interval=30,
            socket_keepalive=True,
        )
    return _redis


async def close_redis() -> None:
    """Close the Redis connection pool."""
    global _redis
    if _redis:
        await _redis.aclose()
        _redis = None


def get_redis() -> Redis:
    """Get the global Redis instance."""
    if _redis is None:
        raise RuntimeError("Redis not initialized")
    return _redis
