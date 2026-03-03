# AGENTS

This file is a lightweight handoff contract for moving work between environments (local laptop, remote dev box, CI) and between “agents” (people or automated helpers) without losing context.

## Environments

### Repo root

All commands below assume you are in the repo root.

### Node + package manager

- Node is required (see `package.json` -> `engines.node`).
- `pnpm` is required (see `package.json` -> `packageManager`).

### One-time setup

- Create `.env` files:
  - `./setup.sh`

This copies `.env.example` files into place and runs `pnpm install`.

### Start / stop dev

- Start (Docker + dev servers):
  - `./scripts/dev-start.sh`

- Stop:
  - `./scripts/dev-stop.sh`
  - Force stop (kills listeners on the expected dev ports if the PID file is missing):
    - `./scripts/dev-stop.sh --force`

### Logs

`dev-start.sh` writes logs to one of these locations:

- Preferred (repo-local):
  - `./.plane-dev-logs/*.log`
- Fallback (state dir, if repo is not writable):
  - `${PLANE_DEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/plane-dev}/logs/*.log`

### PID file

`dev-start.sh` records background PIDs so `dev-stop.sh` can stop them safely:

- Preferred: `./.plane-dev-pids`
- Fallback: `${PLANE_DEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/plane-dev}/pids`

## Ports

Default dev ports (as printed by `dev-start.sh`):

- Web: `3003`
- Admin: `3001`
- Space: `3002`
- Live: `3110` (configurable via `LIVE_PORT`)

### Live server controls

- Disable live:
  - `SKIP_LIVE=1 ./scripts/dev-start.sh`
- Override live port:
  - `LIVE_PORT=3110 ./scripts/dev-start.sh`

## Remote server workflow

### Why URLs may not load from your laptop

On a remote dev box, dev servers commonly bind to `127.0.0.1` on the remote host, which makes them reachable only from that host.

### Recommended: SSH port forwarding

From your laptop:

- `ssh -L 3003:127.0.0.1:3003 -L 3001:127.0.0.1:3001 -L 3002:127.0.0.1:3002 -L 3110:127.0.0.1:3110 user@remote-host`

Then open on your laptop:

- `http://127.0.0.1:3003/`
- `http://127.0.0.1:3001/god-mode/`
- `http://127.0.0.1:3002/spaces/`
- `http://127.0.0.1:3110/live`

### Verify listeners on the remote host

Run on the remote host:

- `lsof -nP -iTCP:3003 -sTCP:LISTEN`
- `lsof -nP -iTCP:3001 -sTCP:LISTEN`
- `lsof -nP -iTCP:3002 -sTCP:LISTEN`
- `lsof -nP -iTCP:3110 -sTCP:LISTEN`

If a service isn’t listening, check its log file under `.plane-dev-logs/`.

## Agent roles

These are suggested “agents” you can assign (human or automated). Keep the handoff format below so the next agent can continue quickly.

- Setup Agent
  - Ensures `.env` files exist and `pnpm install` has completed.
  - Validates Node/pnpm versions.

- Dev Agent
  - Uses `dev-start.sh`/`dev-stop.sh`.
  - Debugs startup failures via `.plane-dev-logs/*.log`.

- Ops/Remote Agent
  - Sets up SSH port forwarding.
  - Checks firewall/security if exposing ports.
  - Manages Docker services via `docker-compose-local.yml`.

## Handoff format (copy/paste)

When switching environments or agents, paste this block:

- Environment:
  - Host: (local|remote)
  - OS:
  - Repo path:
- What you ran:
  - `./setup.sh` (yes/no)
  - `./scripts/dev-start.sh` (yes/no)
  - `./scripts/dev-stop.sh` (yes/no)
- What’s broken:
  - Symptom:
  - Relevant log tail (last ~50 lines):
    - `.plane-dev-logs/web.log`
    - `.plane-dev-logs/admin.log`
    - `.plane-dev-logs/space.log`
    - `.plane-dev-logs/live.log`
- Network:
  - Using SSH port forwarding? (yes/no)
  - Forwarded ports:
- Next action you want:
  - (e.g. “get web to listen”, “fix missing deps”, “debug API proxy”)
