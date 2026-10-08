"""User profile, search and lookup endpoints."""

import uuid

from conftest import register_user, requires_stack

pytestmark = requires_stack


async def test_search_lookup_check_require_auth(client):
    assert (await client.get("/api/users/search", params={"q": "pt"})).status_code in (
        401,
        403,
    )
    assert (await client.get("/api/users/check-username/whatever")).status_code in (
        401,
        403,
    )
    assert (await client.get("/api/users/someone")).status_code in (401, 403)


async def test_search_prefix_and_min_length(client):
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    h = alice["headers"]

    assert (
        await client.get("/api/users/search", params={"q": "p"}, headers=h)
    ).status_code == 422

    prefix = bob["username"][:10].upper()  # case-insensitive
    found = await client.get("/api/users/search", params={"q": prefix}, headers=h)
    assert found.status_code == 200
    assert bob["user_id"] in {u["id"] for u in found.json()}

    # Infix does not match (prefix only)
    infix = bob["username"][3:12]
    found = await client.get("/api/users/search", params={"q": infix}, headers=h)
    assert bob["user_id"] not in {u["id"] for u in found.json()}

    # Self is excluded; LIKE wildcards are literal
    found = await client.get(
        "/api/users/search", params={"q": alice["username"]}, headers=h
    )
    assert alice["user_id"] not in {u["id"] for u in found.json()}
    found = await client.get("/api/users/search", params={"q": "%%"}, headers=h)
    assert found.status_code == 200 and found.json() == []


async def test_lookup_and_check_username(client):
    alice = await register_user(client, "alice")
    bob = await register_user(client, "bob")
    h = alice["headers"]

    lookup = await client.get(f"/api/users/{bob['username']}", headers=h)
    assert lookup.status_code == 200
    assert lookup.json()["id"] == bob["user_id"]

    taken = await client.get(f"/api/users/check-username/{bob['username']}", headers=h)
    assert taken.json() == {"available": False}
    mine = await client.get(f"/api/users/check-username/{alice['username']}", headers=h)
    assert mine.json() == {"available": True}
    free = await client.get(
        f"/api/users/check-username/free{uuid.uuid4().hex[:8]}", headers=h
    )
    assert free.json() == {"available": True}
    invalid = await client.get("/api/users/check-username/No!", headers=h)
    assert invalid.json() == {"available": False}


async def test_profile_validation(client):
    alice = await register_user(client, "alice")
    h = alice["headers"]

    async def patch(body):
        return await client.patch("/api/users/me", json=body, headers=h)

    assert (await patch({"display_name": "x" * 51})).status_code == 422
    assert (await patch({"status_message": "x" * 101})).status_code == 422
    assert (await patch({"settings": {"hidden_apps": ["a"] * 201}})).status_code == 422
    assert (await patch({"settings": {"hidden_apps": ["a" * 256]}})).status_code == 422

    ok = await patch(
        {
            "display_name": "x" * 50,
            "status_message": "y" * 100,
            "settings": {"hidden_apps": ["com.example." + "a" * 200] * 200},
        }
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["status_message"] == "y" * 100

    # Omitted field is unchanged; "" clears to null
    unchanged = await patch({"display_name": "Alice"})
    assert unchanged.json()["status_message"] == "y" * 100
    cleared = await patch({"status_message": ""})
    assert cleared.status_code == 200
    assert cleared.json()["status_message"] is None
    assert cleared.json()["display_name"] == "Alice"

    me = await client.get("/api/users/me", headers=h)
    assert me.json()["status_message"] is None
