#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.plane-dev-pids"

force=false
if [[ "${1:-}" == "--force" ]]; then
  force=true
fi

if [[ ! -f "$PID_FILE" ]]; then
  STATE_DIR="${PLANE_DEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/plane-dev}"
  ALT_PID_FILE="$STATE_DIR/pids"
  if [[ -f "$ALT_PID_FILE" ]]; then
    PID_FILE="$ALT_PID_FILE"
    echo "Using PID file from state dir: $PID_FILE"
  fi
fi

if [[ ! -f "$PID_FILE" ]]; then
  echo "No PID file found at $PID_FILE. Nothing to stop." >&2
  if [[ "$force" != "true" ]]; then
    exit 0
  fi

  echo "--force specified; attempting to stop dev processes by port..." >&2

  ports=(3001 3002 3003 3110 8000)
  for p in "${ports[@]}"; do
    if command -v lsof >/dev/null 2>&1; then
      while IFS= read -r pid; do
        [[ -z "$pid" ]] && continue
        if kill -0 "$pid" >/dev/null 2>&1; then
          echo "Stopping pid=$pid listening on port $p"
          kill "$pid" >/dev/null 2>&1 || true
        fi
      done < <(lsof -t -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null || true)
    fi
  done

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
