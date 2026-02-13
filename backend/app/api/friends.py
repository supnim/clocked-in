"""Friends API endpoints for managing friendships and friend requests."""

from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.api.deps import get_current_user
from app.database import get_db
from app.redis_client import get_redis
from app.ws.presence import presence_manager

router = APIRouter(prefix="/api/friends", tags=["friends"])


# -----------------------------------------------------------------------------
# Pydantic Models
# -----------------------------------------------------------------------------


class PresenceData(BaseModel):
    """Current presence data for a user."""

    online: bool = False
    app_name: str | None = None
    app_bundle_id: str | None = None
    window_title: str | None = None
    url: str | None = None
    updated_at: datetime | None = None


class FriendResponse(BaseModel):
    """Response model for a friend with presence info."""

    user_id: str
    username: str
    display_name: str | None = None
    avatar_url: str | None = None
    presence: PresenceData
    friends_since: datetime


class FriendRequestResponse(BaseModel):
    """Response model for a friend request."""

    id: str
    sender_id: str
    sender_username: str
    sender_display_name: str | None = None
    sender_avatar_url: str | None = None
    created_at: datetime


class FriendRequestSentResponse(BaseModel):
    """Response when a friend request is sent."""

    id: str
    recipient_id: str
    recipient_username: str
    status: str
    created_at: datetime


class MessageResponse(BaseModel):
    """Simple message response."""

    message: str


# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------


async def get_presence_from_redis(user_id: str) -> PresenceData:
    """Fetch presence data from Redis for a user using HGETALL."""
    data = await presence_manager.get_presence(user_id)

    if data:
        return PresenceData(
            online=data.get("online", False),
            app_name=data.get("app_name"),
            app_bundle_id=data.get("bundle_id"),  # Match WebSocket field name
            window_title=data.get("window_title"),
            url=data.get("browser_domain"),  # Map browser_domain to url
            updated_at=datetime.fromisoformat(data["updated_at"])
            if isinstance(data.get("updated_at"), str)
            else None,
        )

    return PresenceData(online=False)


async def invalidate_friend_cache(redis, user_id: str) -> None:
    """Invalidate the friend list cache for a user."""
    # Use consistent key with presence.py
    cache_key = f"friends:{user_id}"
    await redis.delete(cache_key)


# -----------------------------------------------------------------------------
# Endpoints
# -----------------------------------------------------------------------------


@router.get("", response_model=list[FriendResponse])
async def get_friends(
    current_user: Annotated[str, Depends(get_current_user)],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> list[FriendResponse]:
    """Get list of friends with their current presence.

    Returns all friends of the authenticated user along with their
    real-time presence data from Redis.
    """
    # Query friendships where user is either user_id_1 or user_id_2
    # Parse current_user string to UUID for database query
    try:
        user_uuid = UUID(current_user)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format",
        )

    query = """
        SELECT
            f.created_at as friends_since,
            u.id as friend_id,
            u.username,
            u.display_name,
            u.avatar_url
        FROM friendships f
        JOIN users u ON (
            (f.user_id_1 = $1 AND f.user_id_2 = u.id) OR
            (f.user_id_2 = $1 AND f.user_id_1 = u.id)
        )
        WHERE f.user_id_1 = $1 OR f.user_id_2 = $1
    """
    rows = await db.fetch(query, user_uuid)

    friends = []
    for row in rows:
        presence = await get_presence_from_redis(str(row["friend_id"]))
        friends.append(
            FriendResponse(
                user_id=str(row["friend_id"]),
                username=row["username"],
                display_name=row["display_name"],
                avatar_url=row["avatar_url"],
                presence=presence,
                friends_since=row["friends_since"],
            )
        )

    return friends


@router.post(
    "/request/{username}",
    response_model=FriendRequestSentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def send_friend_request(
    username: str,
    current_user: Annotated[str, Depends(get_current_user)],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> FriendRequestSentResponse:
    """Send a friend request to a user by username.

    Validates that:
    - Target user exists
    - Not sending request to self
    - Not already friends
    - No pending request exists
    """
    # Find target user by username
    target_user = await db.fetchrow(
        "SELECT id, username FROM users WHERE username = $1", username
    )
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    target_id = str(target_user["id"])

    # Validate not self
    if target_id == current_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send friend request to yourself",
        )

    # Check if already friends (sorted user IDs)
    user_ids = sorted([current_user, target_id])
    existing_friendship = await db.fetchrow(
        "SELECT 1 FROM friendships WHERE user_id_1 = $1 AND user_id_2 = $2",
        user_ids[0],
        user_ids[1],
    )
    if existing_friendship:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already friends with this user",
        )

    # Check for existing pending request (either direction)
    existing_request = await db.fetchrow(
        """
        SELECT 1 FROM friend_requests
        WHERE status = 'pending'
        AND (
            (sender_id = $1 AND recipient_id = $2)
            OR (sender_id = $2 AND recipient_id = $1)
        )
        """,
        current_user,
        target_id,
    )
    if existing_request:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Friend request already pending",
        )

    # Create friend request
    now = datetime.now(timezone.utc)
    request_row = await db.fetchrow(
        """
        INSERT INTO friend_requests (sender_id, recipient_id, status, created_at, updated_at)
        VALUES ($1, $2, 'pending', $3, $3)
        RETURNING id, created_at
        """,
        current_user,
        target_id,
        now,
    )

    return FriendRequestSentResponse(
        id=str(request_row["id"]),
        recipient_id=target_id,
        recipient_username=target_user["username"],
        status="pending",
        created_at=request_row["created_at"],
    )


