"""Integration test for the friend request -> accept -> friends-list flow.

Runs against the live compose stack (see conftest.requires_stack). Uses
uuid4-suffixed device_ids and usernames per run since there is no DB
cleanup between test runs.
"""

import uuid

from conftest import requires_stack

pytestmark = requires_stack


async def _register_user(client, name_prefix: str) -> dict:
    """Register a device user and claim a unique username for them."""
    suffix = uuid.uuid4().hex[:12]
    device_id = f"pytest-device-{name_prefix}-{suffix}"
    # Username must match ^[a-z0-9_]{3,20}$ (app/api/users.py:161) — keep short.
    username = f"pt{name_prefix[0]}{suffix[:8]}"

    register = await client.post("/auth/device", json={"device_id": device_id})
    assert register.status_code == 200
    token = register.json()["token"]
    user_id = register.json()["user_id"]
    headers = {"Authorization": f"Bearer {token}"}

    claim = await client.post(
        "/api/users/username", json={"username": username}, headers=headers
    )
    assert claim.status_code == 200
    assert claim.json()["username"] == username

    return {"user_id": user_id, "username": username, "headers": headers}


async def test_friend_request_accept_and_list(client):
    alice = await _register_user(client, "alice")
    bob = await _register_user(client, "bob")

    # Alice sends a friend request to Bob by username.
    send = await client.post(
        f"/api/friends/request/{bob['username']}", headers=alice["headers"]
    )
    assert send.status_code == 201
    request_body = send.json()
    assert request_body["recipient_username"] == bob["username"]
    assert request_body["status"] == "pending"

    # Bob sees the pending request from Alice.
    pending = await client.get("/api/friends/requests", headers=bob["headers"])
    assert pending.status_code == 200
    matching = [r for r in pending.json() if r["sender_id"] == alice["user_id"]]
    assert len(matching) == 1
    request_id = matching[0]["id"]

    # Bob accepts.
    accept = await client.post(
        f"/api/friends/accept/{request_id}", headers=bob["headers"]
    )
    assert accept.status_code == 200

    # Both now see each other in their friends list.
    alice_friends = await client.get("/api/friends", headers=alice["headers"])
    bob_friends = await client.get("/api/friends", headers=bob["headers"])

    assert alice_friends.status_code == 200
    assert bob_friends.status_code == 200

    alice_friend_ids = {f["user_id"] for f in alice_friends.json()}
    bob_friend_ids = {f["user_id"] for f in bob_friends.json()}

    assert bob["user_id"] in alice_friend_ids
    assert alice["user_id"] in bob_friend_ids
