"""Users API endpoints."""

from datetime import datetime, timezone
from typing import Any
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
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
    # Build dynamic update query
    updates: list[str] = []
    values: list[Any] = []
    param_idx = 1

    if update.display_name is not None:
        updates.append(f"display_name = ${param_idx}")
        values.append(update.display_name)
        param_idx += 1

    if update.status_message is not None:
        updates.append(f"status_message = ${param_idx}")
        values.append(update.status_message)
        param_idx += 1

    if update.settings is not None:
        updates.append(f"settings = ${param_idx}")
        values.append(update.settings.model_dump())
        param_idx += 1

    if not updates:
        # No updates provided, just return current user
        return await get_current_user_profile(current_user, db)

    # Always update updated_at
    updates.append(f"updated_at = ${param_idx}")
    values.append(datetime.now(timezone.utc))
    param_idx += 1

    # Add user_id as final parameter
    values.append(current_user)

    query = f"""
        UPDATE users
        SET {", ".join(updates)}
        WHERE id = ${param_idx}
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
