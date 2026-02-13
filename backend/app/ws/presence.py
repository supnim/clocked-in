import asyncio
import json
from typing import Any
from uuid import UUID

import asyncpg
import redis.asyncio as redis
from fastapi import WebSocket

from app.config import config as settings


class PresenceManager:
    """Manages user presence state via Redis."""

    PRESENCE_TTL = 45  # seconds
    FRIEND_CACHE_TTL = 300  # 5 minutes

    def __init__(self) -> None:
        self._redis: redis.Redis | None = None
        self._pubsub_tasks: dict[str, asyncio.Task] = {}
        self._db_pool: asyncpg.Pool | None = None

    def set_db_pool(self, pool: asyncpg.Pool) -> None:
        """Set database pool for friend lookups."""
        self._db_pool = pool

    async def _get_redis(self) -> redis.Redis:
        """Get or create Redis connection."""
        if self._redis is None:
            self._redis = redis.from_url(
                settings.REDIS_URL,
                encoding="utf-8",
                decode_responses=True,
            )
        return self._redis

    def _presence_key(self, user_id: str) -> str:
        """Get Redis key for user presence."""
        return f"presence:{user_id}"

    def _presence_channel(self, user_id: str) -> str:
        """Get Redis pubsub channel for user presence updates."""
        return f"channel:presence:{user_id}"

    async def update_presence(self, user_id: str, data: dict) -> None:
        """Update user presence data in Redis and publish notification."""
        r = await self._get_redis()
        key = self._presence_key(user_id)

        # Store presence data as hash
        presence_data = {
            "user_id": user_id,
            "online": "true",
            **{k: json.dumps(v) if isinstance(v, (dict, list)) else str(v) for k, v in data.items()},
        }

        pipe = r.pipeline()
        pipe.hset(key, mapping=presence_data)
        pipe.expire(key, self.PRESENCE_TTL)
        await pipe.execute()

        # Publish presence update to subscribers
        channel = self._presence_channel(user_id)
        await r.publish(channel, json.dumps(presence_data))

    async def heartbeat(self, user_id: str) -> None:
        """Refresh TTL on user's presence key."""
        r = await self._get_redis()
        key = self._presence_key(user_id)
        await r.expire(key, self.PRESENCE_TTL)

    async def set_offline(self, user_id: str) -> None:
        """Set user as offline and notify subscribers."""
        r = await self._get_redis()
        key = self._presence_key(user_id)

        offline_data = {
            "user_id": user_id,
            "online": "false",
        }

        # Update presence to offline (short TTL for cleanup)
        pipe = r.pipeline()
        pipe.hset(key, mapping=offline_data)
        pipe.expire(key, 60)  # Keep offline status briefly
        await pipe.execute()

        # Publish offline notification
        channel = self._presence_channel(user_id)
        await r.publish(channel, json.dumps(offline_data))

    async def get_presence(self, user_id: str) -> dict[str, Any] | None:
        """Get presence data for a user."""
        r = await self._get_redis()
        key = self._presence_key(user_id)
        data = await r.hgetall(key)

        if not data:
            return None

        # Parse JSON fields back to Python objects
        result: dict[str, Any] = {}
        for k, v in data.items():
            if v == "true":
                result[k] = True
            elif v == "false":
                result[k] = False
            else:
                try:
                    result[k] = json.loads(v)
                except (json.JSONDecodeError, TypeError):
                    result[k] = v

        return result

    async def get_friends_presence(self, user_id: str) -> list[dict[str, Any]]:
        """Get presence data for all friends of a user."""
        friend_ids = await self._get_friend_ids(user_id)
        if not friend_ids:
            return []

        r = await self._get_redis()

        # Batch fetch presence for all friends
        pipe = r.pipeline()
        for friend_id in friend_ids:
            pipe.hgetall(self._presence_key(friend_id))
        results = await pipe.execute()

        presences = []
        for friend_id, data in zip(friend_ids, results):
            if data:
                presence = {"user_id": friend_id}
                for k, v in data.items():
                    if v == "true":
                        presence[k] = True
                    elif v == "false":
                        presence[k] = False
                    else:
                        try:
                            presence[k] = json.loads(v)
                        except (json.JSONDecodeError, TypeError):
                            presence[k] = v
                presences.append(presence)

        return presences

    async def _get_friend_ids(self, user_id: str) -> list[str]:
        """Get friend IDs from cache or database."""
        r = await self._get_redis()
        cache_key = f"friends:{user_id}"

        # Try cache first
        cached = await r.smembers(cache_key)
        if cached:
            return list(cached)

        # Fetch from database and cache
        if self._db_pool is None:
            return []

        try:
            user_uuid = UUID(user_id)
        except ValueError:
            return []

        async with self._db_pool.acquire() as conn:
            # Use the get_friend_ids SQL function
            rows = await conn.fetch(
                "SELECT * FROM get_friend_ids($1)",
                user_uuid,
            )

        friend_ids = [str(row[0]) for row in rows]

        # Cache the friend IDs
        if friend_ids:
            await r.sadd(cache_key, *friend_ids)
            await r.expire(cache_key, self.FRIEND_CACHE_TTL)

        return friend_ids

    async def subscribe_to_friends(self, user_id: str, websocket: WebSocket) -> None:
        """Subscribe to presence updates for all friends and forward to websocket."""
        friend_ids = await self._get_friend_ids(user_id)
        if not friend_ids:
            return

        r = await self._get_redis()
        pubsub = r.pubsub()

        # Subscribe to all friend presence channels
        channels = [self._presence_channel(fid) for fid in friend_ids]
        await pubsub.subscribe(*channels)

        async def listen() -> None:
            try:
                async for message in pubsub.listen():
                    if message["type"] == "message":
                        try:
                            data = json.loads(message["data"])
                            await websocket.send_json({
                                "type": "presence_update",
                                "data": data,
                            })
                        except Exception:
                            break
            finally:
                await pubsub.unsubscribe(*channels)
                await pubsub.close()

        # Store task reference for cleanup
        task = asyncio.create_task(listen())
        self._pubsub_tasks[user_id] = task

    async def unsubscribe(self, user_id: str) -> None:
        """Cancel pubsub subscription for a user."""
        task = self._pubsub_tasks.pop(user_id, None)
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    async def close(self) -> None:
        """Close Redis connection and cleanup."""
        # Cancel all pubsub tasks
        for task in self._pubsub_tasks.values():
            task.cancel()
        self._pubsub_tasks.clear()

        if self._redis:
            await self._redis.close()
            self._redis = None


# Singleton instance
presence_manager = PresenceManager()
