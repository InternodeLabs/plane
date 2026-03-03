#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.plane-dev-pids"

force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|-f)
      force=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--force|-f]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$PID_FILE" ]]; then
  STATE_DIR="${PLANE_DEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/plane-dev}"
  ALT_PID_FILE="$STATE_DIR/pids"
  if [[ -f "$ALT_PID_FILE" ]]; then
    PID_FILE="$ALT_PID_FILE"
    echo "Using PID file from state dir: $PID_FILE"
  fi
fi

if [[ ! -f "$PID_FILE" ]]; then
  if [[ "$force" != "true" ]]; then
    echo "No PID file found at $PID_FILE. Nothing to stop." >&2
    exit 0
  fi

  echo "No PID file found; force-stopping dev processes by port." >&2

  live_port="${LIVE_PORT:-3110}"
  ports=(3001 3002 3003)
  if [[ "${SKIP_LIVE:-}" != "1" ]]; then
    ports+=("$live_port")
  fi

  pids_to_kill=()
  for port in "${ports[@]}"; do
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      pids_to_kill+=("$pid")
    done < <(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
  done

  if [[ ${#pids_to_kill[@]} -gt 0 ]]; then
    uniq_pids=$(printf "%s\n" "${pids_to_kill[@]}" | sort -u)
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      if kill -0 "$pid" >/dev/null 2>&1; then
        echo "Force stopping pid=$pid" >&2
        kill -TERM "$pid" >/dev/null 2>&1 || true
      fi
    done <<< "$uniq_pids"

    sleep 1

    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      if kill -0 "$pid" >/dev/null 2>&1; then
        echo "Process pid=$pid still running; sending SIGKILL" >&2
        kill -KILL "$pid" >/dev/null 2>&1 || true
      fi
    done <<< "$uniq_pids"
  else
    echo "No dev server processes found listening on expected ports." >&2
  fi

  if command -v docker >/dev/null 2>&1; then
    docker compose -f "$ROOT_DIR/docker-compose-local.yml" down >/dev/null 2>&1 || true
  fi

  echo "Force stop complete."
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
