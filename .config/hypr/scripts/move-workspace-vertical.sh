#!/usr/bin/env bash
# Move the current workspace to the vertically-adjacent monitor.
# Goes up if a monitor sits above the focused one, otherwise down.
# A 2-row toggle: from a top monitor it descends, from a bottom one it ascends.
set -u

MONS=$(hyprctl monitors -j)

focused=$(printf '%s' "$MONS" | jq -r '.[] | select(.focused) | .name')
fx=$(printf '%s' "$MONS" | jq -r --arg n "$focused" '.[] | select(.name == $n) | (.x + .width / 2) | floor')
fy=$(printf '%s' "$MONS" | jq -r --arg n "$focused" '.[] | select(.name == $n) | (.y + .height / 2) | floor')

up_dist=999999;   up_target=""
down_dist=999999; down_target=""

while IFS= read -r m; do
    [ "$m" = "$focused" ] && continue
    mx=$(printf '%s' "$MONS" | jq -r --arg n "$m" '.[] | select(.name == $n) | (.x + .width / 2) | floor')
    my=$(printf '%s' "$MONS" | jq -r --arg n "$m" '.[] | select(.name == $n) | (.y + .height / 2) | floor')
    dx=$((mx - fx)); dy=$((my - fy))
    adx=${dx#-}; ady=${dy#-}

    # Only vertically-dominant neighbours count, so a monitor mainly to the side
    # but slightly higher/lower isn't treated as up/down.
    [ "$ady" -le "$adx" ] && continue

    if [ "$dy" -lt 0 ]; then
        [ "$ady" -lt "$up_dist" ]   && { up_dist=$ady;   up_target=$m; }
    else
        [ "$ady" -lt "$down_dist" ] && { down_dist=$ady; down_target=$m; }
    fi
done < <(printf '%s' "$MONS" | jq -r '.[].name')

# Prefer up; fall back to down. Gives the toggle between two stacked rows.
target="${up_target:-$down_target}"
[ -z "$target" ] && exit 0

# Hyprland 0.55 lua config reinterprets `dispatch <classic>` as Lua, so use the
# Lua dispatcher form (matches swap-workspaces.sh).
hyprctl dispatch "hl.dsp.workspace.move({monitor=\"$target\"})" >/dev/null
