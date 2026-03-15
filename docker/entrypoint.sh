#!/bin/bash
set -e

echo "Starting server (auto-migrates on boot)..."
exec /app/bin/ex_cortex start
