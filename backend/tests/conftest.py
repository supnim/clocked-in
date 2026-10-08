"""Shared fixtures and helpers for integration tests.

These tests run against a LIVE server (default http://localhost:8000, the
docker-compose stack; override with CLOCKEDIN_BASE_URL) rather than an
in-process app. There is no cleanup between runs, so tests use unique
device_ids/usernames (uuid4 suffix).

If the server isn't reachable, integration tests FAIL. Set
SKIP_INTEGRATION=1 to skip them instead (e.g. in a unit-only CI job).

Note: the suite registers many users from one IP; run the server with
RATE_LIMIT_AUTH_DEVICE=10000/3600 (see DEPLOY.md), or with
RATE_LIMIT_ENABLED=false and export RATE_LIMIT_ENABLED=false to pytest too
(the live rate-limit test is then skipped).
"""

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import uuid
from pathlib import Path

import httpx
import pytest

# Make the `app` package importable for unit tests that don't need the server.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

BASE_URL = (
    os.getenv("CLOCKEDIN_BASE_URL")
    or os.getenv("CLOCKEDIN_API_URL")
    or "http://localhost:8000"
).rstrip("/")
WS_URL = (
    BASE_URL.replace("http://", "ws://", 1).replace("https://", "wss://", 1) + "/ws"
)

_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
_DEV_JWT_SECRET = "dev-only-insecure-jwt-secret-0123456789abcdef-do-not-use"

_stack_state: dict[str, bool] = {}


def _stack_available() -> bool:
    """Probe /health once per session."""
    if "ok" not in _stack_state:
        try:
            response = httpx.get(f"{BASE_URL}/health", timeout=2.0)
            _stack_state["ok"] = response.status_code == 200
        except httpx.HTTPError:
            _stack_state["ok"] = False
    return _stack_state["ok"]


@pytest.fixture(scope="session")
def stack() -> str:
    """Require the live stack: fail (or skip with SKIP_INTEGRATION=1)."""
    if not _stack_available():
        msg = (
            f"API not reachable at {BASE_URL} (start `docker compose up -d` in backend/ "
            "or set CLOCKEDIN_BASE_URL)"
        )
        if os.getenv("SKIP_INTEGRATION") == "1":
            pytest.skip(msg)
        pytest.fail(msg)
    return BASE_URL


# Use as `pytestmark = requires_stack` in integration test modules.
requires_stack = pytest.mark.usefixtures("stack")


def _read_jwt_secret() -> str:
    """JWT secret the running server uses: env, then backend/.env, then dev default."""
    if os.getenv("JWT_SECRET"):
        return os.environ["JWT_SECRET"]
    if _ENV_PATH.exists():
        for line in _ENV_PATH.read_text().splitlines():
            if line.startswith("JWT_SECRET="):
                value = line.split("=", 1)[1].strip()
                if value:
                    return value
    return _DEV_JWT_SECRET


def _b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_token(sub: str, exp_offset: int = 3600) -> str:
    """Hand-craft an HS256 JWT (exp = now + exp_offset seconds)."""
    secret = _read_jwt_secret()
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"sub": sub, "exp": int(time.time()) + exp_offset}

    header_b64 = _b64url(json.dumps(header, separators=(",", ":")).encode())
    payload_b64 = _b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = header_b64 + b"." + payload_b64
    signature = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()

    return (signing_input + b"." + _b64url(signature)).decode()


def make_expired_token(sub: str = "00000000-0000-0000-0000-000000000000") -> str:
    """HS256 JWT with an `exp` in the past."""
    return make_token(sub, exp_offset=-3600)


async def register_user(
    client: httpx.AsyncClient, name_prefix: str = "u", claim: bool = True
) -> dict:
    """Register a device user (and optionally claim a unique username)."""
    suffix = uuid.uuid4().hex[:12]
    device_id = f"pytest-device-{name_prefix}-{suffix}"
    # Username must match ^[a-z0-9_]{3,20}$
    username = f"pt{name_prefix[0]}{suffix}"

    register = await client.post("/auth/device", json={"device_id": device_id})
    assert register.status_code == 200, register.text
    token = register.json()["token"]
    user = {
        "user_id": register.json()["user_id"],
        "device_id": device_id,
        "token": token,
        "headers": {"Authorization": f"Bearer {token}"},
        "username": None,
    }
    if claim:
        resp = await client.post(
            "/api/users/username", json={"username": username}, headers=user["headers"]
        )
        assert resp.status_code == 200, resp.text
        user["username"] = username
    return user


async def make_friends(client: httpx.AsyncClient, a: dict, b: dict) -> None:
    """a requests b, b accepts."""
    send = await client.post(
        f"/api/friends/request/{b['username']}", headers=a["headers"]
    )
    assert send.status_code == 201, send.text
    accept = await client.post(
        f"/api/friends/accept/{send.json()['id']}", headers=b["headers"]
    )
    assert accept.status_code == 200, accept.text


@pytest.fixture
async def client():
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10.0) as ac:
        yield ac
