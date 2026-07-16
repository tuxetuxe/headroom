#!/bin/bash
set -e

# Build the image directly from a clean Python base + the latest headroom-ai
# wheel from PyPI (no dependency on the infrequently-republished upstream image).
#
# Resolve the newest headroom-ai version and pass it as a build arg. This is the
# cache-bust: when the version is unchanged the pip layer stays cached (fast
# rebuild); when upstream releases a new version the arg changes and only the
# affected layers rebuild. Override/pin with:  HEADROOM_VERSION=0.30.0 ./start.sh
# If the lookup fails (e.g. offline), fall back to "latest" (empty arg), which
# builds fresh or reuses whatever is cached.
if [ -z "${HEADROOM_VERSION:-}" ]; then
  HEADROOM_VERSION="$(curl -fsSL https://pypi.org/pypi/headroom-ai/json 2>/dev/null \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null || true)"
fi
if [ -n "${HEADROOM_VERSION}" ]; then
  echo "Building headroom-local with headroom-ai==${HEADROOM_VERSION}"
else
  echo "warning: could not resolve latest headroom-ai version; building with latest/cached." >&2
fi
docker build --build-arg HEADROOM_VERSION="${HEADROOM_VERSION}" -t headroom-local .

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
