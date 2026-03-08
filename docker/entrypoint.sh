#!/bin/bash
set -e

# Wait for database
echo "Waiting for database..."
while ! pg_isready -h "${DB_HOST:-db}" -U "${DB_USER:-excellence}" -q 2>/dev/null; do
  sleep 1
done

echo "Running migrations..."
/app/bin/ex_cellence_server eval "ExCellenceServer.Release.migrate()"

echo "Starting server..."
exec /app/bin/ex_cellence_server start
