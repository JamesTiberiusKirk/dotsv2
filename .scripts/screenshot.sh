#!/bin/sh
# Freeze screen (wayfreeze) → region (quickshell RegionPicker, runs grim) → satty annotation window → save + clipboard on exit.

path="$HOME/Pictures/screenshots"
mkdir -p "$path"

timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(hyprctl activewindow -j 2>/dev/null | grep -oP '"class"\s*:\s*"\K[^"]+')
out="${path}/${timestamp}-${active_window:-screenshot}.png"

tmp=$(mktemp --suffix=.png)
# wayfreeze unfreezes when its cmd exits; the IPC call returns at once, so sleep and let
# the picker's callback pkill wayfreeze. 120s caps a stuck freeze if the shell is dead.
export GRAB="[ -n \"\$1\" ] && grim -g \"\$1\" '$tmp'; pkill wayfreeze"
wayfreeze --hide-cursor --after-freeze-cmd "qs ipc call region pick \"\$GRAB\" && sleep 120"
[ -s "$tmp" ] || { rm -f "$tmp"; exit 0; }

satty \
    --filename "$tmp" \
    --output-filename "$out" \
    --early-exit \
    --disable-notifications \
    --copy-command wl-copy
rm -f "$tmp"
