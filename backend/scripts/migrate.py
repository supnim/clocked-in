#!/usr/bin/env python3
"""Apply pending SQL migrations from backend/migrations/ in filename order.

    DATABASE_URL=postgresql://... python scripts/migrate.py [--dry-run] [--status]

- Applied migrations are recorded in ``schema_migrations(version, checksum, applied_at)``.
- Each file runs in its own transaction; a failure rolls back that file and stops.
- A Postgres advisory lock serialises concurrent runs (e.g. several machines booting).
- Idempotent: re-running applies nothing new.
- Baseline adoption: if ``schema_migrations`` is missing but a ``users`` table
  exists (database created from the old init.sql), ``0001_baseline.sql`` is
  recorded as applied without executing it.
- Editing an already-applied file is reported as a checksum mismatch (warning);
  add a new numbered file instead.
"""

import argparse
import asyncio
import hashlib
import os
import re
import sys
from pathlib import Path

import asyncpg

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"
BASELINE = "0001_baseline"
LOCK_ID = 727_001_001  # arbitrary, constant advisory-lock key
FILENAME_RE = re.compile(r"^(\d{4})_[a-z0-9_]+\.sql$")


def discover() -> list[tuple[str, Path, str]]:
    """Return [(version, path, sha256)] sorted by version."""
    found = []
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if not FILENAME_RE.match(path.name):
            raise SystemExit(
                f"Bad migration filename (want NNNN_name.sql): {path.name}"
            )
        found.append((path.stem, path, hashlib.sha256(path.read_bytes()).hexdigest()))
    versions = [v[:4] for v, _, _ in found]
    if len(versions) != len(set(versions)):
        raise SystemExit("Duplicate migration number in migrations/")
    return found


async def run(dsn: str, dry_run: bool, status_only: bool) -> int:
    conn = await asyncpg.connect(dsn)
    try:
        await conn.execute("SELECT pg_advisory_lock($1)", LOCK_ID)
        try:
            had_table = await conn.fetchval(
                "SELECT to_regclass('public.schema_migrations') IS NOT NULL"
            )
            if not had_table and not dry_run:
                await conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS schema_migrations (
                        version TEXT PRIMARY KEY,
                        checksum TEXT NOT NULL,
                        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                    )
                    """
                )
            migrations = discover()
            applied: dict[str, str] = {}
            if had_table:
                applied = {
                    r["version"]: r["checksum"]
                    for r in await conn.fetch(
                        "SELECT version, checksum FROM schema_migrations"
                    )
                }
            elif await conn.fetchval("SELECT to_regclass('public.users') IS NOT NULL"):
                base = next((m for m in migrations if m[0] == BASELINE), None)
                if base:
                    print(f"Existing schema detected; adopting {BASELINE} as applied")
                    if not dry_run:
                        await conn.execute(
                            "INSERT INTO schema_migrations (version, checksum) VALUES ($1, $2)",
                            base[0],
                            base[2],
                        )
                    applied[base[0]] = base[2]

            pending = []
            for version, path, checksum in migrations:
                if version in applied:
                    if applied[version] != checksum:
                        print(
                            f"WARNING: {path.name} changed after being applied (checksum mismatch)"
                        )
                    if status_only:
                        print(f"  applied  {version}")
                    continue
                pending.append((version, path, checksum))
                if status_only:
                    print(f"  pending  {version}")

            if status_only:
                return 0
            if not pending:
                print("Database is up to date")
                return 0

            for version, path, checksum in pending:
                if dry_run:
                    print(f"Would apply {path.name}")
                    continue
                print(f"Applying {path.name} ...", flush=True)
                async with conn.transaction():
                    await conn.execute(path.read_text())
                    await conn.execute(
                        "INSERT INTO schema_migrations (version, checksum) VALUES ($1, $2)",
                        version,
                        checksum,
                    )
            print(
                f"Applied {len(pending)} migration(s)"
                if not dry_run
                else "Dry run complete"
            )
            return 0
        finally:
            await conn.execute("SELECT pg_advisory_unlock($1)", LOCK_ID)
    finally:
        await conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--dry-run", action="store_true", help="show what would be applied"
    )
    parser.add_argument(
        "--status", action="store_true", help="list applied/pending migrations"
    )
    parser.add_argument("--database-url", default=os.getenv("DATABASE_URL"))
    args = parser.parse_args()
    if not args.database_url:
        raise SystemExit("DATABASE_URL is not set")
    sys.exit(asyncio.run(run(args.database_url, args.dry_run, args.status)))


if __name__ == "__main__":
    main()
