#!/usr/bin/env bash
# Block until the Postgres container is accepting connections.
set -euo pipefail

CONTAINER=${CONTAINER:-baseball-postgres}
TIMEOUT=${TIMEOUT:-60}
USER_=${POSTGRES_USER:-baseball}
DB_=${POSTGRES_DB:-baseball}

echo "▶ Waiting up to ${TIMEOUT}s for ${CONTAINER} to accept connections..."
for ((i = 0; i < TIMEOUT; i++)); do
    if docker exec "${CONTAINER}" pg_isready -U "${USER_}" -d "${DB_}" >/dev/null 2>&1; then
        echo "✓ Postgres is ready."
        exit 0
    fi
    sleep 1
done

echo "✗ Postgres did not become ready within ${TIMEOUT}s." >&2
docker logs --tail 50 "${CONTAINER}" >&2 || true
exit 1
