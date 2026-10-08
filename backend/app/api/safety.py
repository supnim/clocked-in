"""Shared helpers for blocks and friendship-change notifications.

Used by the REST routers and intended for the WebSocket layer too, e.g.:

    from app.api.safety import is_blocked
    if await is_blocked(conn, sender_id, target_id): ...  # drop nudge
"""

import logging
from uuid import UUID

import asyncpg

from app.redis_client import get_redis

logger = logging.getLogger(__name__)


async def is_blocked(conn: asyncpg.Connection, a: str | UUID, b: str | UUID) -> bool:
    """True if either user has blocked the other."""
    return bool(
        await conn.fetchval(
            """
            SELECT EXISTS (
                SELECT 1 FROM blocks
                WHERE (blocker_id = $1::uuid AND blocked_id = $2::uuid)
                   OR (blocker_id = $2::uuid AND blocked_id = $1::uuid)
            )
            """,
            str(a),
            str(b),
        )
    )


async def notify_friends_changed(*user_ids: str | UUID) -> None:
    """Invalidate ``friends:{id}`` caches and PUBLISH ``friends_changed:{id}``.

    Called after any friendship change (accept, remove, block, account deletion)
    so live WebSocket sessions re-subscribe to the right set of friends.
    Best-effort: a Redis failure is logged, not raised, because the DB change
    has already been committed.
    """
    ids = {str(u) for u in user_ids}
    if not ids:
        return
    try:
        redis = get_redis()
        pipe = redis.pipeline(transaction=False)
        for uid in ids:
            pipe.delete(f"friends:{uid}")
            pipe.publish(f"friends_changed:{uid}", "1")
        await pipe.execute()
    except Exception:
        logger.warning("Failed to publish friends_changed for %s", ids, exc_info=True)
