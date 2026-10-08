# syntax=docker/dockerfile:1
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8000

WORKDIR /app

# Dependencies first for layer caching (plain pip; no extra installer to pin).
COPY requirements.txt .
RUN pip install -r requirements.txt

# Unprivileged runtime user.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY --chown=app:app app/ ./app/
COPY --chown=app:app migrations/ ./migrations/
COPY --chown=app:app scripts/ ./scripts/
RUN chmod 0755 scripts/entrypoint.sh

USER app

EXPOSE 8000

# Liveness only (process up). /health/ready (PG + Redis) is for the platform's
# readiness/smoke checks so a dependency blip doesn't restart the container.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/health', timeout=4)" || exit 1

# Runs migrations (MIGRATE_ON_START=true by default) then uvicorn with
# --proxy-headers --forwarded-allow-ips "$FORWARDED_ALLOW_IPS".
ENTRYPOINT ["./scripts/entrypoint.sh"]
