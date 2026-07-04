#!/bin/bash
# Run the pre-built Headroom image (code-aware + memory + telemetry enabled).
# For end users: this pulls the published image from GHCR — no local build needed.
set -e

# The published image. Override with:  HEADROOM_IMAGE=ghcr.io/tuxetuxe/headroom:latest ./start-headroom.sh
IMAGE="${HEADROOM_IMAGE:-ghcr.io/tuxetuxe/headroom:latest}"

# Host port to expose the proxy on (container always listens on 8787).
PORT="${HEADROOM_PORT:-8787}"

docker pull "$IMAGE"

# Telemetry, code-aware, memory, and the dashboard live-message feed are all
# enabled by the image entrypoint. The named volume persists memory + savings
# across restarts (Headroom writes them under /root/.headroom).
docker run --rm -p "${PORT}:8787" \
  -e HEADROOM_TELEMETRY=on \
  -e HEADROOM_CODE_AWARE_ENABLED=1 \
  -e HEADROOM_MEMORY_DB_PATH=/root/.headroom/memory.db \
  -e HEADROOM_PUBLIC_PORT="${PORT}" \
  -v headroom-memory:/root/.headroom \
  "$IMAGE"
