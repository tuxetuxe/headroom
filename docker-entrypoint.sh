#!/bin/sh
# Entrypoint for the Headroom image.
#
# The dashboard's live-message feed (/transformations/feed) is loopback-only:
# the proxy serves it only when the request's peer IP is 127.0.0.1 (a defence
# against exposing prompt/response content over the network). Under
# `docker run -p`, host traffic reaches the container from the Docker gateway
# IP, so the feed 404s and the dashboard shows "No requests yet".
#
# Fix: bind Headroom to loopback INSIDE the container and relay the published
# port to it with socat. The proxy then sees every request as coming from
# 127.0.0.1, so the live feed works while the port is still reachable from the
# host.
set -eu

LISTEN_PORT=8787                                  # port published to the host
INTERNAL_PORT="${HEADROOM_INTERNAL_PORT:-8788}"   # loopback port Headroom binds

# --log-messages is required for the live feed to carry request/response bodies.
# WARNING: it stores prompt + completion content on disk. Fine for local use;
# do not enable on a shared/exposed instance.
headroom proxy \
  --host 127.0.0.1 --port "$INTERNAL_PORT" \
  --memory --log-messages "$@" &
HR_PID=$!

socat "TCP-LISTEN:${LISTEN_PORT},fork,reuseaddr" "TCP:127.0.0.1:${INTERNAL_PORT}" &
SOCAT_PID=$!

# Tell the user which port to actually use. The proxy's own banner prints the
# internal loopback listener (127.0.0.1:8788); this is the reachable one.
# HEADROOM_PUBLIC_PORT is the host port the run script mapped (default 8787).
PUBLIC_PORT="${HEADROOM_PUBLIC_PORT:-$LISTEN_PORT}"
( sleep 3
  echo ""
  echo "========================================================================"
  echo "  Headroom is ready — use port ${PUBLIC_PORT} (ignore the 127.0.0.1:${INTERNAL_PORT} above)"
  echo ""
  echo "  Proxy:      http://localhost:${PUBLIC_PORT}"
  echo "  Dashboard:  http://localhost:${PUBLIC_PORT}/dashboard"
  echo "  Claude Code: ANTHROPIC_BASE_URL=http://localhost:${PUBLIC_PORT} claude"
  echo "========================================================================"
  echo ""
) &

# Stop both halves together on Ctrl+C / docker stop.
term() { kill "$HR_PID" "$SOCAT_PID" 2>/dev/null || true; }
trap term TERM INT
wait
