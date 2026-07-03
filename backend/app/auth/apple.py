"""Apple Sign-In authentication utilities.

Verifies Apple identity tokens using Apple's public keys (JWKS).
"""

import asyncio
import time

import httpx
from jose import jwt, JWTError
from jose.exceptions import ExpiredSignatureError

from app.config import config


# Apple's public key endpoint for JWT verification
APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

# Cache for Apple's public keys
_apple_keys_cache: dict | None = None
_apple_keys_fetched_at: float = 0.0
_apple_keys_lock = asyncio.Lock()

_CACHE_TTL_SECONDS = 86400  # 24 hours


async def get_apple_public_keys() -> dict:
    """Fetch Apple's public keys for JWT verification.

    Returns:
        The JWKS (JSON Web Key Set) from Apple.
    """
    global _apple_keys_cache, _apple_keys_fetched_at

    cache_expired = (time.monotonic() - _apple_keys_fetched_at) > _CACHE_TTL_SECONDS

    if _apple_keys_cache is not None and not cache_expired:
        return _apple_keys_cache

    async with _apple_keys_lock:
        # Double-check after acquiring lock
        cache_expired = (time.monotonic() - _apple_keys_fetched_at) > _CACHE_TTL_SECONDS
        if _apple_keys_cache is not None and not cache_expired:
            return _apple_keys_cache

        async with httpx.AsyncClient() as client:
            response = await client.get(APPLE_KEYS_URL)
            response.raise_for_status()
            _apple_keys_cache = response.json()
            _apple_keys_fetched_at = time.monotonic()
            return _apple_keys_cache


async def verify_apple_identity_token(identity_token: str) -> dict:
    """Verify an Apple identity token and extract user information.

    Args:
        identity_token: The identity token from Sign in with Apple (base64 JWT).

    Returns:
        A dict containing the verified token payload with:
        - sub: Apple's unique user identifier
        - email: User's email (if shared)
        - email_verified: Whether email is verified
        - is_private_email: Whether email is a private relay address

    Raises:
        ValueError: If token verification fails.
    """
    try:
        # Get Apple's public keys
        keys = await get_apple_public_keys()

        # Decode and verify the token
        # python-jose handles key selection from JWKS automatically
        payload = jwt.decode(
            identity_token,
            keys,
            algorithms=["RS256"],
            audience=config.APPLE_BUNDLE_ID,
            issuer=APPLE_ISSUER,
        )

        return payload

    except ExpiredSignatureError as e:
        raise ValueError("Apple identity token has expired") from e
    except JWTError as e:
        raise ValueError(f"Invalid Apple identity token: {e}") from e


def clear_keys_cache() -> None:
    """Clear the cached Apple public keys.

    Useful if keys need to be refreshed after a rotation.
    """
    global _apple_keys_cache, _apple_keys_fetched_at
    _apple_keys_cache = None
    _apple_keys_fetched_at = 0.0
