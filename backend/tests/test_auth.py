"""Integration tests for device auth and JWT verification.

Runs against the live compose stack (see conftest.requires_stack).
"""

import uuid

from conftest import make_expired_token, requires_stack

pytestmark = requires_stack


def _new_device_id() -> str:
    return f"pytest-device-{uuid.uuid4().hex}"


async def test_device_auth_creates_new_user(client):
    device_id = _new_device_id()

    response = await client.post("/auth/device", json={"device_id": device_id})

    assert response.status_code == 200
    body = response.json()
    assert body["is_new"] is True
    assert body["token"]
    assert body["user_id"]


async def test_device_auth_same_device_returns_same_user(client):
    device_id = _new_device_id()

    first = await client.post("/auth/device", json={"device_id": device_id})
    second = await client.post("/auth/device", json={"device_id": device_id})

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["is_new"] is False
    assert second.json()["user_id"] == first.json()["user_id"]


async def test_valid_token_authenticates(client):
    # Exercises get_current_user via /auth/refresh (touches no DB row), not
    # /api/users/me — see test_get_current_user_profile_500s_on_settings_jsonb
    # below for why /me is currently unusable as an auth-path check.
    device_id = _new_device_id()
    register = await client.post("/auth/device", json={"device_id": device_id})
    token = register.json()["token"]

    response = await client.post(
        "/auth/refresh", headers={"Authorization": f"Bearer {token}"}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["access_token"]
    assert body["token_type"] == "bearer"


async def test_garbage_token_rejected(client):
    response = await client.get(
        "/api/users/me", headers={"Authorization": "Bearer garbage"}
    )

    assert response.status_code == 401


async def test_expired_token_rejected(client):
    expired = make_expired_token()

    response = await client.get(
        "/api/users/me", headers={"Authorization": f"Bearer {expired}"}
    )

    assert response.status_code == 401


async def test_missing_token_rejected(client):
    response = await client.get("/api/users/me")

    assert response.status_code in (401, 403)


async def test_get_current_user_profile(client):
    """Guards the jsonb codec registration in app/database.py — without it,
    UserSettings(**row["settings"]) 500s because asyncpg returns jsonb as str."""
    device_id = _new_device_id()
    register = await client.post("/auth/device", json={"device_id": device_id})
    token = register.json()["token"]

    response = await client.get(
        "/api/users/me", headers={"Authorization": f"Bearer {token}"}
    )

    assert response.status_code == 200
    assert isinstance(response.json()["settings"], dict)
