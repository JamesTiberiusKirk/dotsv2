#!/usr/bin/env bash
# Global Hyprland layout switcher. hyprctl keyword no-ops under the lua config,
# so we write the choice to ~/.config/hypr/.layout and reload (base.lua reads it).
set -u

LAYOUT_FILE="$HOME/.config/hypr/.layout"
CURRENT=$(cat "$LAYOUT_FILE" 2>/dev/null || echo dwindle)

SELECTED=$(printf "dwindle\nmaster" \
    | wofi --dmenu --prompt "Layout (now: $CURRENT)")

[ -z "$SELECTED" ] && exit 0

printf "%s" "$SELECTED" > "$LAYOUT_FILE"
hyprctl reload
