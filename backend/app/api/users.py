"""Users API endpoints."""

import re
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

import asyncpg
import asyncpg.exceptions
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.database import get_db
from app.api.deps import get_current_user

router = APIRouter(prefix="/api/users", tags=["users"])


# Pydantic Models
class UserSettings(BaseModel):
    """User settings stored in JSONB."""

    nudge_shake: bool = True
    nudge_sound: bool = True
    nudge_notification: bool = True
    invisible: bool = False
    hidden_apps: list[str] = []
    share_window_title: bool = True
    share_browser_domain: bool = True


class UserResponse(BaseModel):
    """Full user response for authenticated user."""

    id: UUID
    username: str
    email: str | None = None  # Nullable for Apple Sign-In users
    display_name: str | None = None
    avatar_url: str | None = None
    status_message: str | None = None
    settings: UserSettings = Field(default_factory=UserSettings)
    created_at: datetime
    updated_at: datetime


class UserUpdate(BaseModel):
    """Request body for updating user profile."""

    display_name: str | None = None
    status_message: str | None = None
    settings: UserSettings | None = None


class PublicUserResponse(BaseModel):
    """Public user profile (no email, no settings)."""

    id: UUID
    username: str
    display_name: str | None = None
    avatar_url: str | None = None


def _row_to_user_response(row: asyncpg.Record) -> UserResponse:
    """Convert database row to UserResponse."""
    settings_dict = row["settings"] or {}
    return UserResponse(
        id=row["id"],
        username=row["username"],
        email=row["email"],
        display_name=row["display_name"],
        avatar_url=row["avatar_url"],
        status_message=row["status_message"],
        settings=UserSettings(**settings_dict),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


@router.get("/me", response_model=UserResponse)
async def get_current_user_profile(
    current_user: str = Depends(get_current_user),
    db: asyncpg.Connection = Depends(get_db),
) -> UserResponse:
    """Get the current authenticated user's profile."""
    row = await db.fetchrow(
        """
        SELECT id, username, email, display_name, avatar_url,
               status_message, settings, created_at, updated_at
        FROM users
        WHERE id = $1
        """,
        current_user,
    )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return _row_to_user_response(row)


@router.patch("/me", response_model=UserResponse)
async def update_current_user_profile(
    update: UserUpdate,
    current_user: str = Depends(get_current_user),
    db: asyncpg.Connection = Depends(get_db),
) -> UserResponse:
    """Update the current authenticated user's profile."""
    # Build dynamic update from provided fields
    fields: list[tuple[str, Any]] = []
    if update.display_name is not None:
        fields.append(("display_name", update.display_name))
    if update.status_message is not None:
        fields.append(("status_message", update.status_message))
    if update.settings is not None:
        fields.append(("settings", update.settings.model_dump()))

    if not fields:
        return await get_current_user_profile(current_user, db)

    fields.append(("updated_at", datetime.now(timezone.utc)))

    set_clause = ", ".join(f"{col} = ${i+1}" for i, (col, _) in enumerate(fields))
    values = [v for _, v in fields]
    user_param = f"${len(values) + 1}"
    values.append(current_user)

    query = f"""
        UPDATE users
        SET {set_clause}
        WHERE id = {user_param}
        RETURNING id, username, email, display_name, avatar_url,
                  status_message, settings, created_at, updated_at
    """

    row = await db.fetchrow(query, *values)

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return _row_to_user_response(row)


class UsernameClaimRequest(BaseModel):
    """Request body for claiming a username."""

    username: str


class UsernameAvailabilityResponse(BaseModel):
    """Response for username availability check."""

    available: bool


USERNAME_REGEX = re.compile(r"^[a-z0-9_]{3,20}$")


@router.get("/check-username/{username}", response_model=UsernameAvailabilityResponse)
async def check_username_availability(
    username: str,
    db: asyncpg.Connection = Depends(get_db),
) -> UsernameAvailabilityResponse:
    """Check if a username is available."""
    exists = await db.fetchval("SELECT 1 FROM users WHERE username = $1", username)
    return UsernameAvailabilityResponse(available=not exists)


@router.post("/username")
async def claim_username(
    body: UsernameClaimRequest,
    current_user: str = Depends(get_current_user),
    db: asyncpg.Connection = Depends(get_db),
) -> dict:
    """Claim or change a username for the current user."""
    username = body.username.lower()

    # Validate format
    if not USERNAME_REGEX.match(username):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Username must be 3-20 characters, lowercase letters, numbers, and underscores only",
        )

    # Check availability
    existing = await db.fetchval(
        "SELECT id FROM users WHERE username = $1 AND id != $2",
        username,
        current_user,
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username is already taken",
        )

    # Update username
    try:
        await db.execute(
            "UPDATE users SET username = $1, updated_at = $2 WHERE id = $3",
            username,
            datetime.now(timezone.utc),
            current_user,
        )
    except asyncpg.exceptions.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username is already taken",
        )

    return {"username": username}


@router.get("/search")
async def search_users(
    q: str = Query(..., min_length=1),
    db: asyncpg.Connection = Depends(get_db),
) -> list[PublicUserResponse]:
    """Search for users by username prefix."""
    escaped = q.lower().replace("%", "\\%").replace("_", "\\_")
    rows = await db.fetch(
        "SELECT id, username, display_name, avatar_url FROM users WHERE username ILIKE $1 LIMIT 20",
        f"%{escaped}%",
    )
    return [
        PublicUserResponse(
            id=row["id"],
            username=row["username"],
            display_name=row["display_name"],
            avatar_url=row["avatar_url"],
        )
        for row in rows
    ]


@router.get("/{username}", response_model=PublicUserResponse)
async def get_user_by_username(
    username: str,
    db: asyncpg.Connection = Depends(get_db),
) -> PublicUserResponse:
    """Get a user's public profile by username."""
    row = await db.fetchrow(
        """
        SELECT id, username, display_name, avatar_url
        FROM users
        WHERE username = $1
        """,
        username,
    )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return PublicUserResponse(
        id=row["id"],
        username=row["username"],
        display_name=row["display_name"],
        avatar_url=row["avatar_url"],
    )
