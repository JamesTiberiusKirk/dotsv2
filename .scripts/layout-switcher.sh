#!/usr/bin/env bash
# Per-workspace Hyprland layout switcher. Picks are persisted to
# ~/.config/hypr/.layout ("*=<global default>", "N=<override>"), which base.lua
# replays as workspace_rules on every reload/restart. Applied live via
# `hyprctl eval` (keyword no-ops under the lua config), so no reload needed.
set -u

LAYOUT_FILE="$HOME/.config/hypr/.layout"
WS_JSON=$(hyprctl activeworkspace -j)
WS=$(jq -r .id <<<"$WS_JSON")
CURRENT=$(jq -r .tiledLayout <<<"$WS_JSON")

MENU=$(cat <<'EOF'
dwindle — split the focused tile along its longest edge
master — one big master window, stacks on the sides
monocle — every window maximized, switch between them
scrolling — windows in a horizontal strip, pan across
lua:spiral — fibonacci spiral, each window splits the remainder
lua:grid — even grid of roughly square cells
lua:columns — equal-width side-by-side columns
default — clear override, follow global default
EOF
)

SELECTED=$(printf "%s\n" "$MENU" | ~/.scripts/qsmenu --prompt "Layout ws$WS (now: $CURRENT)")
[ -z "$SELECTED" ] && exit 0

LAYOUT=${SELECTED%% *} # strip the description
GLOBAL=$(sed -n 's/^\*=//p' "$LAYOUT_FILE" 2>/dev/null)
GLOBAL=${GLOBAL:-dwindle}

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
qs ipc call shell refreshLayout >/dev/null 2>&1 || true # bar shows tiledLayout; eval emits no event
