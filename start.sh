#!/bin/bash
set -e

# Pull the latest base image, then build a thin image on top that adds the
# "code" + "memory" extras and the loopback relay for the live-message feed.
docker pull ghcr.io/chopratejas/headroom:latest
docker build -t headroom-local .

# Telemetry, code-aware, memory, and the dashboard live-message feed are all
# enabled by the image entrypoint. The named volume persists memory + savings
# across restarts (Headroom writes them under /root/.headroom).
docker run -p 8787:8787 \
  -e HEADROOM_TELEMETRY=on \
  -e HEADROOM_CODE_AWARE_ENABLED=1 \
  -e HEADROOM_MEMORY_DB_PATH=/root/.headroom/memory.db \
  -e HEADROOM_PUBLIC_PORT=8787 \
  -v headroom-memory:/root/.headroom \
  headroom-local
