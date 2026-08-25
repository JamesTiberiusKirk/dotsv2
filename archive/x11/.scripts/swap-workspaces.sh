#!/bin/bash
# Swap visible workspaces between focused monitor and the one in a given direction
# Usage: swap-workspaces.sh <left|right|up|down>

DIRECTION="${1:?Usage: swap-workspaces.sh <left|right|up|down>}"

INFO=$(i3-msg -t get_outputs | jq '[.[] | select(.active)]')
WS_INFO=$(i3-msg -t get_workspaces)

# Get focused monitor name and center position
FOCUSED_OUT=$(echo "$WS_INFO" | jq -r '.[] | select(.focused) | .output')
FOCUSED_WS=$(echo "$WS_INFO" | jq -r '.[] | select(.focused) | .name')
FOCUSED_X=$(echo "$INFO" | jq -r ".[] | select(.name==\"$FOCUSED_OUT\") | (.rect.x + .rect.width/2) | floor")
FOCUSED_Y=$(echo "$INFO" | jq -r ".[] | select(.name==\"$FOCUSED_OUT\") | (.rect.y + .rect.height/2) | floor")

# Find the nearest monitor in the given direction
TARGET_OUT=""
BEST_DIST=999999

for OUT in $(echo "$INFO" | jq -r '.[].name'); do
    [ "$OUT" = "$FOCUSED_OUT" ] && continue
    OX=$(echo "$INFO" | jq -r ".[] | select(.name==\"$OUT\") | (.rect.x + .rect.width/2) | floor")
    OY=$(echo "$INFO" | jq -r ".[] | select(.name==\"$OUT\") | (.rect.y + .rect.height/2) | floor")

    DX=$((OX - FOCUSED_X))
    DY=$((OY - FOCUSED_Y))
    ABS_DX=${DX#-}
    ABS_DY=${DY#-}

    # Classify by dominant axis so a monitor that's mainly right
    # but slightly higher doesn't count as "up"
    if [ "$ABS_DX" -ge "$ABS_DY" ]; then
        if [ "$DX" -lt 0 ]; then DIR="left"; else DIR="right"; fi
        DIST=$ABS_DX
    else
        if [ "$DY" -lt 0 ]; then DIR="up"; else DIR="down"; fi
        DIST=$ABS_DY
    fi

    [ "$DIR" != "$DIRECTION" ] && continue

    if [ "$DIST" -lt "$BEST_DIST" ]; then
        BEST_DIST=$DIST
        TARGET_OUT=$OUT
    fi
done

[ -z "$TARGET_OUT" ] && exit 0

TARGET_WS=$(echo "$WS_INFO" | jq -r ".[] | select(.visible and .output==\"$TARGET_OUT\") | .name")
[ -z "$TARGET_WS" ] && exit 0

i3-msg "move workspace to output $TARGET_OUT; workspace $TARGET_WS; move workspace to output $FOCUSED_OUT; focus output $FOCUSED_OUT"
