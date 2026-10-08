"""Small Redis fixed-window rate limiter exposed as FastAPI dependencies.

Usage:
    @router.post("/x", dependencies=[Depends(rate_limit_ip("auth_device", 10, 3600))])
    @router.get("/y", dependencies=[Depends(rate_limit_user("search", 60, 60))])

Each limit can be overridden per deployment with an env var named
``RATE_LIMIT_<NAME>`` (upper-cased), formatted ``<limit>/<window_seconds>``,
e.g. ``RATE_LIMIT_AUTH_DEVICE=1000/3600``. ``RATE_LIMIT_ENABLED=false`` turns
all limits off.

The limiter fails open (logs a warning) if Redis is unavailable, so a Redis
outage degrades protection rather than taking the API down.
"""

import logging
import os
import time
from collections.abc import Awaitable, Callable
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status

from app.api.deps import get_current_user
from app.config import config
from app.redis_client import get_redis

logger = logging.getLogger(__name__)


def client_ip(request: Request) -> str:
    """Best-effort client IP.

    X-Forwarded-For is honoured only when TRUST_PROXY=true, and then the
    entry PROXY_HOPS from the right is used (the address our own proxy
    appended), never the client-controlled leftmost entry.
    """
    if config.TRUST_PROXY:
        xff = request.headers.get("x-forwarded-for", "")
        hops = [h.strip() for h in xff.split(",") if h.strip()]
        if hops:
            index = max(len(hops) - config.PROXY_HOPS, 0)
            return hops[index]
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def resolve_limit(name: str, limit: int, window: int) -> tuple[int, int]:
    """Apply an optional ``RATE_LIMIT_<NAME>=limit/window`` env override."""
    raw = os.getenv(f"RATE_LIMIT_{name.upper()}")
    if not raw:
        return limit, window
    try:
        lim_s, win_s = raw.split("/", 1)
        lim, win = int(lim_s), int(win_s)
        if lim > 0 and win > 0:
            return lim, win
    except ValueError:
        pass
    logger.warning("Ignoring malformed RATE_LIMIT_%s=%r", name.upper(), raw)
    return limit, window


async def hit(name: str, identity: str, limit: int, window: int) -> None:
    """Count one hit; raise 429 if over the limit for the current window."""
    if not config.RATE_LIMIT_ENABLED:
        return
    now = int(time.time())
    bucket = now // window
    key = f"rl:{name}:{identity}:{bucket}"
    try:
        redis = get_redis()
        pipe = redis.pipeline(transaction=True)
        pipe.incr(key)
        pipe.expire(key, window + 1)
        count, _ = await pipe.execute()
    except Exception:
        logger.warning(
            "Rate limiter unavailable; allowing request (%s)", name, exc_info=True
        )
        return
    if int(count) > limit:
        retry_after = (bucket + 1) * window - now
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests, please try again later",
            headers={"Retry-After": str(max(retry_after, 1))},
        )


def rate_limit_ip(name: str, limit: int, window: int) -> Callable[..., Awaitable[None]]:
    """Dependency limiting requests per client IP."""
    lim, win = resolve_limit(name, limit, window)

    async def _dep(request: Request) -> None:
        await hit(name, f"ip:{client_ip(request)}", lim, win)

    return _dep


def rate_limit_user(
    name: str, limit: int, window: int
) -> Callable[..., Awaitable[None]]:
    """Dependency limiting requests per authenticated user (implies auth)."""
    lim, win = resolve_limit(name, limit, window)

    async def _dep(current_user: Annotated[str, Depends(get_current_user)]) -> None:
        await hit(name, f"user:{current_user}", lim, win)

    return _dep
