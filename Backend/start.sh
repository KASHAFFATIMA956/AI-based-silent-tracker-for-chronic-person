#!/bin/sh
# Container entrypoint — runs on every deploy/restart, not just the first.
# Two things Railway needs that plain `uvicorn app.main:app` doesn't give:
#   1. Migrations applied before the app starts serving traffic (Alembic
#      is idempotent — `upgrade head` on an already-current DB is a no-op,
#      confirmed via this exact script in a real container run, see
#      context/decisions-log.md).
#   2. Binding to $PORT, which Railway assigns dynamically per deploy —
#      never a fixed port. Falls back to 8000 only for a local
#      `docker run` with no -e PORT set (matches every dev session's own
#      convention in this project).
set -e

echo "Running database migrations..."
alembic upgrade head

echo "Starting server on port ${PORT:-8000}..."
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
