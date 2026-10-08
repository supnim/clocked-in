"""API dependencies including authentication."""

from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth.jwt import verify_token
from app.database import get_pool

security = HTTPBearer()


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


async def user_exists(user_id: str) -> bool:
    """Return True if a user row with this id still exists."""
    pool = get_pool()
    if pool is None:
        raise RuntimeError("Database pool not initialized")
    async with pool.acquire() as conn:
        return bool(
            await conn.fetchval("SELECT 1 FROM users WHERE id = $1", UUID(user_id))
        )


async def authenticate_token(token: str) -> str:
    """Validate a JWT and confirm its user still exists.

    Returns the canonical user_id string. Raises HTTPException(401) otherwise.
    Usable outside FastAPI DI (e.g. the WebSocket handler).
    """
    payload = verify_token(token)

    sub = payload.get("sub")
    if not isinstance(sub, str) or not sub:
        raise _unauthorized("Invalid token payload")
    try:
        user_id = str(UUID(sub))
    except ValueError:
        raise _unauthorized("Invalid token payload") from None

    if not await user_exists(user_id):
        raise _unauthorized("User no longer exists")

    return user_id


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
) -> str:
    """
    Validate JWT token and return current user ID.

    Returns the user_id string extracted from the token's 'sub' claim.
    Raises HTTPException 401 if the token is invalid/expired or the user
    no longer exists (e.g. deleted account).
    """
    return await authenticate_token(credentials.credentials)


# Type alias for use with Annotated
CurrentUser = Annotated[str, Depends(get_current_user)]
