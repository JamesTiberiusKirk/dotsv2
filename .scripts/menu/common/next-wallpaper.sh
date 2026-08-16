#!/usr/bin/env bash
# Cycle to the next wallpaper in ~/Pictures/wallpapers (ordered, wraps around).
# Applied via hyprpaper IPC; position kept in a state file.
# --current: re-apply the current one without advancing (used at autostart).
set -u

DIR="$HOME/Pictures/wallpapers"
STATE_DIR="$HOME/.local/state"
STATE="$STATE_DIR/wallpaper-index"
mkdir -p "$STATE_DIR"

mapfile -t WALLS < <(find "$DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort)

if [ ${#WALLS[@]} -eq 0 ]; then
    notify-send "wallpaper" "no images in $DIR"
    exit 0
fi

IDX=$(cat "$STATE" 2>/dev/null || echo 0)
if [ "${1:-}" != "--current" ]; then
    IDX=$(( (IDX + 1) % ${#WALLS[@]} ))
    printf "%s" "$IDX" > "$STATE"
fi
# clamp in case the collection shrank since last run
[ "$IDX" -ge ${#WALLS[@]} ] && IDX=0

pgrep -x hyprpaper >/dev/null || { hyprpaper >/dev/null 2>&1 & disown; sleep 1; }

hyprctl hyprpaper wallpaper ,"${WALLS[$IDX]}" >/dev/null
