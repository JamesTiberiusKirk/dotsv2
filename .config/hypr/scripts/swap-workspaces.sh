#!/usr/bin/env bash
# Swap visible workspaces between focused monitor and the one in given direction.
# Usage: swap-workspaces.sh <left|right|up|down>
set -u

DIRECTION="${1:?Usage: $0 <left|right|up|down>}"

MONS=$(hyprctl monitors -j)

focused=$(printf '%s' "$MONS" | jq -r '.[] | select(.focused) | .name')
fx=$(printf '%s' "$MONS" | jq -r --arg n "$focused" '.[] | select(.name == $n) | (.x + .width / 2) | floor')
fy=$(printf '%s' "$MONS" | jq -r --arg n "$focused" '.[] | select(.name == $n) | (.y + .height / 2) | floor')

best_dist=999999
target=""

while IFS= read -r m; do
    [ "$m" = "$focused" ] && continue
    mx=$(printf '%s' "$MONS" | jq -r --arg n "$m" '.[] | select(.name == $n) | (.x + .width / 2) | floor')
    my=$(printf '%s' "$MONS" | jq -r --arg n "$m" '.[] | select(.name == $n) | (.y + .height / 2) | floor')
    dx=$((mx - fx)); dy=$((my - fy))
    adx=${dx#-}; ady=${dy#-}

    # Classify by dominant axis so a monitor mainly to the right but slightly
    # higher doesn't count as "up".
    if [ "$adx" -ge "$ady" ]; then
        if [ "$dx" -lt 0 ]; then dir="left"; else dir="right"; fi
        dist=$adx
    else
        if [ "$dy" -lt 0 ]; then dir="up"; else dir="down"; fi
        dist=$ady
    fi

    [ "$dir" != "$DIRECTION" ] && continue

    if [ "$dist" -lt "$best_dist" ]; then
        best_dist=$dist
        target=$m
    fi
done < <(printf '%s' "$MONS" | jq -r '.[].name')

[ -z "$target" ] && exit 0

hyprctl dispatch swapactiveworkspaces "$focused" "$target" >/dev/null
