#!/bin/sh
# Region screenshot → satty annotation window → save + clipboard on exit.

path="$HOME/Pictures/screenshots"
mkdir -p "$path"

timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(hyprctl activewindow -j 2>/dev/null | grep -oP '"class"\s*:\s*"\K[^"]+')
out="${path}/${timestamp}-${active_window:-screenshot}.png"

region=$(slurp) || exit 0
grim -g "$region" - | satty \
    --filename - \
    --output-filename "$out" \
    --early-exit \
    --copy-command wl-copy
