#!/usr/bin/env bash

set -euo pipefail

output_file="/tmp/i3status_updates"
interval=3600

printf '%s\n' "n/a" > "$output_file"

while true; do
  if ! command -v yay >/dev/null 2>&1; then
    printf '%s\n' "n/a" > "$output_file"
  else
    updates=$(timeout 120 command yay -Qu 2>/dev/null) || true
    count=$(printf '%s\n' "$updates" | awk 'NF{c++} END{print c+0}')
    printf '%s\n' "$count" > "$output_file"
  fi
  sleep "$interval"
done
