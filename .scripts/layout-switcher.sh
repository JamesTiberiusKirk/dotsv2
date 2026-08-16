#!/usr/bin/env bash
# Global Hyprland layout switcher. hyprctl keyword no-ops under the lua config,
# so we write the choice to ~/.config/hypr/.layout and reload (base.lua reads it).
set -u

LAYOUT_FILE="$HOME/.config/hypr/.layout"
CURRENT=$(cat "$LAYOUT_FILE" 2>/dev/null || echo dwindle)

MENU=$(cat <<'EOF'
dwindle — split the focused tile along its longest edge
master — one big master window, stacks on the sides
monocle — every window maximized, switch between them
scrolling — windows in a horizontal strip, pan across
EOF
)

SELECTED=$(printf "%s\n" "$MENU" | ~/.scripts/qsmenu --prompt "Layout (now: $CURRENT)")
[ -z "$SELECTED" ] && exit 0

LAYOUT=${SELECTED%% *} # strip the description
printf "%s" "$LAYOUT" > "$LAYOUT_FILE"
hyprctl reload
