"""Application configuration loaded from environment variables."""

import os
from dataclasses import dataclass


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
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"

    # JWT
    JWT_SECRET: str = os.getenv("JWT_SECRET", "dev-secret-change-in-production")
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_HOURS: int = int(os.getenv("JWT_EXPIRATION_HOURS", "24"))

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

    if not config.DEBUG and config.JWT_SECRET == "dev-secret-change-in-production":
        errors.append("JWT_SECRET must be changed from default in production")

    if not os.getenv("DATABASE_URL"):
        errors.append("DATABASE_URL environment variable is not set")

    if not os.getenv("REDIS_URL"):
        errors.append("REDIS_URL environment variable is not set")

    if errors:
        raise ValueError("Config validation failed:\n  - " + "\n  - ".join(errors))
