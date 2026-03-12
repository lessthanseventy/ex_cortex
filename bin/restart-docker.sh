#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_FILE="$PROJECT_DIR/log/restart.log"
PORT="${PORT:-4000}"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[restart-docker] $(date -Iseconds) Starting restart..." | tee -a "$LOG_FILE"

cd "$PROJECT_DIR"
git pull --ff-only 2>&1 | tee -a "$LOG_FILE"

if git diff HEAD~1 --name-only 2>/dev/null | grep -q "mix.lock\|Dockerfile\|docker-compose"; then
  echo "[restart-docker] Rebuilding container..." | tee -a "$LOG_FILE"
  docker-compose up -d --build app 2>&1 | tee -a "$LOG_FILE"
else
  echo "[restart-docker] Restarting container..." | tee -a "$LOG_FILE"
  docker-compose restart app 2>&1 | tee -a "$LOG_FILE"
fi

echo "[restart-docker] Waiting for http://localhost:$PORT ..." | tee -a "$LOG_FILE"
for i in $(seq 1 60); do
  if curl -sf "http://localhost:$PORT" > /dev/null 2>&1; then
    echo "[restart-docker] App is up after ${i}s" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "[restart-docker] TIMEOUT — app did not come up in 60s" | tee -a "$LOG_FILE"
exit 1