@router.get("/requests", response_model=list[FriendRequestResponse])
async def get_pending_requests(
    current_user: Annotated[str, Depends(get_current_user)],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> list[FriendRequestResponse]:
    """Get pending incoming friend requests.

    Returns all friend requests where the authenticated user is the
    recipient and the status is 'pending'.
    """
    query = """
        SELECT
            fr.id,
            fr.sender_id,
            fr.created_at,
            u.username as sender_username,
            u.display_name as sender_display_name,
            u.avatar_url as sender_avatar_url
        FROM friend_requests fr
        JOIN users u ON fr.sender_id = u.id
        WHERE fr.recipient_id = $1 AND fr.status = 'pending'
        ORDER BY fr.created_at DESC
    """
    rows = await db.fetch(query, current_user)

    return [
        FriendRequestResponse(
            id=str(row["id"]),
            sender_id=str(row["sender_id"]),
            sender_username=row["sender_username"],
            sender_display_name=row["sender_display_name"],
            sender_avatar_url=row["sender_avatar_url"],
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.post("/accept/{request_id}", response_model=MessageResponse)
async def accept_friend_request(
    request_id: UUID,
    current_user: Annotated[str, Depends(get_current_user)],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> MessageResponse:
    """Accept a pending friend request.

    Creates a friendship record with sorted user IDs and updates
    the request status to 'accepted'. Invalidates Redis friend
    cache for both users.
    """
    # Fetch the request and validate ownership
    request_row = await db.fetchrow(
        """
        SELECT id, sender_id, recipient_id, status
        FROM friend_requests
        WHERE id = $1
        """,
        request_id,
    )

    if not request_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found",
        )

    if str(request_row["recipient_id"]) != current_user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to accept this request",
        )

    if request_row["status"] != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Request already {request_row['status']}",
        )

    sender_id = str(request_row["sender_id"])
    now = datetime.now(timezone.utc)

    # Create friendship with sorted user IDs
    user_ids = sorted([current_user, sender_id])

    async with db.transaction():
        # Create friendship record
        await db.execute(
            """
            INSERT INTO friendships (user_id_1, user_id_2, created_at)
            VALUES ($1, $2, $3)
            ON CONFLICT DO NOTHING
            """,
            user_ids[0],
            user_ids[1],
            now,
        )

        # Update request status
        await db.execute(
            """
            UPDATE friend_requests
            SET status = 'accepted', updated_at = $1
            WHERE id = $2
            """,
            now,
            request_id,
        )

    # Invalidate Redis friend cache for both users
    redis = get_redis()
    await invalidate_friend_cache(redis, current_user)
    await invalidate_friend_cache(redis, sender_id)

    return MessageResponse(message="Friend request accepted")


@router.post("/decline/{request_id}", response_model=MessageResponse)
async def decline_friend_request(
    request_id: UUID,
    current_user: Annotated[str, Depends(get_current_user)],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> MessageResponse:
    """Decline a pending friend request.

    Updates the request status to 'declined'.
    """
    # Fetch the request and validate ownership
    request_row = await db.fetchrow(
        """
        SELECT id, recipient_id, status
        FROM friend_requests
        WHERE id = $1
        """,
        request_id,
    )

    if not request_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found",
        )

    if str(request_row["recipient_id"]) != current_user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to decline this request",
        )

    if request_row["status"] != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Request already {request_row['status']}",
        )

    now = datetime.now(timezone.utc)
    await db.execute(
        """
        UPDATE friend_requests
        SET status = 'declined', updated_at = $1
        WHERE id = $2
        """,
        now,
        request_id,
    )

    return MessageResponse(message="Friend request declined")


@router.delete("/{user_id}", response_model=MessageResponse)
async def remove_friend(
    user_id: str,
    current_user: Annotated[str, Depends(get_current_user)],
    db: Annotated[asyncpg.Connection, Depends(get_db)],
) -> MessageResponse:
    """Remove a friendship.

    Deletes the friendship record and invalidates Redis friend
    cache for both users.
    """
    # Use sorted user IDs to find the friendship
    user_ids = sorted([current_user, user_id])

    result = await db.execute(
        """
        DELETE FROM friendships
        WHERE user_id_1 = $1 AND user_id_2 = $2
        """,
        user_ids[0],
        user_ids[1],
    )

    # Check if any row was deleted
    if result == "DELETE 0":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friendship not found",
        )

    # Invalidate Redis friend cache for both users
    redis = get_redis()
    await invalidate_friend_cache(redis, current_user)
    await invalidate_friend_cache(redis, user_id)

    return MessageResponse(message="Friend removed")
