"""Integration tests for the /ws presence protocol (v1 contract).

Like the rest of the suite these run against a LIVE stack. The tests also talk
to that stack's Postgres and Redis directly (to create/delete friendships and
inspect presence keys), so point these env vars at the same services the api
uses:

    CLOCKEDIN_BASE_URL   (default http://localhost:8000)
    TEST_DATABASE_URL    (default postgresql://clockedin:clockedin_dev@localhost:55432/clockedin)
    TEST_REDIS_URL       (default redis://localhost:6379/0)

Each test registers fresh uuid-suffixed device users; nothing is cleaned up.
The suite registers ~25 device users, so run the api with
``RATE_LIMIT_ENABLED=false`` (or a raised ``RATE_LIMIT_AUTH_DEVICE``).
"""

import asyncio
import json
import os
import time
import uuid

import asyncpg
import httpx
import pytest
import redis.asyncio as aioredis
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus

BASE_URL = os.getenv("CLOCKEDIN_BASE_URL", "http://localhost:8000")
WS_URL = BASE_URL.replace("http", "ws", 1) + "/ws"
DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql://clockedin:clockedin_dev@localhost:55432/clockedin",
)
REDIS_URL = os.getenv("TEST_REDIS_URL", "redis://localhost:6379/0")
SWEEP_WAIT = float(os.getenv("TEST_SWEEP_WAIT", "40"))


def _stack_available() -> bool:
    try:
        return httpx.get(f"{BASE_URL}/health", timeout=2.0).status_code == 200
    except httpx.HTTPError:
        return False


pytestmark = pytest.mark.skipif(
    not _stack_available(), reason=f"api not reachable at {BASE_URL}"
)


# -----------------------------------------------------------------------------
# Fixtures / helpers
# -----------------------------------------------------------------------------


@pytest.fixture
async def client():
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10.0) as ac:
        yield ac


@pytest.fixture
async def db():
    conn = await asyncpg.connect(DATABASE_URL)
    yield conn
    await conn.close()


@pytest.fixture
async def rds():
    r = aioredis.from_url(REDIS_URL, decode_responses=True)
    yield r
    await r.aclose()


