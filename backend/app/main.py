"""FastAPI main application.

Must run as a single uvicorn worker: nudge delivery uses an in-memory
ConnectionManager (app/ws/manager.py). Presence updates are multi-worker-safe
via Redis pub/sub; nudges are not. Move nudges to a Redis channel before
scaling workers.
"""

import asyncio
import logging
import os
import re
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager, suppress
from uuid import UUID

import asyncpg
from fastapi import Depends, FastAPI, HTTPException, Query, WebSocket
from fastapi.responses import JSONResponse
from redis.exceptions import RedisError

from app.api.deps import authenticate_token, get_current_user
from app.api.friends import router as friends_router
from app.api.users import router as users_router
from app.auth.router import router as auth_router
from app.config import config
from app.config import validate as validate_config
from app.database import close_db, get_pool, init_db
from app.redis_client import close_redis, get_redis, init_redis
from app.ws.manager import Connection, manager
from app.ws.presence import presence_manager
from app.ws.session import PresenceSession

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

_TOKEN_RE = re.compile(r"(token=)[^&\s\"']*", re.IGNORECASE)


class RedactTokenFilter(logging.Filter):
    """Redact ``token=...`` query params (WS auth) from uvicorn log lines."""

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str) and "token=" in record.msg.lower():
            record.msg = _TOKEN_RE.sub(r"\1[REDACTED]", record.msg)
        if record.args:
            args = record.args if isinstance(record.args, tuple) else (record.args,)
            if any(isinstance(a, str) and "token=" in a.lower() for a in args):
                redacted = tuple(
                    _TOKEN_RE.sub(r"\1[REDACTED]", a) if isinstance(a, str) else a
                    for a in args
                )
                record.args = (
                    redacted if isinstance(record.args, tuple) else redacted[0]
                )
        return True


def configure_logging() -> None:
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    for name in ("uvicorn.access", "uvicorn.error", "uvicorn"):
        lg = logging.getLogger(name)
        if not any(isinstance(f, RedactTokenFilter) for f in lg.filters):
            lg.addFilter(RedactTokenFilter())


configure_logging()
logger = logging.getLogger(__name__)

PRESENCE_SWEEP_INTERVAL = float(os.getenv("PRESENCE_SWEEP_INTERVAL", "30"))


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup and shutdown."""
    configure_logging()  # uvicorn may have reconfigured loggers after import
    validate_config()
    logger.warning(
        "Starting Clocked-In API (debug=%s, jwt_secret_is_default=%s)",
        config.DEBUG,
        config.JWT_SECRET == "dev-secret-change-in-production",
    )
    pool = await init_db()
    await init_redis()
    presence_manager.set_db_pool(pool)
    sweeper = asyncio.create_task(
        presence_manager.run_sweeper(PRESENCE_SWEEP_INTERVAL), name="presence-sweeper"
    )
    try:
        yield
    finally:
        sweeper.cancel()
        with suppress(asyncio.CancelledError):
            await sweeper
        await presence_manager.close()
        await close_redis()
        await close_db()


app = FastAPI(
    title="Clocked-In API",
    description="Backend API for Clocked-In presence application",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(auth_router)
app.include_router(users_router)
app.include_router(friends_router)


@app.get("/health")
async def health_check() -> dict:
    """Liveness check endpoint."""
    return {"status": "ok"}


@app.get("/health/ready")
async def readiness_check() -> JSONResponse:
    """Readiness: verifies Postgres and Redis are reachable."""
    checks: dict[str, str] = {}

    pool = get_pool()
    try:
        if pool is None:
            raise RuntimeError("pool not initialized")
        async with pool.acquire() as conn:
            await asyncio.wait_for(conn.fetchval("SELECT 1"), timeout=2)
        checks["postgres"] = "ok"
    except (OSError, RuntimeError, TimeoutError, asyncpg.PostgresError) as exc:
        logger.warning("Readiness: postgres check failed: %s", exc)
        checks["postgres"] = "error"

    try:
        await asyncio.wait_for(get_redis().ping(), timeout=2)
        checks["redis"] = "ok"
    except (OSError, RuntimeError, TimeoutError, RedisError) as exc:
        logger.warning("Readiness: redis check failed: %s", exc)
        checks["redis"] = "error"

    ok = all(v == "ok" for v in checks.values())
    return JSONResponse(
        status_code=200 if ok else 503,
        content={"status": "ok" if ok else "unavailable", **checks},
    )


@app.post("/api/presence/offline")
async def go_offline(current_user: str = Depends(get_current_user)) -> dict:
    """Explicitly set user offline (for graceful app quit).

    Lets the client mark itself offline even if the WebSocket can't be closed
    gracefully. The socket (if any) stays registered so nudges still arrive.
    """
    await presence_manager.set_offline(current_user)
    return {"status": "offline"}


async def _fetch_username(user_id: str) -> str | None:
    pool = get_pool()
    if pool is None:
        return None
    async with pool.acquire() as conn:
        return await conn.fetchval(
            "SELECT username FROM users WHERE id = $1", UUID(user_id)
        )


@app.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket, token: str | None = Query(default=None)
) -> None:
    """WebSocket endpoint for real-time presence (see app/ws/session.py)."""
    if not token:
        await websocket.close(code=4001, reason="Missing token")
        return
    try:
        user_id = await authenticate_token(token)
    except HTTPException:
        await websocket.close(code=4001, reason="Invalid token")
        return
    except Exception:
        logger.exception("WS auth failed unexpectedly")
        await websocket.close(code=1011)
        return

    await websocket.accept()
    conn = Connection(
        websocket=websocket, user_id=user_id, username=await _fetch_username(user_id)
    )
    previous = manager.register(conn)
    if previous is not None:
        await previous.close(code=4000, reason="Replaced by newer connection")

    await PresenceSession(conn).run()
