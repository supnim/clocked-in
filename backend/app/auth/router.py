"""Authentication router for Google OAuth and Apple Sign-In flows."""

import secrets
import uuid
from datetime import datetime, timezone
from typing import Annotated

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field

from app.auth.apple import verify_apple_identity_token
from app.auth.jwt import create_access_token, get_current_user
from app.auth.oauth import (
    exchange_code_for_tokens,
    get_google_auth_url,
    get_google_user_info,
)
from app.database import get_db
from app.redis_client import get_redis

router = APIRouter(prefix="/auth", tags=["auth"])

_OAUTH_STATE_TTL = 600  # 10 minutes


def generate_username_from_email(email: str) -> str:
    """Generate a username from email prefix."""
    prefix = email.split("@")[0]
    # Remove special characters, keep alphanumeric and underscores
    username = "".join(c if c.isalnum() or c == "_" else "" for c in prefix)
    return username.lower()[:30] if username else "user"


# Device registration models
class DeviceRegisterRequest(BaseModel):
    """Request body for device-based registration."""

    device_id: str = Field(min_length=1, max_length=255)
    platform: str = "macos"


class DeviceRegisterResponse(BaseModel):
    """Response from device registration."""

    token: str
    user_id: str
    is_new: bool


@router.post("/device", response_model=DeviceRegisterResponse)
async def register_device(
    request: DeviceRegisterRequest,
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> DeviceRegisterResponse:
    """Register or authenticate via device ID.

    If the device is already registered, returns existing user token.
    Otherwise creates a new user with an empty username (must pick one after).
    Note: users table needs a `device_id` column (TEXT, NULLABLE, UNIQUE).
    """
    # Attempt to insert; ON CONFLICT handles the race condition
    user_uuid = uuid.uuid4()
    now = datetime.now(timezone.utc)
    placeholder_username = f"user_{uuid.uuid4().hex[:12]}"
    row = await db.fetchrow(
        "INSERT INTO users (id, device_id, username, created_at, updated_at) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (device_id) DO NOTHING RETURNING id",
        user_uuid,
        request.device_id,
        placeholder_username,
        now,
        now,
    )

    if row:
        # New user created
        user_id = str(row["id"])
        token = create_access_token(user_id=user_id)
        return DeviceRegisterResponse(token=token, user_id=user_id, is_new=True)

    # Device already registered — fetch existing user
    user = await db.fetchrow(
        "SELECT id FROM users WHERE device_id = $1", request.device_id
    )
    token = create_access_token(user_id=str(user["id"]))
    return DeviceRegisterResponse(
        token=token, user_id=str(user["id"]), is_new=False
    )


@router.get("/google")
async def google_auth() -> RedirectResponse:
    """Redirect to Google OAuth authorization URL."""
    state = secrets.token_urlsafe(32)
    r = get_redis()
    await r.set(f"oauth_state:{state}", "1", ex=_OAUTH_STATE_TTL)
    auth_url = get_google_auth_url(state=state)
    return RedirectResponse(url=auth_url)


@router.get("/callback")
async def google_callback(
    code: Annotated[str, Query(description="Authorization code from Google")],
    state: Annotated[str, Query(description="CSRF state parameter")],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> RedirectResponse:
    """Handle Google OAuth callback.

    Exchanges authorization code for tokens, gets user info,
    finds or creates user, and redirects to app with JWT.
    """
    # Validate CSRF state
    r = get_redis()
    state_key = f"oauth_state:{state}"
    valid = await r.delete(state_key)
    if not valid:
        raise HTTPException(status_code=400, detail="Invalid or expired OAuth state")

    # Exchange code for Google tokens
    tokens = await exchange_code_for_tokens(code)
    access_token = tokens["access_token"]

    # Get user info from Google
    google_user = await get_google_user_info(access_token)
    email = google_user["email"]
    name = google_user.get("name", "")
    picture = google_user.get("picture", "")

    # Find existing user by email
    user = await db.fetchrow(
        "SELECT id, email, username, display_name, avatar_url FROM users WHERE email = $1",
        email,
    )

    if user is None:
        # Create new user
        user_id = str(uuid.uuid4())
        base_username = generate_username_from_email(email)

        # Ensure unique username by appending random suffix if needed
        username = base_username
        existing = await db.fetchval(
            "SELECT 1 FROM users WHERE username = $1", username
        )
        if existing:
            username = f"{base_username}_{uuid.uuid4().hex[:6]}"

        await db.execute(
            """
            INSERT INTO users (id, email, username, display_name, avatar_url)
            VALUES ($1, $2, $3, $4, $5)
            """,
            user_id,
            email,
            username,
            name,
            picture,
        )
    else:
        user_id = str(user["id"])

    # Create JWT token
    jwt_token = create_access_token(user_id=user_id)

    # Redirect to app with token
    redirect_url = f"clockedin://auth?token={jwt_token}&user_id={user_id}"
    return RedirectResponse(url=redirect_url)


@router.post("/refresh")
async def refresh_token(
    current_user_id: Annotated[str, Depends(get_current_user)],
) -> dict:
    """Refresh the current JWT token.

    Requires a valid JWT token and returns a new one.
    """
    new_token = create_access_token(user_id=current_user_id)
    return {"access_token": new_token, "token_type": "bearer"}


# Apple Sign-In models
class AppleSignInRequest(BaseModel):
    """Request body for Apple Sign-In."""

    identity_token: str
    full_name: str | None = None
    email: str | None = None


class AppleSignInResponse(BaseModel):
    """Response from Apple Sign-In."""

    token: str
    user_id: str


@router.post("/apple", response_model=AppleSignInResponse)
async def apple_sign_in(
    request: AppleSignInRequest,
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> AppleSignInResponse:
    """Handle Apple Sign-In.

    Verifies the Apple identity token, finds or creates the user,
    and returns a JWT token for the app.
    """
    try:
        # Verify the Apple identity token
        payload = await verify_apple_identity_token(request.identity_token)
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e)) from e

    # Extract user info from verified token
    apple_user_id = payload["sub"]  # Apple's unique identifier
    email = payload.get("email") or request.email  # Email might be in token or request

    # Find existing user by Apple ID (stored in apple_user_id column)
    user = await db.fetchrow(
        "SELECT id, email, username, display_name, avatar_url FROM users WHERE apple_user_id = $1",
        apple_user_id,
    )

    if user is None and email:
        # Check if user exists by email (might have signed in with Google first)
        user = await db.fetchrow(
            "SELECT id, email, username, display_name, avatar_url FROM users WHERE email = $1",
            email,
        )
        if user is not None:
            # Link Apple ID to existing account
            await db.execute(
                "UPDATE users SET apple_user_id = $1 WHERE id = $2",
                apple_user_id,
                user["id"],
            )

    if user is None:
        # Create new user
        user_id = str(uuid.uuid4())
        display_name = request.full_name or ""

        # Generate username from email or Apple ID
        if email:
            base_username = generate_username_from_email(email)
        else:
            # Use part of Apple user ID if no email
            base_username = f"user_{apple_user_id[:8]}"

        # Ensure unique username
        username = base_username
        existing = await db.fetchval(
            "SELECT 1 FROM users WHERE username = $1", username
        )
        if existing:
            username = f"{base_username}_{uuid.uuid4().hex[:6]}"

        await db.execute(
            """
            INSERT INTO users (id, email, username, display_name, apple_user_id)
            VALUES ($1, $2, $3, $4, $5)
            """,
            user_id,
            email,
            username,
            display_name,
            apple_user_id,
        )
    else:
        user_id = str(user["id"])

    # Create JWT token
    jwt_token = create_access_token(user_id=user_id)

    return AppleSignInResponse(token=jwt_token, user_id=user_id)
