#!/bin/sh

path=$HOME"/Pictures/screenshots/"
mkdir -p "$path"
timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(xdotool getactivewindow getwindowclassname 2>/dev/null || echo "unknown")

# Flameshot with auto-save to specific path and clipboard
flameshot gui --path "$path" --filename "${timestamp}-${active_window}"
