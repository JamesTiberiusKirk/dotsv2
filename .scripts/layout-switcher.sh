#!/usr/bin/env bash
# Per-workspace Hyprland layout switcher. Picks are persisted to
# ~/.config/hypr/.layout ("*=<global default>", "N=<override>"), which base.lua
# replays as workspace_rules on every reload/restart. Applied live via
# `hyprctl eval` (keyword no-ops under the lua config), so no reload needed.
set -u

LAYOUT_FILE="$HOME/.config/hypr/.layout"
WS=$(hyprctl activeworkspace -j | jq -r .id)
GLOBAL=$(sed -n 's/^\*=//p' "$LAYOUT_FILE" 2>/dev/null)
GLOBAL=${GLOBAL:-dwindle}
# from the file, not hyprctl: hyprland's IPC misreports lua layout names
CURRENT=$(sed -n "s/^$WS=//p" "$LAYOUT_FILE" 2>/dev/null)
CURRENT=${CURRENT:-$GLOBAL}
CURRENT=${CURRENT#lua:}

MENU=$(cat <<'EOF'
dwindle — split the focused tile along its longest edge
master — one big master window, stacks on the sides
monocle — every window maximized, switch between them
scrolling — windows in a horizontal strip, pan across
spiral — fibonacci spiral, each window splits the remainder
grid — even grid of roughly square cells
columns — equal-width side-by-side columns
accordion:horizontal — overlapping stack, side peek strips, H/L to navigate
accordion:vertical — overlapping stack, top/bottom peek strips, J/K to navigate
default — clear override, follow global default
EOF
)

SELECTED=$(printf "%s\n" "$MENU" | ~/.scripts/qsmenu --prompt "Layout ws$WS (now: $CURRENT)")
[ -z "$SELECTED" ] && exit 0

LAYOUT=${SELECTED%% *} # strip the description
case $LAYOUT in # menu shows bare names; hyprland needs the lua: prefix back
    spiral|grid|columns|accordion:*) LAYOUT=lua:$LAYOUT ;;
esac

grep -v "^$WS=" "$LAYOUT_FILE" 2>/dev/null > "$LAYOUT_FILE.tmp" || true
if [ "$LAYOUT" = default ]; then
    APPLY=$GLOBAL
else
    APPLY=$LAYOUT
    echo "$WS=$LAYOUT" >> "$LAYOUT_FILE.tmp"
fi
grep -q '^\*=' "$LAYOUT_FILE.tmp" || echo "*=$GLOBAL" >> "$LAYOUT_FILE.tmp"
mv "$LAYOUT_FILE.tmp" "$LAYOUT_FILE"

hyprctl eval "hl.workspace_rule({ workspace = '$WS', layout = '$APPLY' })"
