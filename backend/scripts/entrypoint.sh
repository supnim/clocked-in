#!/bin/sh
# Container entrypoint: optionally migrate, then exec uvicorn (single worker:
# nudges use an in-memory connection manager, see app/main.py).
set -eu

if [ "${MIGRATE_ON_START:-true}" = "true" ]; then
    python scripts/migrate.py
fi

# --proxy-headers lets uvicorn honour X-Forwarded-Proto/For from the proxies
# listed in FORWARDED_ALLOW_IPS (default: none but localhost). Rate limiting
# reads X-Forwarded-For itself, and only when TRUST_PROXY=true.
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --workers 1 \
    --ws-max-size 65536 \
    --proxy-headers \
    --forwarded-allow-ips "${FORWARDED_ALLOW_IPS:-127.0.0.1}" \
    "$@"
