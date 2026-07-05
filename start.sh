#!/bin/bash
set -e

# Pull the latest base image, then build a thin image on top that adds the
# "code" + "memory" extras and the loopback relay for the live-message feed.
docker pull ghcr.io/chopratejas/headroom:latest
docker build -t headroom-local .

# Output-shaper verbosity level (0-4) applied to ALL projects. Overrides the
# per-project levels from `headroom learn --verbosity`. Override per-run with:
# HEADROOM_VERBOSITY_LEVEL=1 ./start.sh
VERBOSITY_LEVEL="${HEADROOM_VERBOSITY_LEVEL:-2}"

# One-shot self-heal: seed the output-savings baseline so the dashboard can
# measure reduction immediately (without it the dashboard shows "run headroom
# learn --verbosity to start measuring"). Runs only when the baseline is
# missing — a fresh or wiped volume — so normal restarts skip it. Reads Claude
# Code transcripts (mounted read-only) and is best-effort: never blocks startup.
if ! docker run --rm -v headroom-memory:/root/.headroom \
     --entrypoint sh headroom-local -c 'test -f /root/.headroom/output_savings.json' 2>/dev/null; then
  echo "Seeding output-savings baseline (first run)…"
  docker run --rm \
    -v "${HOME}/.claude:/root/.claude:ro" \
    -v headroom-memory:/root/.headroom \
    --entrypoint headroom headroom-local \
    learn --verbosity --apply --all \
    || echo "warning: baseline seed skipped (no transcripts to learn from)." >&2
fi

# Telemetry, code-aware, memory, and the dashboard live-message feed are all
# enabled by the image entrypoint. The named volume persists memory + savings
# across restarts (Headroom writes them under /root/.headroom).
docker run -p 8787:8787 \
  -e HEADROOM_VERBOSITY_LEVEL="${VERBOSITY_LEVEL}" \
  -e HEADROOM_TELEMETRY=on \
  -e HEADROOM_CODE_AWARE_ENABLED=1 \
  -e HEADROOM_OUTPUT_SHAPER=1 \
  -e HEADROOM_MEMORY_DB_PATH=/root/.headroom/memory.db \
  -e HEADROOM_PUBLIC_PORT=8787 \
  -e HEADROOM_HTTP2="${HEADROOM_HTTP2:-0}" \
  -v headroom-memory:/root/.headroom \
  -v "${HOME}/.claude:/root/.claude:ro" \
  headroom-local
