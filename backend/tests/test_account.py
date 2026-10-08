"""Account deletion and deleted-user token handling."""

import uuid

from conftest import make_friends, make_token, register_user, requires_stack

pytestmark = requires_stack


async def test_delete_account_then_token_rejected(client):
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    await make_friends(client, alice, bob)

    resp = await client.delete("/api/users/me", headers=alice["headers"])
    assert resp.status_code == 204

    # Old token no longer works anywhere, including refresh.
    assert (
        await client.get("/api/users/me", headers=alice["headers"])
    ).status_code == 401
    assert (
        await client.post("/auth/refresh", headers=alice["headers"])
    ).status_code == 401
    assert (
        await client.delete("/api/users/me", headers=alice["headers"])
    ).status_code == 401

    # Bob's friend list no longer contains Alice.
    friends = await client.get("/api/friends", headers=bob["headers"])
    assert friends.status_code == 200
    assert alice["user_id"] not in {f["user_id"] for f in friends.json()}

    # Username is free again; the same device registers as a brand-new user.
    lookup = await client.get(f"/api/users/{alice['username']}", headers=bob["headers"])
    assert lookup.status_code == 404
    again = await client.post("/auth/device", json={"device_id": alice["device_id"]})
    assert again.status_code == 200
    assert again.json()["is_new"] is True
    assert again.json()["user_id"] != alice["user_id"]


async def test_valid_signature_for_nonexistent_user_rejected(client):
    token = make_token(str(uuid.uuid4()))
    resp = await client.get(
        "/api/users/me", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 401
    resp = await client.post(
        "/auth/refresh", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 401


async def test_non_uuid_sub_rejected(client):
    token = make_token("not-a-uuid")
    resp = await client.get(
        "/api/users/me", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 401
