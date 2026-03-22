#!/usr/bin/env bash

set -euo pipefail

output_file="/tmp/i3status_updates"
interval=3600

printf '%s\n' "n/a" > "$output_file"

while true; do
  if ! command -v yay >/dev/null 2>&1; then
    printf '%s\n' "n/a" > "$output_file"
  else
    if updates=$(timeout 120 yay -Qu 2>/dev/null); then
      count=$(printf '%s\n' "$updates" | awk 'NF{c++} END{print c+0}')
      printf '%s\n' "$count" > "$output_file"
    else
      printf '%s\n' "err" > "$output_file"
    fi
  fi
  sleep "$interval"
done
