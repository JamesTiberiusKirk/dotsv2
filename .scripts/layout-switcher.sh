#!/usr/bin/env bash
# Per-workspace Hyprland layout switcher. hyprctl keyword no-ops under the lua
# config, but `hyprctl eval` runs lua live in the compositor, so we set a
# workspace_rule for the focused workspace only. In-memory: resets on reload.
set -u

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
EOF
)

SELECTED=$(printf "%s\n" "$MENU" | ~/.scripts/qsmenu --prompt "Layout ws$WS (now: $CURRENT)")
[ -z "$SELECTED" ] && exit 0

LAYOUT=${SELECTED%% *} # strip the description
hyprctl eval "hl.workspace_rule({ workspace = '$WS', layout = '$LAYOUT' })"
qs ipc call shell refreshLayout >/dev/null 2>&1 || true # bar shows tiledLayout; eval emits no event
