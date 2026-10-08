"""Presence state in Redis.

Storage layout (all keys owned by this module):

- ``presence:{uid}``      hash, TTL ``PRESENCE_TTL``. Present only while the
  user is online. Every field is a plain string; ``_decode_presence`` maps it
  back to strict types (``online`` bool, ``updated_at`` int ms, everything else
  str or None). Fields are never JSON-decoded, so an app named "123" stays a str.
- ``presence:last_seen``  sorted set uid -> last heartbeat/update (unix ms).
  Used by the sweeper to publish ``offline`` for users whose presence key
  expired without an explicit disconnect (crash, network loss).
- ``channel:presence:{uid}``  pub/sub channel carrying FriendPresence JSON.
- ``friends:{uid}``       set cache of friend ids (invalidated by the REST API).
"""

import asyncio
import json
import logging
import time
from typing import Any, Literal
from uuid import UUID

import asyncpg
import redis.asyncio as redis
from pydantic import BaseModel, ConfigDict, Field

from app.redis_client import get_redis

logger = logging.getLogger(__name__)

PRESENCE_TTL = 45  # seconds
LAST_SEEN_KEY = "presence:last_seen"

# Atomically decide whether a last_seen entry is really stale: the presence key
# must be gone (TTL is authoritative) and the score must still be old. Only the
# caller whose ZREM succeeds publishes, so multiple sweepers never double-post.
_SWEEP_ONE_LUA = """
if redis.call('EXISTS', KEYS[2]) == 1 then return 0 end
local score = redis.call('ZSCORE', KEYS[1], ARGV[1])
if not score then return 0 end
if tonumber(score) > tonumber(ARGV[2]) then return 0 end
return redis.call('ZREM', KEYS[1], ARGV[1])
"""


def now_ms() -> int:
    return int(time.time() * 1000)


class PresenceIn(BaseModel):
    """Client-supplied presence payload (``data`` of a ``presence_update``)."""

    model_config = ConfigDict(extra="forbid", strict=True)

    status: Literal["online", "away", "ghost"]
    app_name: str | None = Field(default=None, max_length=100)
    bundle_id: str | None = Field(default=None, max_length=255)
    app_icon: str | None = Field(default=None, max_length=24000)
    # Accepted for forward compatibility; v1 never shares them with friends.
    window_title: str | None = Field(default=None, max_length=200)
    browser_domain: str | None = Field(default=None, max_length=200)


_APP_FIELDS = ("app_name", "bundle_id", "app_icon")


def offline_presence(user_id: str, updated_at: int | None = None) -> dict[str, Any]:
    return {
        "user_id": user_id,
        "online": False,
        "status": "offline",
        "app_name": None,
        "bundle_id": None,
        "app_icon": None,
        "window_title": None,
        "browser_domain": None,
        "updated_at": updated_at if updated_at is not None else now_ms(),
    }


def _decode_presence(user_id: str, data: dict[str, str]) -> dict[str, Any]:
    """Map a stored hash to a strictly typed FriendPresence dict."""
    try:
        updated_at = int(data.get("updated_at", "0"))
    except ValueError:
        updated_at = 0
    status = data.get("status")
    if status not in ("online", "away", "ghost"):
        status = "online"
    return {
        "user_id": user_id,
        "online": data.get("online") == "1",
        "status": status,
        "app_name": data.get("app_name") or None,
        "bundle_id": data.get("bundle_id") or None,
        "app_icon": data.get("app_icon") or None,
        "window_title": None,
        "browser_domain": None,
        "updated_at": updated_at,
    }


