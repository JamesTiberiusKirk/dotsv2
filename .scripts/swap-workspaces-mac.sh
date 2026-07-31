#!/usr/bin/env bash
# Swap visible workspaces between the focused monitor and the one in the given
# direction. Focus stays on the original monitor after the swap.
# Usage: swap-workspaces-mac.sh <left|right|up|down>
set -euo pipefail

DIRECTION="${1:?Usage: $0 <left|right|up|down>}"

focused_mon=$(aerospace list-monitors --focused --format "%{monitor-id}")
ws_a=$(aerospace list-workspaces --monitor focused --visible)

aerospace focus-monitor "$DIRECTION" || true
other_mon=$(aerospace list-monitors --focused --format "%{monitor-id}")

# No monitor in that direction: focus-monitor was a no-op.
if [ "$other_mon" = "$focused_mon" ]; then
    exit 0
fi

ws_b=$(aerospace list-workspaces --monitor focused --visible)

aerospace move-workspace-to-monitor "$focused_mon"
aerospace workspace "$ws_a"
aerospace move-workspace-to-monitor "$other_mon"
aerospace workspace "$ws_b"
