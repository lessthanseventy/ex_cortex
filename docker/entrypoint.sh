#!/bin/bash
set -e

echo "Running migrations..."
/app/bin/ex_cellence_server eval "ExCellenceServer.Release.migrate()"

echo "Starting server..."
exec /app/bin/ex_cellence_server start
