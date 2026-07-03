"""FastAPI main application."""

import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

logger = logging.getLogger(__name__)

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query, Depends
from fastapi.middleware.cors import CORSMiddleware

from app.config import validate as validate_config
from app.database import close_db, get_pool, init_db
from app.api.deps import get_current_user
from app.redis_client import close_redis, get_redis, init_redis
from app.auth.router import router as auth_router
from app.auth.jwt import verify_token
from app.api.users import router as users_router
from app.api.friends import router as friends_router
from app.ws.manager import manager
from app.ws.presence import presence_manager


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup and shutdown."""
    # Startup
    validate_config()
    pool = await init_db()
    await init_redis()
    # Set database pool on presence manager for friend lookups
    presence_manager.set_db_pool(pool)
    yield
    # Shutdown
    await presence_manager.close()
    await close_redis()
    await close_db()


app = FastAPI(
    title="Clocked-In API",
    description="Backend API for Clocked-In presence application",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: Restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth_router)
app.include_router(users_router)
app.include_router(friends_router)


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {"status": "ok"}


@app.post("/api/presence/offline")
async def go_offline(current_user: str = Depends(get_current_user)) -> dict:
    """Explicitly set user offline (for graceful app quit).

    This endpoint allows the client to notify the server that the user
    is going offline, even if the WebSocket connection can't be closed
    gracefully (e.g., app force-quit, crash).
    """
    await presence_manager.set_offline(current_user)
    manager.disconnect(current_user)
    return {"status": "offline"}


@app.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(default=None)
) -> None:
    """WebSocket endpoint for real-time presence updates.

    Message types:
    - heartbeat: Refresh presence TTL
    - presence_update: Update current activity
    - nudge: Send nudge to a friend
    """
    # Authenticate
    if not token:
        await websocket.close(code=4001, reason="Missing token")
        return

    try:
        payload = verify_token(token)
        user_id = payload.get("sub")
        if not user_id:
            await websocket.close(code=4001, reason="Invalid token")
            return
    except Exception:
        await websocket.close(code=4001, reason="Invalid token")
        return

    # Connect
    await manager.connect(websocket, user_id)

    try:
        # Subscribe to friends' presence updates
        await presence_manager.subscribe_to_friends(user_id, websocket)

        # Send initial friends presence
        friends_presence = await presence_manager.get_friends_presence(user_id)
        if friends_presence:
            await websocket.send_json({
                "type": "initial_presence",
                "data": friends_presence
            })

        # Message loop
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "heartbeat":
                await presence_manager.heartbeat(user_id)

            elif msg_type == "presence_update":
                presence_data = data.get("data", {})
                if not isinstance(presence_data, dict) or "app_name" not in presence_data:
                    continue
                await presence_manager.update_presence(user_id, presence_data)

            elif msg_type == "nudge":
                target_user_id = data.get("data", {}).get("to_user_id")
                if not isinstance(target_user_id, str) or not target_user_id.strip():
                    continue
                # Get sender username for the nudge display
                sender_username = None
                pool = get_pool()
                if pool:
                    async with pool.acquire() as conn:
                        row = await conn.fetchrow(
                            "SELECT username FROM users WHERE id = $1::uuid",
                            user_id,
                        )
                        if row:
                            sender_username = row["username"]

                await manager.send_to_user(target_user_id, {
                    "type": "nudge",
                    "data": {
                        "from_user_id": user_id,
                        "from_username": sender_username
                    }
                })

    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WebSocket error for user %s", user_id)
    finally:
        # Cleanup
        manager.disconnect(user_id)
        await presence_manager.unsubscribe(user_id)
        await presence_manager.set_offline(user_id)
