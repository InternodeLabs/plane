#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.plane-dev-pids"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No PID file found at $PID_FILE. Nothing to stop." >&2
  exit 0
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  name="${line%%=*}"
  pid="${line#*=}"

  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    echo "Stopping $name (pid=$pid)..."
    kill "$pid" >/dev/null 2>&1 || true
  fi
done < "$PID_FILE"

# Give processes a moment to exit
sleep 1

# If anything is still alive, terminate more forcefully (but still only the recorded PIDs)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line#*=}"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill -TERM "$pid" >/dev/null 2>&1 || true
  fi
done < "$PID_FILE"

sleep 1

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line#*=}"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    echo "Process pid=$pid still running; sending SIGKILL"
    kill -KILL "$pid" >/dev/null 2>&1 || true
  fi
done < "$PID_FILE"

rm -f "$PID_FILE"

echo "Stopped dev processes started via dev-start.sh."
