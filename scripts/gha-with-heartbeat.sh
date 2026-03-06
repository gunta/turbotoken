#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: gha-with-heartbeat.sh <command> [args...]" >&2
  exit 64
fi

interval="${GHA_HEARTBEAT_INTERVAL_SECONDS:-55}"
label="${GHA_HEARTBEAT_LABEL:-$1}"

heartbeat() {
  while true; do
    sleep "$interval"
    printf '[heartbeat][%s] %s still running\n' "$(date -u +%FT%TZ)" "$label"
  done
}

heartbeat &
heartbeat_pid=$!

cleanup() {
  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

"$@"
