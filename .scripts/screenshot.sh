#!/bin/sh

path=$HOME"/Pictures/screenshots/"
mkdir -p "$path"
timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(hyprctl activewindow -j | grep -oP '"class"\s*:\s*"\K[^"]+')
out="${path}/${timestamp}-${active_window}.png"

slurp | grim -g - $out
wl-copy < $out
