"""Database connection pool using asyncpg."""

import json
from typing import AsyncGenerator

import asyncpg
from asyncpg import Pool

from app.config import config

# Global connection pool
_pool: Pool | None = None


async def _init_connection(conn: asyncpg.Connection) -> None:
    """Register codecs so jsonb columns decode to dicts instead of raw strings."""
    await conn.set_type_codec(
        "jsonb",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
    )


async def init_db() -> Pool:
    """Initialize the database connection pool."""
    global _pool
    _pool = await asyncpg.create_pool(
        config.DATABASE_URL,
        min_size=5,
        max_size=20,
        command_timeout=60,
        init=_init_connection,
    )
    return _pool


def get_pool() -> Pool | None:
    """Get the database connection pool."""
    return _pool


async def close_db() -> None:
    """Close the database connection pool."""
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    """Dependency that provides a database connection from the pool."""
    if _pool is None:
        raise RuntimeError("Database pool not initialized")
    async with _pool.acquire() as connection:
        yield connection
