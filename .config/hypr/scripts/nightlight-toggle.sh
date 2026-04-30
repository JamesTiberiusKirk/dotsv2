#!/usr/bin/env bash
# Toggle hyprsunset on/off. Mirrors the start-or-kill shape of redshift-toggle.
# Usage: nightlight-toggle.sh [TEMP_K]   (default 3500)
set -u

TEMP="${1:-3500}"

if pgrep -x hyprsunset >/dev/null 2>&1; then
    pkill -x hyprsunset >/dev/null 2>&1 || true
    exit 0
fi

if ! command -v hyprsunset >/dev/null 2>&1; then
    notify-send "hyprsunset not installed" >/dev/null 2>&1 || true
    exit 1
fi

nohup hyprsunset -t "$TEMP" >/dev/null 2>&1 &
