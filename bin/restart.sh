#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PID_FILE="$PROJECT_DIR/.ex_cortex.pid"
PORT="${PORT:-4000}"
LOG_FILE="$PROJECT_DIR/log/restart.log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[restart] $(date -Iseconds) Starting restart..." | tee -a "$LOG_FILE"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "[restart] Sending SIGTERM to PID $PID" | tee -a "$LOG_FILE"
    kill "$PID"
    for i in $(seq 1 20); do
      if ! kill -0 "$PID" 2>/dev/null; then
        echo "[restart] Process exited after ${i}x500ms" | tee -a "$LOG_FILE"
        break
      fi
      sleep 0.5
    done
    if kill -0 "$PID" 2>/dev/null; then
      echo "[restart] SIGKILL" | tee -a "$LOG_FILE"
      kill -9 "$PID"
      sleep 1
    fi
  fi
fi

cd "$PROJECT_DIR"
git pull --ff-only 2>&1 | tee -a "$LOG_FILE"

if git diff HEAD~1 --name-only 2>/dev/null | grep -q "mix.lock"; then
  echo "[restart] mix.lock changed, running deps.get" | tee -a "$LOG_FILE"
  mix deps.get 2>&1 | tee -a "$LOG_FILE"
fi

echo "[restart] Launching mix phx.server..." | tee -a "$LOG_FILE"
nohup mix phx.server >> "$LOG_FILE" 2>&1 &

echo "[restart] Waiting for http://localhost:$PORT ..." | tee -a "$LOG_FILE"
for i in $(seq 1 60); do
  if curl -sf "http://localhost:$PORT" > /dev/null 2>&1; then
    echo "[restart] App is up after ${i}s" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "[restart] TIMEOUT — app did not come up in 60s" | tee -a "$LOG_FILE"
exit 1
