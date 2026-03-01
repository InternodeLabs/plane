#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose-local.yml"

docker compose -f "$COMPOSE_FILE" down

docker compose -f "$COMPOSE_FILE" up -d
