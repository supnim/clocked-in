"""JWT authentication utilities for FastAPI."""

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from jose import JWTError, jwt

from app.config import config


def create_access_token(user_id: str) -> str:
    """Create a JWT access token with expiration claim.

    Args:
        user_id: The user ID to encode in the token's 'sub' claim.

    Returns:
        Encoded JWT string.
    """
    expire = datetime.now(timezone.utc) + timedelta(hours=config.JWT_EXPIRATION_HOURS)
    to_encode = {"sub": user_id, "exp": expire}
    return jwt.encode(to_encode, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)


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
            token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM]
        )
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from e
