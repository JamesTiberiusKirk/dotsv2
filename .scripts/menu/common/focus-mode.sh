#!/usr/bin/env bash
# Toggle focus mode: big left/right gaps. hyprctl keyword no-ops under the
# lua config, so we toggle ~/.config/hypr/.focus and reload (base.lua reads it).
set -u

FOCUS_FILE="$HOME/.config/hypr/.focus"
if [ -e "$FOCUS_FILE" ]; then
    rm "$FOCUS_FILE"
    echo "focus mode off"
else
    touch "$FOCUS_FILE"
    echo "focus mode on"
fi
hyprctl reload
