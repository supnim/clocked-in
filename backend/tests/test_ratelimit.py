"""Rate limiting: live check on search + unit tests for client IP parsing."""

import asyncio
import os
import time
from types import SimpleNamespace

import pytest
from conftest import register_user, requires_stack


@requires_stack
@pytest.mark.skipif(
    os.getenv("RATE_LIMIT_ENABLED", "true").lower() == "false",
    reason="server under test runs with RATE_LIMIT_ENABLED=false",
)
async def test_search_rate_limited(client):
    alice = await register_user(client, "alice")
    # Fixed 60s window: avoid straddling a boundary.
    remaining = 60 - time.time() % 60
    if remaining < 15:
        await asyncio.sleep(remaining + 0.5)
    statuses = []
    for _ in range(61):
        resp = await client.get(
            "/api/users/search", params={"q": "zz"}, headers=alice["headers"]
        )
        statuses.append(resp.status_code)
    assert statuses[:60] == [200] * 60
    assert statuses[60] == 429
    assert int(resp.headers["retry-after"]) >= 1
    assert resp.json()["detail"]


# --- unit tests (no server needed) ----------------------------------------

os.environ.setdefault("DEBUG", "true")


def _request(peer: str, xff: str | None = None):
    headers = {"x-forwarded-for": xff} if xff is not None else {}
    return SimpleNamespace(headers=headers, client=SimpleNamespace(host=peer))


@pytest.fixture
def ratelimit(monkeypatch):
    from app.api import ratelimit as rl

    return rl


def test_client_ip_ignores_xff_without_trust_proxy(ratelimit, monkeypatch):
    monkeypatch.setattr(ratelimit.config, "TRUST_PROXY", False)
    assert ratelimit.client_ip(_request("10.0.0.1", "1.2.3.4")) == "10.0.0.1"


def test_client_ip_uses_rightmost_hop_when_trusted(ratelimit, monkeypatch):
    monkeypatch.setattr(ratelimit.config, "TRUST_PROXY", True)
    monkeypatch.setattr(ratelimit.config, "PROXY_HOPS", 1)
    # Leftmost entry is attacker-controlled; the proxy appended 5.6.7.8.
    assert ratelimit.client_ip(_request("10.0.0.1", "1.1.1.1, 5.6.7.8")) == "5.6.7.8"
    monkeypatch.setattr(ratelimit.config, "PROXY_HOPS", 2)
    assert ratelimit.client_ip(_request("10.0.0.1", "1.1.1.1, 5.6.7.8")) == "1.1.1.1"
    assert ratelimit.client_ip(_request("10.0.0.1", "")) == "10.0.0.1"


def test_resolve_limit_env_override(ratelimit, monkeypatch):
    monkeypatch.setenv("RATE_LIMIT_UNIT_TEST", "5/10")
    assert ratelimit.resolve_limit("unit_test", 1, 60) == (5, 10)
    monkeypatch.setenv("RATE_LIMIT_UNIT_TEST", "garbage")
    assert ratelimit.resolve_limit("unit_test", 1, 60) == (1, 60)
