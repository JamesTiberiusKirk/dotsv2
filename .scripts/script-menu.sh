#!/usr/bin/env bash
# Headless script menu (SUPER+CTRL+R).
#
# Lists every executable in ~/.scripts/menu/common/ (all hosts) and
# ~/.scripts/menu/<hostname>/ (this host only), shows them in a wofi picker,
# and runs the chosen one. Drop a new executable into either dir and it shows
# up automatically — no edits here.
set -u
shopt -s nullglob

# `hostname` isn't installed here; mirror hyprland.lua's resolution.
host="${HOSTNAME:-$(uname -n)}"; host="${host%%.*}"
dirs=("$HOME/.scripts/menu/common" "$HOME/.scripts/menu/$host")

declare -A items=()
for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        label=$(basename "$f"); label=${label%.sh}
        items["$label"]="$f"   # host dir scanned last, so it wins on name clash
    done
done

if [ ${#items[@]} -eq 0 ]; then
    notify-send "script-menu" "no executables in ~/.scripts/menu/{common,$host}"
    exit 0
fi

choice=$(printf '%s\n' "${!items[@]}" | sort | wofi --dmenu --prompt "Run script" --width 500 --height 400)
[ -n "$choice" ] || exit 0

target=${items["$choice"]:-}
[ -n "$target" ] || exit 0

# Run detached; surface result via notification since there's no terminal.
if out=$("$target" 2>&1); then
    notify-send "script-menu: $choice" "${out:-done}"
else
    notify-send -u critical "script-menu: $choice failed" "${out:-see logs}"
fi
