#!/bin/bash
# Run the pre-built Headroom image (code-aware + memory + telemetry enabled).
# For end users: this pulls the published image from GHCR — no local build needed.
set -e

# The published image. Override with:  HEADROOM_IMAGE=ghcr.io/tuxetuxe/headroom:latest ./start-headroom.sh
IMAGE="${HEADROOM_IMAGE:-ghcr.io/tuxetuxe/headroom:latest}"

# Host port to expose the proxy on (container always listens on 8787).
PORT="${HEADROOM_PORT:-8787}"

# Output-shaper verbosity level (0-4) applied to ALL projects. Overrides the
# per-project levels from `headroom learn --verbosity`. Override per-run with:
# HEADROOM_VERBOSITY_LEVEL=2 ./start-headroom.sh
VERBOSITY_LEVEL="${HEADROOM_VERBOSITY_LEVEL:-2}"

# Always fetch the newest published image. `docker pull` on a :latest tag is a
# no-op when already current and downloads the new layers otherwise. Don't abort
# on a pull failure (e.g. offline) — fall back to the cached image if present.
if ! docker pull "$IMAGE"; then
  echo "warning: could not pull ${IMAGE}; using cached image if available." >&2
  docker image inspect "$IMAGE" >/dev/null 2>&1 || {
    echo "error: no cached ${IMAGE} to fall back to." >&2; exit 1
  }
fi
# One-shot self-heal: seed the output-savings baseline so the dashboard can
# measure reduction immediately (without it the dashboard shows "run headroom
# learn --verbosity to start measuring"). Runs only when the baseline is
# missing — a fresh or wiped volume — so normal restarts skip it. Reads Claude
# Code transcripts (mounted read-only) and is best-effort: never blocks startup.
if ! docker run --rm -v headroom-memory:/root/.headroom \
     --entrypoint sh "$IMAGE" -c 'test -f /root/.headroom/output_savings.json' 2>/dev/null; then
  echo "Seeding output-savings baseline (first run)…"
  docker run --rm \
    -v "${HOME}/.claude:/root/.claude:ro" \
    -v headroom-memory:/root/.headroom \
    --entrypoint headroom "$IMAGE" \
    learn --verbosity --apply --all \
    || echo "warning: baseline seed skipped (no transcripts to learn from)." >&2
fi

# Telemetry, code-aware, memory, and the dashboard live-message feed are all
# enabled by the image entrypoint. The named volume persists memory + savings
# across restarts (Headroom writes them under /root/.headroom).
docker run --rm -p "${PORT}:8787" \
  -e HEADROOM_TELEMETRY=on \
  -e HEADROOM_CODE_AWARE_ENABLED=1 \
  -e HEADROOM_OUTPUT_SHAPER=1 \
  -e HEADROOM_VERBOSITY_LEVEL="${VERBOSITY_LEVEL}" \
  -e HEADROOM_MEMORY_DB_PATH=/root/.headroom/memory.db \
  -e HEADROOM_PUBLIC_PORT="${PORT}" \
  -e HEADROOM_HTTP2="${HEADROOM_HTTP2:-0}" \
  -v headroom-memory:/root/.headroom \
  -v "${HOME}/.claude:/root/.claude:ro" \
  "$IMAGE"