class PresenceManager:
    """Manages user presence state via Redis."""

    PRESENCE_TTL = PRESENCE_TTL
    FRIEND_CACHE_TTL = 300  # 5 minutes

    def __init__(self) -> None:
        self._db_pool: asyncpg.Pool | None = None

    def set_db_pool(self, pool: asyncpg.Pool | None) -> None:
        """Set database pool for friend lookups."""
        self._db_pool = pool

    def _redis(self) -> redis.Redis:
        return get_redis()

    @staticmethod
    def presence_key(user_id: str) -> str:
        return f"presence:{user_id}"

    @staticmethod
    def presence_channel(user_id: str) -> str:
        return f"channel:presence:{user_id}"

    @staticmethod
    def friends_changed_channel(user_id: str) -> str:
        return f"friends_changed:{user_id}"

    @staticmethod
    def account_deleted_channel(user_id: str) -> str:
        return f"account_deleted:{user_id}"

    # ------------------------------------------------------------------ writes

    async def update_presence(self, user_id: str, data: PresenceIn) -> dict[str, Any]:
        """Replace the user's presence hash and publish it to friends."""
        r = self._redis()
        key = self.presence_key(user_id)
        ts = now_ms()

        fields: dict[str, str] = {"status": data.status}
        if data.status != "ghost":
            for name in _APP_FIELDS:
                value = getattr(data, name)
                if value:
                    fields[name] = value
        # Server-owned fields last so the client can never override them.
        fields["user_id"] = user_id
        fields["online"] = "1"
        fields["updated_at"] = str(ts)

        pipe = r.pipeline(transaction=True)
        pipe.delete(key)
        pipe.hset(key, mapping=fields)
        pipe.expire(key, self.PRESENCE_TTL)
        pipe.zadd(LAST_SEEN_KEY, {user_id: ts})
        await pipe.execute()

        presence = _decode_presence(user_id, fields)
        await r.publish(self.presence_channel(user_id), json.dumps(presence))
        return presence

    async def heartbeat(self, user_id: str) -> bool:
        """Refresh TTL on the user's presence key if it exists."""
        r = self._redis()
        refreshed = await r.expire(self.presence_key(user_id), self.PRESENCE_TTL)
        if refreshed:
            await r.zadd(LAST_SEEN_KEY, {user_id: now_ms()})
        return bool(refreshed)

    async def set_offline(self, user_id: str) -> None:
        """Delete the user's presence and notify friends they went offline."""
        r = self._redis()
        pipe = r.pipeline(transaction=True)
        pipe.delete(self.presence_key(user_id))
        pipe.zrem(LAST_SEEN_KEY, user_id)
        await pipe.execute()
        await r.publish(
            self.presence_channel(user_id), json.dumps(offline_presence(user_id))
        )

    async def sweep_expired(self, max_age_ms: int | None = None) -> list[str]:
        """Publish offline for users whose presence key expired silently."""
        r = self._redis()
        cutoff = now_ms() - (
            max_age_ms if max_age_ms is not None else self.PRESENCE_TTL * 1000
        )
        stale = await r.zrangebyscore(LAST_SEEN_KEY, "-inf", cutoff)
        swept: list[str] = []
        for user_id in stale:
            removed = await r.eval(
                _SWEEP_ONE_LUA,
                2,
                LAST_SEEN_KEY,
                self.presence_key(user_id),
                user_id,
                cutoff,
            )
            if removed:
                await r.publish(
                    self.presence_channel(user_id),
                    json.dumps(offline_presence(user_id)),
                )
                swept.append(user_id)
        return swept

    async def run_sweeper(self, interval: float = 30.0) -> None:
        """Background loop for ``sweep_expired`` (started from app lifespan)."""
        while True:
            try:
                swept = await self.sweep_expired()
                if swept:
                    logger.info(
                        "Presence sweeper marked %d user(s) offline", len(swept)
                    )
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Presence sweeper iteration failed")
            await asyncio.sleep(interval)

    # ------------------------------------------------------------------- reads

    async def get_presence(self, user_id: str) -> dict[str, Any] | None:
        """Get strictly typed presence for a user, or None when offline."""
        data = await self._redis().hgetall(self.presence_key(user_id))
        if not data:
            return None
        return _decode_presence(user_id, data)

    async def get_presences(self, user_ids: list[str]) -> list[dict[str, Any]]:
        """Presence for the given users that are currently online."""
        if not user_ids:
            return []
        pipe = self._redis().pipeline(transaction=False)
        for uid in user_ids:
            pipe.hgetall(self.presence_key(uid))
        results = await pipe.execute()
        return [_decode_presence(uid, d) for uid, d in zip(user_ids, results) if d]

    async def get_friends_presence(self, user_id: str) -> list[dict[str, Any]]:
        """Get presence data for all online friends of a user."""
        return await self.get_presences(await self.get_friend_ids(user_id))

    async def get_friend_ids(
        self, user_id: str, *, bypass_cache: bool = False
    ) -> list[str]:
        """Get friend IDs from cache or database."""
        r = self._redis()
        cache_key = f"friends:{user_id}"

        if not bypass_cache:
            cached = await r.smembers(cache_key)
            if cached:
                return list(cached)

        if self._db_pool is None:
            return []
        try:
            user_uuid = UUID(user_id)
        except ValueError:
            return []

        async with self._db_pool.acquire() as conn:
            rows = await conn.fetch("SELECT * FROM get_friend_ids($1)", user_uuid)
        friend_ids = [str(row[0]) for row in rows]

        pipe = r.pipeline(transaction=True)
        pipe.delete(cache_key)
        if friend_ids:
            pipe.sadd(cache_key, *friend_ids)
            pipe.expire(cache_key, self.FRIEND_CACHE_TTL)
        await pipe.execute()
        return friend_ids

    # Backwards-compatible alias.
    _get_friend_ids = get_friend_ids

    async def are_friends(self, user_a: str, user_b: str) -> bool:
        """Check friendship directly in Postgres (authoritative, uncached)."""
        if self._db_pool is None:
            return False
        try:
            a, b = UUID(user_a), UUID(user_b)
        except ValueError:
            return False
        if a == b:
            return False
        async with self._db_pool.acquire() as conn:
            row = await conn.fetchval(
                "SELECT 1 FROM friendships "
                "WHERE user_id_1 = LEAST($1::uuid, $2::uuid) "
                "AND user_id_2 = GREATEST($1::uuid, $2::uuid)",
                a,
                b,
            )
        return row is not None

    async def close(self) -> None:
        """Nothing to tear down: the Redis pool is owned by app.redis_client."""


# Singleton instance
presence_manager = PresenceManager()
