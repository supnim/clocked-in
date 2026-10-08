"""Registry of live WebSocket connections (single uvicorn worker).

Connections are tracked per *connection*, not per user: each socket gets a
``Connection`` object, and a user maps to their most recent one. When a user
reconnects, the older socket is closed, and its cleanup sees that it is no
longer the registered connection, so it must not mark the user offline.
"""

import asyncio
import contextlib
import itertools
import logging
import time
from dataclasses import dataclass, field
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger(__name__)

_ids = itertools.count(1)


@dataclass(eq=False)
class Connection:
    websocket: WebSocket
    user_id: str
    username: str | None = None
    id: int = field(default_factory=lambda: next(_ids))
    _send_lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def send_json(self, message: dict[str, Any]) -> None:
        """Serialized send (the reader loop and pub/sub listener both send)."""
        async with self._send_lock:
            await self.websocket.send_json(message)

    async def close(self, code: int = 1000, reason: str | None = None) -> None:
        # Already closed / client gone: nothing left to do.
        with contextlib.suppress(Exception):
            await self.websocket.close(code=code, reason=reason)


class ConnectionManager:
    """Manages active WebSocket connections."""

    def __init__(self) -> None:
        self.active_connections: dict[str, Connection] = {}

    def register(self, conn: Connection) -> Connection | None:
        """Make ``conn`` the user's active connection; return the replaced one."""
        previous = self.active_connections.get(conn.user_id)
        self.active_connections[conn.user_id] = conn
        return previous if previous is not conn else None

    def is_current(self, conn: Connection) -> bool:
        return self.active_connections.get(conn.user_id) is conn

    def has_connection(self, user_id: str) -> bool:
        return user_id in self.active_connections

    def unregister(self, conn: Connection) -> bool:
        """Remove ``conn`` only if it is still the registered one."""
        if self.is_current(conn):
            del self.active_connections[conn.user_id]
            return True
        return False

    async def send_to_user(self, user_id: str, message: dict[str, Any]) -> bool:
        """Send JSON message to a user's active connection."""
        conn = self.active_connections.get(user_id)
        if conn is None:
            return False
        try:
            await conn.send_json(message)
            return True
        except Exception:
            logger.debug("send_to_user failed for %s", user_id, exc_info=True)
            return False


class NudgeRateLimiter:
    """In-memory limiter: one nudge per (sender, target) per ``window`` seconds."""

    def __init__(self, window: float = 30.0) -> None:
        self.window = window
        self._last: dict[tuple[str, str], float] = {}

    def allow(self, sender: str, target: str) -> bool:
        now = time.monotonic()
        if len(self._last) > 10_000:
            self._last = {k: t for k, t in self._last.items() if now - t < self.window}
        last = self._last.get((sender, target))
        if last is not None and now - last < self.window:
            return False
        self._last[(sender, target)] = now
        return True


# Singleton instances
manager = ConnectionManager()
nudge_limiter = NudgeRateLimiter()
