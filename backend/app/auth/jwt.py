"""JWT authentication utilities for FastAPI."""

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from jose import JWTError, jwt

from app.config import MIN_JWT_SECRET_BYTES, config


def _secret() -> str:
    """Return the signing secret, refusing to operate with a weak one."""
    secret = config.JWT_SECRET
    if not secret or len(secret.encode()) < MIN_JWT_SECRET_BYTES:
        raise RuntimeError(
            f"JWT_SECRET must be set and at least {MIN_JWT_SECRET_BYTES} bytes"
        )
    return secret


def create_access_token(user_id: str) -> str:
    """Create a JWT access token with expiration claim.

    Args:
        user_id: The user ID to encode in the token's 'sub' claim.

    Returns:
        Encoded JWT string.
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(hours=config.JWT_EXPIRATION_HOURS)
    to_encode = {"sub": user_id, "exp": expire, "iat": now}
    return jwt.encode(to_encode, _secret(), algorithm=config.JWT_ALGORITHM)


def verify_token(token: str) -> dict:
    """Decode and validate a JWT token.

    Args:
        token: The JWT string to verify.

    Returns:
        Decoded token payload as a dictionary.

    Raises:
        HTTPException: If token is invalid, expired, or malformed.
    """
    try:
        payload = jwt.decode(
            token,
            _secret(),
            algorithms=[config.JWT_ALGORITHM],
            options={"require_exp": True, "require_sub": True},
        )
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from e
