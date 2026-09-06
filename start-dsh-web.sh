#!/usr/bin/env bash
#
# start-dsh-web.sh — start the DeepSeek Harness (dsh) web UI for remote
# access over Tailscale Serve, without touching dsh internals.
#
# Why this exists
#   dsh web binds to 127.0.0.1:3080 by design (the agent can run shell and
#   write files; the maintainers deliberately refuse --host 0.0.0.0). To use
#   the UI from your phone over Tailscale Serve, dsh must (a) still listen on
#   loopback and (b) tell the /api trust fence to accept the tailnet hostname.
#   This script does exactly that, using only official flags:
#       --trusted-host <ts-hostname>   allow the tailnet Origin/Host fence
#       --no-open                      don't try to open a local browser
#
# It prints:
#   - the local URL  (http://127.0.0.1:3080/?token=...) for on-machine use
#   - the phone URL  (https://<TS_HOSTNAME>/?token=...)   for FIRST phone visit
#
# The token exchange mints a signed cookie valid 30 days (persisted across
# dsh restarts). After the first visit, just open https://<TS_HOSTNAME>/
#
# Requirements
#   - dsh installed and on PATH
#   - Tailscale installed, logged in, MagicDNS enabled, `serve` mapped
#   - a trust config (see below)
#
# Usage
#   bash start-dsh-web.sh
#   TSSSL_HOST=... bash start-dsh-web.sh   # override the hostname on the fly
#
# Trust configuration
#   The script reads the tailnet hostname from, in order:
#     1. $DSH_TS_HOST          environment variable
#     2. ./local.conf          (KEY=VALUE, created at first run)
#     3. a dist error
#   Set it once via `bash start-dsh-web.sh --configure <hostname>` or by
#   editing local.conf. local.conf is gitignored.

set -euo pipefail

CONF_FILE="$(cd "$(dirname "$0")" && pwd)/local.conf"
LOG="${DSH_WEB_LOG:-/tmp/dsh-web.log}"
READY_TIMEOUT=20            # seconds to wait for the URL line

# ---- resolve hostname -------------------------------------------------------
TS_HOST=""
if [[ -n "${DSH_TS_HOST:-}" ]]; then
  TS_HOST="$DSH_TS_HOST"
elif [[ -f "$CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
fi

configure() {
  # persist the tailnet hostname into local.conf (gitignored)
  if [[ -z "${2:-}" ]]; then
    echo "Usage: bash start-dsh-web.sh --configure <ts-hostname>" >&2
    echo "e.g.   bash start-dsh-web.sh --configure 'node-abc123.tailXXXX.ts.net'" >&2
    exit 2
  fi
  printf 'DSH_TS_HOST=%s\n' "$2" > "$CONF_FILE"
  echo "Saved DSH_TS_HOST to $CONF_FILE"
  exit 0
}

if [[ "${1:-}" == "--configure" ]]; then configure "$@"; fi

if [[ -z "$TS_HOST" ]]; then
  echo "ERROR: tailnet hostname not set." >&2
  echo "  Run: bash start-dsh-web.sh --configure <ts-hostname>" >&2
  echo "  or:  export DSH_TS_HOST=<ts-hostname>" >&2
  exit 1
fi

# ---- stop a previous instance ---------------------------------------------
# pkill pattern is the full command line so we never match this script itself.
pkill -f "dsh web --trusted-host $TS_HOST" 2>/dev/null || true
sleep 1

# ---- start dsh web ----------------------------------------------------------
cd ~/.dsh
nohup dsh web --trusted-host "$TS_HOST" --no-open > "$LOG" 2>&1 &
echo "dsh web starting... (log: $LOG)"

# ---- wait for the printed URL (carries the launch token) --------------------
URL=""
for _ in $(seq 1 "$READY_TIMEOUT"); do
  URL=$(grep -o 'http://127.0.0.1:3080/?token=[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | head -1)
  [[ -n "$URL" ]] && break
  sleep 1
done

if [[ -n "$URL" ]]; then
  TOKEN="${URL#*token=}"
  echo
  echo "Local access : $URL"
  echo
  echo "Phone FIRST visit (exchanges token for a 30-day cookie):"
  echo "  https://$TS_HOST/?token=$TOKEN"
  echo
  echo "After that, just open:"
  echo "  https://$TS_HOST/"
else
  echo "ERROR: dsh web did not become ready in ${READY_TIMEOUT}s." >&2
  echo "--- log tail ---" >&2
  tail -n 20 "$LOG" 2>/dev/null >&2 || true
  exit 1
fi