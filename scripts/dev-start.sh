#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.plane-dev-pids"
LOG_DIR="$ROOT_DIR/.plane-dev-logs"

mkdir -p "$LOG_DIR"

required_ports=(3001 3002 3003)
start_live=true
if [[ "${SKIP_LIVE:-}" == "1" ]]; then
  start_live=false
fi

live_port="${LIVE_PORT:-3110}"
skipped_live=false

if [[ "$start_live" == "true" ]]; then
  required_ports+=("$live_port")
fi

port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

for p in "${required_ports[@]}"; do
  if port_in_use "$p"; then
    if [[ "$start_live" == "true" && "$p" == "$live_port" ]]; then
      echo "Port $p is already in use; skipping live server." >&2
      lsof -nP -iTCP:"$p" -sTCP:LISTEN >&2 || true
      start_live=false
      skipped_live=true
      continue
    fi
    echo "Port $p is already in use. Refusing to start to avoid port auto-shifting." >&2
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >&2 || true
    exit 1
  fi
done

# Start dev servers in background without attaching to TTY (prevents job control suspension)
# Record PIDs so we can stop them safely later.
: > "$PID_FILE"

start_bg() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"

  ("$@" </dev/null >"$log" 2>&1) &
  local pid=$!
  echo "$name=$pid" >> "$PID_FILE"
  echo "Started $name (pid=$pid). Logs: $log"
}

needs_build=false
required_dist_files=(
  "$ROOT_DIR/packages/utils/dist/index.js"
  "$ROOT_DIR/packages/constants/dist/index.mjs"
)

for f in "${required_dist_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    needs_build=true
    break
  fi
done

if [[ "$needs_build" == "true" ]]; then
  echo "Workspace packages are not built yet; building packages first..."
  pnpm turbo run build --filter=./packages/* --force </dev/null >"$LOG_DIR/build.log" 2>&1
  echo "Build complete. Logs: $LOG_DIR/build.log"
fi

# Start supporting services
start_bg "docker" docker compose -f "$ROOT_DIR/docker-compose-local.yml" up -d

# Dev servers
start_bg "web" env WEB_PORT=3003 pnpm --filter web dev
start_bg "admin" pnpm --filter admin dev
start_bg "space" pnpm --filter space dev
if [[ "$start_live" == "true" ]]; then
  start_bg "live" env PORT="$live_port" pnpm --filter live dev
fi

echo

echo "Dev servers started."
echo "- web:   http://127.0.0.1:3003/"
echo "- admin: http://127.0.0.1:3001/god-mode/"
echo "- space: http://127.0.0.1:3002/spaces/"
if [[ "$start_live" == "true" ]]; then
  echo "- live:  http://127.0.0.1:${live_port}/live"
fi
if [[ "$skipped_live" == "true" ]]; then
  echo "- live:  skipped (port ${live_port} already in use)"
fi
echo

echo "To stop: $ROOT_DIR/scripts/dev-stop.sh"
