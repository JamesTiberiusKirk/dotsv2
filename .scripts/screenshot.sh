#!/bin/sh
# Freeze screen (wayfreeze) → region (slurp) → grim → satty annotation window → save + clipboard on exit.

path="$HOME/Pictures/screenshots"
mkdir -p "$path"

timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(hyprctl activewindow -j 2>/dev/null | grep -oP '"class"\s*:\s*"\K[^"]+')
out="${path}/${timestamp}-${active_window:-screenshot}.png"

tmp=$(mktemp --suffix=.png)
wayfreeze --hide-cursor --after-freeze-cmd "region=\$(slurp) && grim -g \"\$region\" '$tmp'; pkill wayfreeze"
[ -s "$tmp" ] || { rm -f "$tmp"; exit 0; }

satty \
    --filename "$tmp" \
    --output-filename "$out" \
    --early-exit \
    --copy-command wl-copy
rm -f "$tmp"