async def register(client) -> dict:
    suffix = uuid.uuid4().hex[:12]
    resp = await client.post("/auth/device", json={"device_id": f"pytest-ws-{suffix}"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    headers = {"Authorization": f"Bearer {body['token']}"}
    username = f"ws{suffix[:10]}"
    claim = await client.post(
        "/api/users/username", json={"username": username}, headers=headers
    )
    assert claim.status_code == 200, claim.text
    return {"user_id": body["user_id"], "token": body["token"], "username": username}


async def befriend(db, rds, a: dict, b: dict) -> None:
    lo, hi = sorted([a["user_id"], b["user_id"]])
    await db.execute(
        "INSERT INTO friendships (user_id_1, user_id_2) VALUES ($1::uuid, $2::uuid)",
        lo,
        hi,
    )
    await _friends_changed(rds, a, b)


async def unfriend(db, rds, a: dict, b: dict) -> None:
    lo, hi = sorted([a["user_id"], b["user_id"]])
    await db.execute(
        "DELETE FROM friendships WHERE user_id_1 = $1::uuid AND user_id_2 = $2::uuid",
        lo,
        hi,
    )
    await _friends_changed(rds, a, b)


async def _friends_changed(rds, *users: dict) -> None:
    for u in users:
        await rds.delete(f"friends:{u['user_id']}")
        await rds.publish(f"friends_changed:{u['user_id']}", "1")


async def open_ws(user: dict):
    ws, _ = await open_ws_initial(user)
    return ws


async def open_ws_initial(user: dict):
    """Connect and consume the handshake; returns (ws, initial friends list)."""
    ws = await connect(f"{WS_URL}?token={user['token']}")
    first = json.loads(await asyncio.wait_for(ws.recv(), 5))
    assert first == {"type": "connected"}
    second = json.loads(await asyncio.wait_for(ws.recv(), 5))
    assert second["type"] == "initial_presence"
    assert isinstance(second["friends"], list)
    return ws, second["friends"]


async def recv_type(ws, msg_type: str, timeout: float = 5.0) -> dict:
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(f"no {msg_type!r} message within {timeout}s")
        msg = json.loads(await asyncio.wait_for(ws.recv(), remaining))
        if msg["type"] == msg_type:
            return msg


async def assert_silent(ws, msg_type: str, timeout: float = 1.0) -> None:
    with pytest.raises((asyncio.TimeoutError, TimeoutError)):
        await recv_type(ws, msg_type, timeout)


def presence_msg(**data) -> str:
    payload = {
        "status": "online",
        "app_name": "Xcode",
        "bundle_id": "com.apple.dt.Xcode",
    }
    payload.update(data)
    return json.dumps({"type": "presence_update", "data": payload})


def assert_strict_presence(p: dict) -> None:
    assert set(p) >= {
        "user_id",
        "online",
        "status",
        "app_name",
        "bundle_id",
        "app_icon",
        "window_title",
        "browser_domain",
        "updated_at",
    }
    assert isinstance(p["online"], bool)
    assert type(p["updated_at"]) is int
    assert p["status"] in ("online", "away", "ghost", "offline")
    for key in ("app_name", "bundle_id", "app_icon", "window_title", "browser_domain"):
        assert p[key] is None or isinstance(p[key], str)


# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------


async def test_health_ready(client):
    resp = await client.get("/health/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "postgres": "ok", "redis": "ok"}


async def test_connect_sends_connected_and_empty_initial_presence(client):
    loner = await register(client)
    ws, initial = await open_ws_initial(loner)
    try:
        assert initial == []
        await ws.send(json.dumps({"type": "heartbeat"}))
        assert await recv_type(ws, "heartbeat_ack") == {"type": "heartbeat_ack"}
    finally:
        await ws.close()


async def test_bad_token_rejected(client):
    with pytest.raises(InvalidStatus) as exc:
        await connect(f"{WS_URL}?token=not-a-jwt")
    assert exc.value.response.status_code == 403


async def test_presence_types_strict_and_hash_replaced(client, db, rds):
    alice, bob = await register(client), await register(client)
    await befriend(db, rds, alice, bob)
    ws_b = await open_ws(bob)
    ws_a = await open_ws(alice)
    try:
        await ws_a.send(presence_msg(app_name="123", app_icon="iVBORw0KGgo="))
        upd = await recv_type(ws_b, "presence_update")
        assert_strict_presence(upd)
        assert upd["user_id"] == alice["user_id"]
        assert upd["online"] is True
        assert upd["app_name"] == "123"
        assert upd["app_icon"] == "iVBORw0KGgo="

        # Second update omits icon/bundle: stale fields must not survive.
        await ws_a.send(presence_msg(app_name="456", bundle_id=None, status="away"))
        upd = await recv_type(ws_b, "presence_update")
        assert (upd["app_name"], upd["bundle_id"], upd["app_icon"]) == (
            "456",
            None,
            None,
        )
        assert upd["status"] == "away"

        # Ghost: online but app fields hidden.
        await ws_a.send(presence_msg(status="ghost"))
        upd = await recv_type(ws_b, "presence_update")
        assert upd["status"] == "ghost" and upd["online"] is True
        assert upd["app_name"] is None and upd["bundle_id"] is None

        await ws_a.send(presence_msg(app_name="789"))
        await recv_type(ws_b, "presence_update")

        # Fresh connection: initial_presence decodes to the same strict types.
        ws_b2, initial = await open_ws_initial(bob)
        try:
            [p] = [f for f in initial if f["user_id"] == alice["user_id"]]
            assert_strict_presence(p)
            assert p["app_name"] == "789" and p["online"] is True
        finally:
            await ws_b2.close()
    finally:
        await ws_a.close()
        await ws_b.close()


async def test_spoofed_presence_rejected(client, db, rds):
    alice, bob, carol = (
        await register(client),
        await register(client),
        await register(client),
    )
    await befriend(db, rds, alice, bob)
    ws_b = await open_ws(bob)
    ws_a = await open_ws(alice)
    try:
        bad_payloads = [
            {"status": "online", "user_id": carol["user_id"], "app_name": "x"},
            {"status": "online", "online": False},
            {"status": "online", "updated_at": 1},
            {"status": "offline"},
            {"status": "online", "app_name": "a" * 101},
            {"status": "online", "app_icon": "A" * 24001},
            {"status": "online", "app_name": 123},
            {"app_name": "no status"},
        ]
        for data in bad_payloads:
            await ws_a.send(json.dumps({"type": "presence_update", "data": data}))
        await ws_a.send(json.dumps({"type": "presence_update", "data": "nope"}))
        await assert_silent(ws_b, "presence_update", 1.5)
        assert await rds.exists(f"presence:{alice['user_id']}") == 0
        assert await rds.exists(f"presence:{carol['user_id']}") == 0

        # Connection still usable after rejected messages.
        await ws_a.send(json.dumps({"type": "heartbeat"}))
        await recv_type(ws_a, "heartbeat_ack")

        # Messages over 64 KB close the socket.
        await ws_a.send(json.dumps({"type": "heartbeat", "pad": "x" * 70_000}))
        with pytest.raises(ConnectionClosed) as exc:
            await recv_type(ws_a, "never", 5)
        assert exc.value.rcvd is not None and exc.value.rcvd.code == 1009
    finally:
        await ws_a.close()
        await ws_b.close()


async def test_unfriend_stops_stream_and_new_friend_streams(client, db, rds):
    alice, bob = await register(client), await register(client)
    await befriend(db, rds, alice, bob)
    ws_b = await open_ws(bob)
    ws_a = await open_ws(alice)
    try:
        await ws_a.send(presence_msg(app_name="Before"))
        assert (await recv_type(ws_b, "presence_update"))["app_name"] == "Before"

        await unfriend(db, rds, alice, bob)
        await asyncio.sleep(0.5)
        await ws_a.send(presence_msg(app_name="Secret"))
        await assert_silent(ws_b, "presence_update", 1.5)

        # Re-friend without reconnecting: current presence is pushed, then streams.
        await befriend(db, rds, alice, bob)
        upd = await recv_type(ws_b, "presence_update")
        assert upd["user_id"] == alice["user_id"] and upd["app_name"] == "Secret"
        await ws_a.send(presence_msg(app_name="After"))
        assert (await recv_type(ws_b, "presence_update"))["app_name"] == "After"
    finally:
        await ws_a.close()
        await ws_b.close()


async def test_nudge_requires_friendship_and_is_rate_limited(client, db, rds):
    alice, bob, carol = (
        await register(client),
        await register(client),
        await register(client),
    )
    await befriend(db, rds, alice, bob)
    ws_a, ws_b, ws_c = await open_ws(alice), await open_ws(bob), await open_ws(carol)
    try:
        # Non-friend: dropped.
        await ws_a.send(json.dumps({"type": "nudge", "to_user_id": carol["user_id"]}))
        await assert_silent(ws_c, "nudge", 1.0)

        # Friend: delivered (legacy `data` envelope accepted too).
        await ws_a.send(
            json.dumps({"type": "nudge", "data": {"to_user_id": bob["user_id"]}})
        )
        nudge = await recv_type(ws_b, "nudge")
        assert nudge["data"] == {
            "from_user_id": alice["user_id"],
            "from_username": alice["username"],
        }

        # Second nudge within 30s: rate limited.
        await ws_a.send(json.dumps({"type": "nudge", "to_user_id": bob["user_id"]}))
        await assert_silent(ws_b, "nudge", 1.0)
    finally:
        for ws in (ws_a, ws_b, ws_c):
            await ws.close()


async def test_reconnect_does_not_mark_offline(client, db, rds):
    alice, bob = await register(client), await register(client)
    await befriend(db, rds, alice, bob)
    ws_b = await open_ws(bob)
    ws_a1 = await open_ws(alice)
    try:
        await ws_a1.send(presence_msg(app_name="Mail"))
        await recv_type(ws_b, "presence_update")

        ws_a2 = await open_ws(alice)
        # Old socket is closed by the server ...
        with pytest.raises(ConnectionClosed):
            await recv_type(ws_a1, "never", 5)
        # ... without telling friends Alice went offline.
        await assert_silent(ws_b, "presence_update", 1.5)
        assert await rds.exists(f"presence:{alice['user_id']}") == 1

        # New socket is fully live.
        await ws_a2.send(json.dumps({"type": "heartbeat"}))
        await recv_type(ws_a2, "heartbeat_ack")

        # Closing the current socket does mark her offline.
        await ws_a2.close()
        upd = await recv_type(ws_b, "presence_update")
        assert upd["user_id"] == alice["user_id"]
        assert upd["online"] is False and upd["status"] == "offline"
    finally:
        await ws_a1.close()
        await ws_b.close()


async def test_go_offline(client, db, rds):
    alice, bob = await register(client), await register(client)
    await befriend(db, rds, alice, bob)
    ws_b = await open_ws(bob)
    ws_a = await open_ws(alice)
    try:
        await ws_a.send(presence_msg())
        await recv_type(ws_b, "presence_update")

        await ws_a.send(json.dumps({"type": "go_offline"}))
        upd = await recv_type(ws_b, "presence_update")
        assert_strict_presence(upd)
        assert upd["online"] is False and upd["status"] == "offline"
        assert upd["app_name"] is None
        assert await rds.exists(f"presence:{alice['user_id']}") == 0

        # Heartbeat while invisible must not resurrect presence.
        await ws_a.send(json.dumps({"type": "heartbeat"}))
        await recv_type(ws_a, "heartbeat_ack")
        assert await rds.exists(f"presence:{alice['user_id']}") == 0
    finally:
        await ws_a.close()
        await ws_b.close()


async def test_account_deleted_closes_socket(client):
    user = await register(client)
    ws = await open_ws(user)
    r = aioredis.from_url(REDIS_URL, decode_responses=True)
    try:
        await r.publish(f"account_deleted:{user['user_id']}", "1")
        with pytest.raises(ConnectionClosed) as exc:
            await recv_type(ws, "never", 5)
        assert exc.value.rcvd is not None and exc.value.rcvd.code == 4003
    finally:
        await r.aclose()
        await ws.close()


async def test_expired_presence_swept_offline(client, db, rds):
    """A crashed client's key expires; the sweeper tells friends it's offline."""
    alice, bob = await register(client), await register(client)
    await befriend(db, rds, alice, bob)
    ws_b = await open_ws(bob)
    try:
        # Simulate: Alice was online 60s ago, her key has since expired.
        await rds.zadd(
            "presence:last_seen", {alice["user_id"]: int(time.time() * 1000) - 60_000}
        )
        upd = await recv_type(ws_b, "presence_update", SWEEP_WAIT)
        assert upd["user_id"] == alice["user_id"]
        assert upd["online"] is False and upd["status"] == "offline"
        assert await rds.zscore("presence:last_seen", alice["user_id"]) is None
    finally:
        await ws_b.close()
