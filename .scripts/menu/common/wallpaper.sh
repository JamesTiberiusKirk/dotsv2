#!/usr/bin/env bash
# Wallpapers in ~/Pictures/wallpapers. Applied via awww (formerly swww);
# position kept in a state file so the picker and the cycler agree.
#   (no args) : open the quickshell picker
#   --next    : advance one (wraps around)
#   --current : re-apply the current one, no animation (autostart)
#   --random  : jump to a random one
#   <path>    : apply that file
# menu-icon: image-multiple
set -u

DIR="$HOME/Pictures/wallpapers"
STATE_DIR="$HOME/.local/state"
STATE="$STATE_DIR/wallpaper-index"
mkdir -p "$STATE_DIR"

# Transition knob. swww types: grow | wipe | outer | fade | wave | random | none.
# `grow` blooms out from the cursor, which is why --transition-pos is fed
# hyprctl cursorpos below. Override per-invocation with WALL_TRANSITION=wipe.
TRANSITION="${WALL_TRANSITION:-grow}"
DURATION="${WALL_DURATION:-1.2}"
FPS="${WALL_FPS:-60}"

# no args is the picker; everything else applies something. Bail before the
# find so opening the picker costs nothing.
if [ $# -eq 0 ]; then
    exec qs ipc call wallpaper toggle
fi

mapfile -t WALLS < <(find "$DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort)

if [ ${#WALLS[@]} -eq 0 ]; then
    notify-send "wallpaper" "no images in $DIR"
    exit 0
fi

IDX=$(cat "$STATE" 2>/dev/null || echo 0)
case "$1" in
    --current) ;;
    --random)  IDX=$(( RANDOM % ${#WALLS[@]} )); printf "%s" "$IDX" > "$STATE" ;;
    --next)    IDX=$(( (IDX + 1) % ${#WALLS[@]} )); printf "%s" "$IDX" > "$STATE" ;;
    *)
        # an explicit path from the picker: find its slot so --next resumes from
        # here rather than from wherever the cycler last was
        for i in "${!WALLS[@]}"; do
            [ "${WALLS[$i]}" = "$1" ] && IDX=$i && break
        done
        printf "%s" "$IDX" > "$STATE"
        ;;
esac
# clamp in case the collection shrank since last run
[ "$IDX" -ge ${#WALLS[@]} ] && IDX=0

# upstream renamed swww -> awww; hosts on older repos still have the old name
BIN=$(command -v awww || command -v swww) || {
    notify-send "wallpaper" "awww not installed"; exit 1
}
# the daemon must be up before `img`; it has no autospawn
if ! "$BIN" query >/dev/null 2>&1; then
    "${BIN}-daemon" >/dev/null 2>&1 & disown
    for _ in $(seq 20); do "$BIN" query >/dev/null 2>&1 && break; sleep 0.1; done
fi

ARGS=(--transition-type "$TRANSITION" --transition-duration "$DURATION" --transition-fps "$FPS")
if [ "$1" = "--current" ]; then
    # animating the very first paint just shows the transition against a black
    # screen, so the autostart path swaps in cold
    ARGS=(--transition-type none)
elif [ "$TRANSITION" = "grow" ] || [ "$TRANSITION" = "outer" ]; then
    # hyprctl reports "x, y" from the top-left; swww counts from the bottom-left
    POS=$(hyprctl cursorpos 2>/dev/null | tr -d ' ')
    [ -n "$POS" ] && ARGS+=(--transition-pos "$POS" --invert-y)
fi

"$BIN" img "${ARGS[@]}" -- "${WALLS[$IDX]}" >/dev/null

# "wallpaper" is a theme like any other (themes/wallpaper.json), regenerated
# from every applied picture so the picker card previews it; re-applied only
# when it is the theme in use
if command -v matugen >/dev/null && "$HOME/.scripts/theme-from-wallpaper" "${WALLS[$IDX]}"; then
    [ "$(python3 -c 'import json;print(json.load(open("'"$HOME"'/.theme.json"))["name"])' 2>/dev/null)" = wallpaper ] \
        && "$HOME/.scripts/theme-apply" wallpaper >/dev/null
fi
# caption widget (quickshell wallpaper/Info.qml) re-reads awww query
qs ipc call wallinfo refresh >/dev/null 2>&1
