# Deploying the Clocked-In API

Production target: **Fly.io** (one always-on machine) + **managed Postgres** + **managed Redis** (Upstash), TLS at Fly's edge for `api.clockedin.studio.gold`.
Everything here is generic; any host that runs a Docker image with Postgres 15+ and Redis 7 works (see `docker-compose.prod.yml` for a self-hosted variant).

> **Single process.** Nudges are routed through an in-memory connection map, so run exactly **one** machine with one uvicorn worker (the entrypoint enforces `--workers 1`). Presence fan-out already goes through Redis pub/sub.

## 1. Required configuration

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | `postgresql://user:pass@host:5432/db` (add `?sslmode=require` if your provider needs it) |
| `REDIS_URL` | yes | Include the password; use `rediss://` for TLS (Upstash) |
| `JWT_SECRET` | yes | **≥ 32 bytes**, random. Startup fails otherwise. `python -c "import secrets; print(secrets.token_urlsafe(48))"`. Rotating it signs everyone out (clients silently re-auth with their device ID). |
| `JWT_EXPIRATION_HOURS` | no | Default **720** (30 days). |
| `DEBUG` | no | Must be `false` (default) in production. `true` allows a built-in dev JWT secret. |
| `TRUST_PROXY` | prod: `true` | Use `X-Forwarded-For` for client IPs (rate limits). Only when the app is reachable *only* via your proxy. |
| `PROXY_HOPS` | no | Default 1 = take the right-most XFF entry (the one Fly's edge appends). |
| `FORWARDED_ALLOW_IPS` | no | Passed to `uvicorn --forwarded-allow-ips` (Fly: `*`). |
| `MIGRATE_ON_START` | no | Default `true`: entrypoint runs `scripts/migrate.py` before uvicorn. Fly uses `release_command` instead (set `false`). |
| `RATE_LIMIT_<NAME>` | no | Override a limit as `count/seconds`: `AUTH_DEVICE` (10/3600 per IP), `SEARCH` (60/60 per user), `FRIEND_REQUEST` (30/3600 per user), `REPORT` (20/86400 per user). `RATE_LIMIT_ENABLED=false` disables all. |
| `APPLE_BUNDLE_ID` | no | Default `gold.studio.clocked-in`. |
| `GOOGLE_*` | no | Google sign-in is hidden in the v1 client. |

## 2. Fly.io

```bash
cd backend
fly auth login
fly launch --no-deploy --copy-config      # keeps fly.toml; pick a unique app name + region

# Postgres: Fly Managed Postgres (or Neon/Supabase/RDS). Attach sets DATABASE_URL.
fly mpg create --name clockedin-db --region sjc
fly mpg attach <cluster-id> --app <app>   # or: fly secrets set DATABASE_URL=...

# Redis: Upstash via Fly (prints a redis:// URL with password)
fly redis create --name clockedin-redis --region sjc --no-replicas
fly secrets set REDIS_URL='redis://default:<password>@fly-clockedin-redis.upstash.io:6379'

fly secrets set JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"

fly deploy                                 # release_command runs scripts/migrate.py first
fly scale count 1                          # exactly one machine (see note above)
```

### TLS / custom domain

```bash
fly certs add api.clockedin.studio.gold
fly certs show api.clockedin.studio.gold   # shows the A/AAAA (or CNAME) records to create
```

Create the DNS records at your registrar, wait for `fly certs check` to report the certificate as issued. `force_https = true` redirects HTTP to HTTPS; WebSockets use `wss://api.clockedin.studio.gold/ws`. The app speaks plain HTTP inside Fly; TLS terminates at the edge.

## 3. Migrations

Numbered SQL files in `migrations/` (`NNNN_name.sql`) are applied in order by `scripts/migrate.py`, tracked in `schema_migrations`, under a Postgres advisory lock, one transaction per file. It is idempotent (re-running applies nothing).

```bash
DATABASE_URL=... python scripts/migrate.py --status    # applied / pending
DATABASE_URL=... python scripts/migrate.py --dry-run
DATABASE_URL=... python scripts/migrate.py
```

- A database created from the old `init.sql` (no `schema_migrations` table, `users` exists) adopts `0001_baseline` automatically and continues from `0002`.
- Never edit an applied file; add a new number. Write migrations to be safe on a live DB (single machine restarts after migrate).

## 4. Smoke test (do this before submitting to App Review)

```bash
API=https://api.clockedin.studio.gold

curl -fsS $API/health                 # {"status":"ok"} – liveness
curl -fsS $API/health/ready           # PG + Redis reachable (readiness)

# Device auth -> token
TOKEN=$(curl -fsS -X POST $API/auth/device -H 'content-type: application/json' \
  -d '{"device_id":"smoke-'$(uuidgen)'"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')

curl -fsS $API/api/users/me -H "Authorization: Bearer $TOKEN"
curl -s -o /dev/null -w '%{http_code}\n' "$API/api/users/search?q=ab"   # expect 403/401 without token

# WebSocket (npm i -g wscat): expect {"type":"connected"} then initial_presence
wscat -c "wss://api.clockedin.studio.gold/ws?token=$TOKEN"
> {"type":"heartbeat"}                 # expect {"type":"heartbeat_ack"}

# Clean up the smoke-test account
curl -s -o /dev/null -w '%{http_code}\n' -X DELETE $API/api/users/me -H "Authorization: Bearer $TOKEN"   # 204
```

Also confirm: `fly logs` shows no tokens in access-log lines, and `fly status` shows exactly one machine.

## 5. Operations

- **Logs:** `fly logs`. User reports are logged at WARNING (`User report ...`) and stored in the `reports` table: `SELECT * FROM reports ORDER BY created_at DESC;`
- **Backups:** enable automated backups / PITR on the managed Postgres. Redis holds only ephemeral presence, rate-limit counters and caches; no persistence needed.
- **Rollback:** `fly releases` then `fly deploy --image <previous-image>`. Migrations are forward-only; keep them backward compatible with the previous release.

## Local development

```bash
cp .env.example .env               # DEBUG=true; dev JWT secret is used if JWT_SECRET is empty
docker compose up -d --build       # Postgres/Redis/API bound to 127.0.0.1 only; api runs migrations on start
pip install -r requirements.txt -r requirements-dev.txt
pytest                             # integration tests need the stack; SKIP_INTEGRATION=1 to skip
```

The integration tests register many users from one IP; for repeated local runs set `RATE_LIMIT_AUTH_DEVICE=10000/3600` in `.env`. Point tests at a different server with `CLOCKEDIN_BASE_URL=http://127.0.0.1:8050`.
