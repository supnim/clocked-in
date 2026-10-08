"""Block / unblock / report."""

import os
import uuid

import pytest
from conftest import make_friends, register_user, requires_stack

pytestmark = requires_stack


async def test_block_removes_friendship_and_hides_user(client):
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    await make_friends(client, alice, bob)

    resp = await client.post(
        f"/api/users/{bob['user_id']}/block", headers=alice["headers"]
    )
    assert resp.status_code == 204
    # Idempotent
    resp = await client.post(
        f"/api/users/{bob['user_id']}/block", headers=alice["headers"]
    )
    assert resp.status_code == 204

    # Friendship gone for both
    for me, other in ((alice, bob), (bob, alice)):
        friends = await client.get("/api/friends", headers=me["headers"])
        assert other["user_id"] not in {f["user_id"] for f in friends.json()}

    # Hidden from lookup and search, both directions
    for me, other in ((alice, bob), (bob, alice)):
        lookup = await client.get(
            f"/api/users/{other['username']}", headers=me["headers"]
        )
        assert lookup.status_code == 404
        search = await client.get(
            "/api/users/search", params={"q": other["username"]}, headers=me["headers"]
        )
        assert search.status_code == 200
        assert other["user_id"] not in {u["id"] for u in search.json()}

    # Friend requests rejected both directions
    for me, other in ((alice, bob), (bob, alice)):
        req = await client.post(
            f"/api/friends/request/{other['username']}", headers=me["headers"]
        )
        assert req.status_code == 403
        assert req.json()["detail"] == "Cannot send request"

    # Block list
    blocks = await client.get("/api/users/me/blocks", headers=alice["headers"])
    assert blocks.status_code == 200
    assert blocks.json() == [
        {"id": bob["user_id"], "username": bob["username"], "display_name": None}
    ]
    assert (
        await client.get("/api/users/me/blocks", headers=bob["headers"])
    ).json() == []

    # Unblock restores visibility (not friendship)
    resp = await client.delete(
        f"/api/users/{bob['user_id']}/block", headers=alice["headers"]
    )
    assert resp.status_code == 204
    assert (
        await client.get("/api/users/me/blocks", headers=alice["headers"])
    ).json() == []
    lookup = await client.get(f"/api/users/{bob['username']}", headers=alice["headers"])
    assert lookup.status_code == 200
    friends = await client.get("/api/friends", headers=alice["headers"])
    assert bob["user_id"] not in {f["user_id"] for f in friends.json()}


async def test_block_clears_pending_requests(client):
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    req = await client.post(
        f"/api/friends/request/{bob['username']}", headers=alice["headers"]
    )
    assert req.status_code == 201

    resp = await client.post(
        f"/api/users/{alice['user_id']}/block", headers=bob["headers"]
    )
    assert resp.status_code == 204
    pending = await client.get("/api/friends/requests", headers=bob["headers"])
    assert alice["user_id"] not in {r["sender_id"] for r in pending.json()}


async def test_block_validation(client):
    alice = await register_user(client, "alice")
    assert (
        await client.post(
            f"/api/users/{alice['user_id']}/block", headers=alice["headers"]
        )
    ).status_code == 400
    assert (
        await client.post(f"/api/users/{uuid.uuid4()}/block", headers=alice["headers"])
    ).status_code == 404
    assert (
        await client.post("/api/users/not-a-uuid/block", headers=alice["headers"])
    ).status_code == 422
    assert (await client.post(f"/api/users/{uuid.uuid4()}/block")).status_code in (
        401,
        403,
    )


async def test_report(client):
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    url = f"/api/users/{bob['user_id']}/report"

    ok = await client.post(url, json={"reason": "spam"}, headers=alice["headers"])
    assert ok.status_code == 204

    assert (
        await client.post(url, json={"reason": ""}, headers=alice["headers"])
    ).status_code == 422
    assert (
        await client.post(url, json={"reason": "x" * 501}, headers=alice["headers"])
    ).status_code == 422
    assert (
        await client.post(url, json={}, headers=alice["headers"])
    ).status_code == 422
    assert (
        await client.post(
            f"/api/users/{uuid.uuid4()}/report",
            json={"reason": "x"},
            headers=alice["headers"],
        )
    ).status_code == 404
    assert (await client.post(url, json={"reason": "spam"})).status_code in (401, 403)


@pytest.mark.skipif(not os.getenv("TEST_REDIS_URL"), reason="TEST_REDIS_URL not set")
async def test_friendship_changes_publish_friends_changed(client):
    import redis.asyncio as aioredis

    r = aioredis.from_url(os.environ["TEST_REDIS_URL"], decode_responses=True)
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    pubsub = r.pubsub()
    channels = [
        f"friends_changed:{alice['user_id']}",
        f"friends_changed:{bob['user_id']}",
    ]
    await pubsub.subscribe(*channels)
    try:
        await make_friends(client, alice, bob)
        resp = await client.delete(
            f"/api/friends/{bob['user_id']}", headers=alice["headers"]
        )
        assert resp.status_code == 200

        seen: list[str] = []
        for _ in range(50):
            msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.2)
            if msg:
                assert msg["data"] == "1"
                seen.append(msg["channel"])
            if len(seen) >= 4:
                break
        # accept + remove => each user notified twice
        assert sorted(seen) == sorted(channels * 2)
    finally:
        await pubsub.unsubscribe()
        await pubsub.aclose()
        await r.aclose()
