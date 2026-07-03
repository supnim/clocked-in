"""Shared fixtures and helpers for integration tests.

These tests run against the LIVE local docker-compose stack (api on
localhost:8000) rather than a test DB fixture. There is no cleanup between
runs, so tests must use unique device_ids/usernames (uuid4 suffix) to avoid
colliding with data left behind by previous runs.
"""

import base64
import hashlib
import hmac
import json
import time
from pathlib import Path

import httpx
import pytest

BASE_URL = "http://localhost:8000"

_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"


def _stack_available() -> bool:
    """Probe /health so the suite degrades gracefully when compose is down."""
    try:
        response = httpx.get(f"{BASE_URL}/health", timeout=2.0)
        return response.status_code == 200
    except httpx.HTTPError:
        return False


requires_stack = pytest.mark.skipif(
    not _stack_available(),
    reason="local compose stack not reachable at localhost:8000 "
    "(run `docker compose up -d` in backend/)",
)


def _read_jwt_secret() -> str:
    """Read JWT_SECRET from backend/.env (same value the running api container uses).

    Falls back to the app/config.py default if .env is missing, so the
    expired-token test still has something reasonable to sign with.
    """
    if _ENV_PATH.exists():
        for line in _ENV_PATH.read_text().splitlines():
            if line.startswith("JWT_SECRET="):
                return line.split("=", 1)[1].strip()
    return "dev-secret-change-in-production"


def _b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_expired_token(sub: str = "00000000-0000-0000-0000-000000000000") -> str:
    """Hand-craft an HS256 JWT with an `exp` in the past.

    Avoids pulling python-jose into the test env just for this one case —
    HS256 is plain HMAC-SHA256 over base64url(header).base64url(payload).
    """
    secret = _read_jwt_secret()
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"sub": sub, "exp": int(time.time()) - 3600}

    header_b64 = _b64url(json.dumps(header, separators=(",", ":")).encode())
    payload_b64 = _b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = header_b64 + b"." + payload_b64
    signature = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()

    return (signing_input + b"." + _b64url(signature)).decode()


@pytest.fixture
async def client():
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10.0) as ac:
        yield ac
