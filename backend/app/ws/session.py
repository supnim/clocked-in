"""Per-connection WebSocket session: auth'd user, one pub/sub, reader loop.

Protocol (see v1 contract):

server -> client: ``connected``, ``initial_presence``, ``presence_update``,
``heartbeat_ack``, ``nudge``.
client -> server: ``presence_update``, ``heartbeat``, ``go_offline``, ``nudge``.
"""

import asyncio
import contextlib
import json
import logging
from typing import Any
from uuid import UUID

from fastapi import WebSocketDisconnect
from pydantic import ValidationError
from redis.asyncio.client import PubSub

from app.redis_client import get_redis
from app.ws.manager import Connection, manager, nudge_limiter
from app.ws.presence import PresenceIn, presence_manager

logger = logging.getLogger(__name__)

MAX_MESSAGE_BYTES = 64 * 1024
CLOSE_TOO_BIG = 1009
CLOSE_ACCOUNT_DELETED = 4003


class _MessageTooBig(Exception):
    pass


class PresenceSession:
    """Owns everything for one socket; torn down in ``run``'s finally."""

    def __init__(self, conn: Connection) -> None:
        self.conn = conn
        self.user_id = conn.user_id
        self.pubsub: PubSub | None = None
        self.friend_ids: set[str] = set()

    # ------------------------------------------------------------ lifecycle

    async def run(self) -> None:
        listener: asyncio.Task | None = None
        reader: asyncio.Task | None = None
        try:
            await self.conn.send_json({"type": "connected"})

            # Subscribe before reading initial state so no update is missed.
            self.pubsub = get_redis().pubsub(ignore_subscribe_messages=True)
            self.friend_ids = set(await presence_manager.get_friend_ids(self.user_id))
            await self.pubsub.subscribe(
                presence_manager.friends_changed_channel(self.user_id),
                presence_manager.account_deleted_channel(self.user_id),
                *(presence_manager.presence_channel(f) for f in self.friend_ids),
            )
            friends = await presence_manager.get_presences(sorted(self.friend_ids))
            await self.conn.send_json({"type": "initial_presence", "friends": friends})

            listener = asyncio.create_task(self._listen())
            reader = asyncio.create_task(self._read_loop())
            done, _ = await asyncio.wait(
                {listener, reader}, return_when=asyncio.FIRST_COMPLETED
            )
            for task in done:
                exc = task.exception()
                if exc and not isinstance(exc, (WebSocketDisconnect, _MessageTooBig)):
                    logger.error(
                        "WebSocket task failed for user %s",
                        self.user_id,
                        exc_info=exc,
                    )
        except WebSocketDisconnect:
            pass
        except Exception:
            logger.exception("WebSocket error for user %s", self.user_id)
        finally:
            for task in (listener, reader):
                if task and not task.done():
                    task.cancel()
                    with contextlib.suppress(asyncio.CancelledError, Exception):
                        await task
            if self.pubsub is not None:
                with contextlib.suppress(Exception):
                    await self.pubsub.aclose()
            # Only the registered (newest) connection may mark the user offline.
            if manager.unregister(self.conn):
                try:
                    await presence_manager.set_offline(self.user_id)
                except Exception:
                    logger.exception("set_offline failed for %s", self.user_id)
            await self.conn.close()

    # --------------------------------------------------------------- reader

    async def _receive_text(self) -> str:
        message = await self.conn.websocket.receive()
        if message["type"] == "websocket.disconnect":
            raise WebSocketDisconnect(message.get("code", 1000))
        text = message.get("text")
        if text is None:
            raw = message.get("bytes") or b""
            if len(raw) > MAX_MESSAGE_BYTES:
                raise _MessageTooBig
            text = raw.decode("utf-8", errors="replace")
        elif (
            len(text) > MAX_MESSAGE_BYTES
            or len(text.encode("utf-8")) > MAX_MESSAGE_BYTES
        ):
            raise _MessageTooBig
        return text

    async def _read_loop(self) -> None:
        while True:
            try:
                text = await self._receive_text()
            except _MessageTooBig:
                logger.warning("Closing WS for %s: message over 64 KB", self.user_id)
                await self.conn.close(code=CLOSE_TOO_BIG, reason="Message too big")
                raise
            try:
                msg = json.loads(text)
            except ValueError:
                continue
            if not isinstance(msg, dict):
                continue
            await self._handle(msg)

    async def _handle(self, msg: dict[str, Any]) -> None:
        msg_type = msg.get("type")
        if msg_type == "heartbeat":
            await presence_manager.heartbeat(self.user_id)
            await self.conn.send_json({"type": "heartbeat_ack"})
        elif msg_type == "presence_update":
            try:
                data = PresenceIn.model_validate(msg.get("data"))
            except ValidationError as exc:
                logger.info(
                    "Rejected presence_update from %s: %d error(s)",
                    self.user_id,
                    exc.error_count(),
                )
                return
            await presence_manager.update_presence(self.user_id, data)
        elif msg_type == "go_offline":
            await presence_manager.set_offline(self.user_id)
        elif msg_type == "nudge":
            await self._handle_nudge(msg)

    async def _handle_nudge(self, msg: dict[str, Any]) -> None:
        target = msg.get("to_user_id")
        if target is None and isinstance(msg.get("data"), dict):
            target = msg["data"].get("to_user_id")
        if not isinstance(target, str):
            return
        try:
            target = str(UUID(target))
        except ValueError:
            return
        if not await presence_manager.are_friends(self.user_id, target):
            logger.info("Dropped nudge %s -> %s: not friends", self.user_id, target)
            return
        if not nudge_limiter.allow(self.user_id, target):
            logger.info("Dropped nudge %s -> %s: rate limited", self.user_id, target)
            return
        await manager.send_to_user(
            target,
            {
                "type": "nudge",
                "data": {
                    "from_user_id": self.user_id,
                    "from_username": self.conn.username,
                },
            },
        )

    # ------------------------------------------------------------- listener

    async def _listen(self) -> None:
        assert self.pubsub is not None
        friends_changed = presence_manager.friends_changed_channel(self.user_id)
        account_deleted = presence_manager.account_deleted_channel(self.user_id)
        prefix = presence_manager.presence_channel("")

        async for message in self.pubsub.listen():
            if message.get("type") != "message":
                continue
            channel = message["channel"]
            if channel == account_deleted:
                await self.conn.close(
                    code=CLOSE_ACCOUNT_DELETED, reason="Account deleted"
                )
                return
            if channel == friends_changed:
                await self._refresh_friends()
                continue
            if channel.startswith(prefix):
                friend_id = channel[len(prefix) :]
                # Drop messages still in flight from a just-unsubscribed friend.
                if friend_id not in self.friend_ids:
                    continue
                try:
                    payload = json.loads(message["data"])
                except ValueError:
                    continue
                if not isinstance(payload, dict):
                    continue
                await self.conn.send_json({**payload, "type": "presence_update"})

    async def _refresh_friends(self) -> None:
        assert self.pubsub is not None
        new_ids = set(
            await presence_manager.get_friend_ids(self.user_id, bypass_cache=True)
        )
        added = new_ids - self.friend_ids
        removed = self.friend_ids - new_ids
        self.friend_ids = new_ids
        if removed:
            await self.pubsub.unsubscribe(
                *(presence_manager.presence_channel(f) for f in removed)
            )
        if added:
            await self.pubsub.subscribe(
                *(presence_manager.presence_channel(f) for f in added)
            )
            for presence in await presence_manager.get_presences(sorted(added)):
                await self.conn.send_json({**presence, "type": "presence_update"})
