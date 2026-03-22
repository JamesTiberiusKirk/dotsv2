#!/usr/bin/env bash

set -euo pipefail

target="1.1.1.1"
output_file="/tmp/i3status_latency"
interval=1

printf '%s\n' "n/a" > "$output_file"

while true; do
  if ping_output=$(ping -c 3 -W 1 "$target" 2>/dev/null); then
    avg=$(printf '%s\n' "$ping_output" | awk -F'=' '/rtt/{print $2}' | awk -F'/' '{print $2}')
    if [ -n "$avg" ]; then
      printf '%6.1f ms\n' "$avg" > "$output_file"
    else
      printf '%6s\n' "n/a" > "$output_file"
    fi
  else
    printf '%s\n' "down" > "$output_file"
  fi
  sleep "$interval"
done
