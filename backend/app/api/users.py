"""Users API endpoints."""

import logging
import re
from datetime import datetime, timezone
from typing import Annotated, Any
from uuid import UUID

import asyncpg
import asyncpg.exceptions
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field, StringConstraints

from app.api.deps import CurrentUser
from app.api.ratelimit import rate_limit_user
from app.api.safety import notify_friends_changed
from app.database import get_db
from app.redis_client import get_redis

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/users", tags=["users"])

DB = Annotated[asyncpg.Connection, Depends(get_db)]

DISPLAY_NAME_MAX = 50
STATUS_MESSAGE_MAX = 100
HIDDEN_APPS_MAX_ITEMS = 200
HIDDEN_APP_MAX_LEN = 255


# Pydantic Models
class UserSettings(BaseModel):
    """User settings stored in JSONB (response shape; tolerant of legacy data)."""

    nudge_shake: bool = True
    nudge_sound: bool = True
    nudge_notification: bool = True
    invisible: bool = False
    hidden_apps: list[str] = []
    share_window_title: bool = True
    share_browser_domain: bool = True


class UserSettingsUpdate(UserSettings):
    """Settings as accepted from clients (bounded)."""

    hidden_apps: Annotated[
        list[Annotated[str, StringConstraints(max_length=HIDDEN_APP_MAX_LEN)]],
        Field(max_length=HIDDEN_APPS_MAX_ITEMS),
    ] = []


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
    """Request body for updating user profile.

    Omitted fields are left unchanged. ``""`` or ``null`` for display_name /
    status_message clears the value (stored as NULL).
    """

    display_name: str | None = Field(default=None, max_length=DISPLAY_NAME_MAX)
    status_message: str | None = Field(default=None, max_length=STATUS_MESSAGE_MAX)
    settings: UserSettingsUpdate | None = None


class PublicUserResponse(BaseModel):
    """Public user profile (no email, no settings)."""

    id: UUID
    username: str
    display_name: str | None = None
    avatar_url: str | None = None


class BlockedUserResponse(BaseModel):
    """Entry in the current user's block list."""

    id: UUID
    username: str | None = None
    display_name: str | None = None


class ReportRequest(BaseModel):
    """Request body for reporting a user."""

    reason: str = Field(min_length=1, max_length=500)


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


def _public(row: asyncpg.Record) -> PublicUserResponse:
    return PublicUserResponse(
        id=row["id"],
        username=row["username"],
        display_name=row["display_name"],
        avatar_url=row["avatar_url"],
    )


async def _require_other_user(
    db: asyncpg.Connection, current_user: str, user_id: UUID
) -> None:
    """404 if the target user doesn't exist, 400 if it is the caller."""
    if str(user_id) == current_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot perform this action on yourself",
        )
    if not await db.fetchval("SELECT 1 FROM users WHERE id = $1", user_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
        )


# Excludes rows where u.id and the caller ($1) are in a block relationship.
_NOT_BLOCKED_SQL = """
    NOT EXISTS (
        SELECT 1 FROM blocks b
        WHERE (b.blocker_id = $1::uuid AND b.blocked_id = u.id)
           OR (b.blocker_id = u.id AND b.blocked_id = $1::uuid)
    )
"""


@router.get("/me", response_model=UserResponse)
async def get_current_user_profile(
    current_user: CurrentUser,
    db: DB,
) -> UserResponse:
    """Get the current authenticated user's profile."""
    row = await db.fetchrow(
        """
        SELECT id, username, email, display_name, avatar_url,
               status_message, settings, created_at, updated_at
        FROM users
        WHERE id = $1
        """,
        UUID(current_user),
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
    current_user: CurrentUser,
    db: DB,
) -> UserResponse:
    """Update the current authenticated user's profile."""
    provided = update.model_fields_set
    fields: list[tuple[str, Any]] = []
    for col in ("display_name", "status_message"):
        if col in provided:
            value = getattr(update, col)
            value = value.strip() if isinstance(value, str) else None
            fields.append((col, value or None))
    if update.settings is not None:
        fields.append(("settings", update.settings.model_dump()))

    if not fields:
        return await get_current_user_profile(current_user, db)

    fields.append(("updated_at", datetime.now(timezone.utc)))

    set_clause = ", ".join(f"{col} = ${i + 1}" for i, (col, _) in enumerate(fields))
    values = [v for _, v in fields]
    user_param = f"${len(values) + 1}"
    values.append(UUID(current_user))

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


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_current_user(
    current_user: CurrentUser,
    db: DB,
) -> Response:
    """Permanently delete the current user's account (App Store 5.1.1(v)).

    Friendships, friend requests, blocks and reports cascade in Postgres.
    Presence and friend caches are cleared in Redis, former friends are told
    to refresh (``friends_changed:{fid}``) and live sockets for this user are
    told to close (``account_deleted:{uid}``).
    """
    uid = UUID(current_user)
    async with db.transaction():
        friend_ids = [
            r["fid"] for r in await db.fetch("SELECT get_friend_ids($1) AS fid", uid)
        ]
        await db.execute("DELETE FROM users WHERE id = $1", uid)

    try:
        redis = get_redis()
        await redis.delete(f"presence:{current_user}", f"friends:{current_user}")
        await redis.publish(f"account_deleted:{current_user}", "1")
    except Exception:
        logger.warning(
            "Redis cleanup failed for deleted user %s", current_user, exc_info=True
        )
    await notify_friends_changed(*friend_ids)

    logger.info(
        "Deleted account %s (%d friends notified)", current_user, len(friend_ids)
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me/blocks", response_model=list[BlockedUserResponse])
async def list_blocks(
    current_user: CurrentUser,
    db: DB,
) -> list[BlockedUserResponse]:
    """List users the current user has blocked."""
    rows = await db.fetch(
        """
        SELECT u.id, u.username, u.display_name
        FROM blocks b JOIN users u ON u.id = b.blocked_id
        WHERE b.blocker_id = $1
        ORDER BY b.created_at DESC
        """,
        UUID(current_user),
    )
    return [
        BlockedUserResponse(
            id=r["id"], username=r["username"], display_name=r["display_name"]
        )
        for r in rows
    ]


class UsernameClaimRequest(BaseModel):
    """Request body for claiming a username."""

    username: str = Field(max_length=64)


class UsernameAvailabilityResponse(BaseModel):
    """Response for username availability check."""

    available: bool


USERNAME_REGEX = re.compile(r"^[a-z0-9_]{3,20}$")


@router.get("/check-username/{username}", response_model=UsernameAvailabilityResponse)
async def check_username_availability(
    username: str,
    current_user: CurrentUser,
    db: DB,
) -> UsernameAvailabilityResponse:
    """Check if a username is available (and valid)."""
    username = username.lower()
    if not USERNAME_REGEX.match(username):
        return UsernameAvailabilityResponse(available=False)
    exists = await db.fetchval(
        "SELECT 1 FROM users WHERE username = $1 AND id != $2",
        username,
        UUID(current_user),
    )
    return UsernameAvailabilityResponse(available=not exists)


@router.post("/username")
async def claim_username(
    body: UsernameClaimRequest,
    current_user: CurrentUser,
    db: DB,
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
        UUID(current_user),
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
            UUID(current_user),
        )
    except asyncpg.exceptions.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username is already taken",
        ) from None

    return {"username": username}


