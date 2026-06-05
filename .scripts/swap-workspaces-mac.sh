#!/usr/bin/env bash
# Swap visible workspaces between focused monitor and the next one (wraps around).
# Focus stays on the original monitor after the swap.
set -euo pipefail

ws_a=$(aerospace list-workspaces --monitor focused --visible)

mon_ids=()
while read -r line; do
    mon_ids+=("$(echo "$line" | awk '{print $1}')")
done < <(aerospace list-monitors)

total=${#mon_ids[@]}
[ "$total" -lt 2 ] && exit 0

focused_idx=0
for i in "${!mon_ids[@]}"; do
    ws=$(aerospace list-workspaces --monitor "${mon_ids[$i]}" --visible)
    if [ "$ws" = "$ws_a" ]; then
        focused_idx=$i
        break
    fi
done

focused_mon=${mon_ids[$focused_idx]}
next_idx=$(( (focused_idx + 1) % total ))
other_mon=${mon_ids[$next_idx]}
ws_b=$(aerospace list-workspaces --monitor "$other_mon" --visible)

aerospace workspace "$ws_b"
aerospace move-workspace-to-monitor "$focused_mon"
aerospace workspace "$ws_a"
aerospace move-workspace-to-monitor "$other_mon"
aerospace workspace "$ws_b"
