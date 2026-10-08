"""Application configuration loaded from environment variables."""

import os
from dataclasses import dataclass

# Development-only JWT secret. Used ONLY when DEBUG=true and JWT_SECRET is unset.
# It satisfies the 32-byte minimum so dev behaves like prod, but it is public,
# so validate() refuses to start with it unless DEBUG=true.
DEV_JWT_SECRET = "dev-only-insecure-jwt-secret-0123456789abcdef-do-not-use"

MIN_JWT_SECRET_BYTES = 32


def _env_bool(name: str, default: str = "false") -> bool:
    return os.getenv(name, default).strip().lower() in ("1", "true", "yes", "on")


@dataclass
class Config:
    """Application configuration."""

    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/clockedin"
    )

    # Redis
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")

    # Server
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))
    DEBUG: bool = _env_bool("DEBUG")

    # Reverse proxy: only when TRUST_PROXY=true is X-Forwarded-For used to
    # determine the client IP (for rate limiting). The client IP is taken
    # PROXY_HOPS entries from the right, i.e. the address appended by the
    # outermost trusted proxy (Fly.io edge = 1 hop). Never trust the leftmost
    # entry: clients can set it to anything.
    TRUST_PROXY: bool = _env_bool("TRUST_PROXY")
    PROXY_HOPS: int = int(os.getenv("PROXY_HOPS", "1"))

    # Rate limiting can be disabled entirely (e.g. local load testing).
    RATE_LIMIT_ENABLED: bool = _env_bool("RATE_LIMIT_ENABLED", "true")

    # JWT
    # Required (>= 32 bytes) unless DEBUG=true, in which case DEV_JWT_SECRET is used.
    JWT_SECRET: str = os.getenv("JWT_SECRET", "") or (
        DEV_JWT_SECRET if _env_bool("DEBUG") else ""
    )
    JWT_ALGORITHM: str = "HS256"
    # Access token lifetime. Default 720h = 30 days. Device-ID login lets the
    # client silently re-authenticate on 401, so long-lived tokens are not
    # required for UX; deleted users are rejected regardless of token expiry.
    JWT_EXPIRATION_HOURS: int = int(os.getenv("JWT_EXPIRATION_HOURS", "720"))

    # Google OAuth
    GOOGLE_CLIENT_ID: str = os.getenv("GOOGLE_CLIENT_ID", "")
    GOOGLE_CLIENT_SECRET: str = os.getenv("GOOGLE_CLIENT_SECRET", "")
    GOOGLE_REDIRECT_URI: str = os.getenv(
        "GOOGLE_REDIRECT_URI", "http://localhost:8000/auth/callback"
    )

    # Apple Sign-In
    # The bundle ID is the client_id for Sign in with Apple
    APPLE_BUNDLE_ID: str = os.getenv("APPLE_BUNDLE_ID", "gold.studio.clocked-in")


config = Config()


def validate() -> None:
    """Validate critical configuration for production readiness.

    Raises:
        ValueError: If any critical config is missing or insecure.
    """
    errors: list[str] = []

    secret = config.JWT_SECRET or ""
    if not secret:
        errors.append(
            "JWT_SECRET must be set (>= 32 bytes; DEBUG=true allows a dev default)"
        )
    elif len(secret.encode()) < MIN_JWT_SECRET_BYTES:
        errors.append(f"JWT_SECRET must be at least {MIN_JWT_SECRET_BYTES} bytes")
    elif secret == DEV_JWT_SECRET and not config.DEBUG:
        errors.append("JWT_SECRET must not be the development default when DEBUG=false")

    if config.JWT_EXPIRATION_HOURS <= 0:
        errors.append("JWT_EXPIRATION_HOURS must be positive")

    if config.PROXY_HOPS < 1:
        errors.append("PROXY_HOPS must be >= 1")

    if not os.getenv("DATABASE_URL"):
        errors.append("DATABASE_URL environment variable is not set")

    if not os.getenv("REDIS_URL"):
        errors.append("REDIS_URL environment variable is not set")

    if errors:
        raise ValueError("Config validation failed:\n  - " + "\n  - ".join(errors))