@router.get("/search", dependencies=[Depends(rate_limit_user("search", 60, 60))])
async def search_users(
    q: Annotated[str, Query(min_length=2, max_length=50)],
    current_user: CurrentUser,
    db: DB,
) -> list[PublicUserResponse]:
    """Search for users by username prefix (case-insensitive).

    Excludes the caller and anyone in a block relationship with them.
    """
    escaped = (
        q.strip().lower().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    )
    if len(escaped) < 2:
        return []
    rows = await db.fetch(
        f"""
        SELECT u.id, u.username, u.display_name, u.avatar_url
        FROM users u
        WHERE lower(u.username) LIKE $2 ESCAPE '\\'
          AND u.id != $1::uuid
          AND {_NOT_BLOCKED_SQL}
        ORDER BY lower(u.username)
        LIMIT 20
        """,
        current_user,
        f"{escaped}%",
    )
    return [_public(row) for row in rows]


@router.post("/{user_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def block_user(
    user_id: UUID,
    current_user: CurrentUser,
    db: DB,
) -> Response:
    """Block a user: removes friendship and pending requests in both directions."""
    await _require_other_user(db, current_user, user_id)
    me = UUID(current_user)
    async with db.transaction():
        await db.execute(
            """
            DELETE FROM friendships
            WHERE user_id_1 = LEAST($1::uuid, $2::uuid)
              AND user_id_2 = GREATEST($1::uuid, $2::uuid)
            """,
            me,
            user_id,
        )
        await db.execute(
            """
            DELETE FROM friend_requests
            WHERE status = 'pending'
              AND ((sender_id = $1 AND recipient_id = $2)
                OR (sender_id = $2 AND recipient_id = $1))
            """,
            me,
            user_id,
        )
        await db.execute(
            """
            INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)
            ON CONFLICT DO NOTHING
            """,
            me,
            user_id,
        )
    await notify_friends_changed(me, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{user_id}/block", status_code=status.HTTP_204_NO_CONTENT)
async def unblock_user(
    user_id: UUID,
    current_user: CurrentUser,
    db: DB,
) -> Response:
    """Unblock a user (idempotent). Does not restore the former friendship."""
    await db.execute(
        "DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2",
        UUID(current_user),
        user_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{user_id}/report",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(rate_limit_user("report", 20, 86400))],
)
async def report_user(
    user_id: UUID,
    body: ReportRequest,
    current_user: CurrentUser,
    db: DB,
) -> Response:
    """Report a user for moderation review."""
    reason = body.reason.strip()
    if not reason:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Reason is required",
        )
    await _require_other_user(db, current_user, user_id)
    report_id = await db.fetchval(
        "INSERT INTO reports (reporter_id, reported_id, reason) VALUES ($1, $2, $3) RETURNING id",
        UUID(current_user),
        user_id,
        reason,
    )
    logger.warning(
        "User report %s: reporter=%s reported=%s reason=%r",
        report_id,
        current_user,
        user_id,
        reason,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{username}", response_model=PublicUserResponse)
async def get_user_by_username(
    username: str,
    current_user: CurrentUser,
    db: DB,
) -> PublicUserResponse:
    """Get a user's public profile by username (404 if blocked either way)."""
    row = await db.fetchrow(
        f"""
        SELECT u.id, u.username, u.display_name, u.avatar_url
        FROM users u
        WHERE u.username = $2 AND {_NOT_BLOCKED_SQL}
        """,
        current_user,
        username.lower(),
    )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return _public(row)
