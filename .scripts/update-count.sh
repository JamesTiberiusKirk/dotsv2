#!/usr/bin/env bash

set -euo pipefail

# One copy per user: hyprx starts this on every login and the loop never
# exits, so without the lock each Hyprland restart stacked another (3 were
# running on 2026-10-01).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/update-count.lock"
flock -n 9 || exit 0

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
