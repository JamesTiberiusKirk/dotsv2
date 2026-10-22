#!/bin/sh
# Toggle a region recording. First run: pick a box (quickshell RegionPicker), wl-screenrec
# records it. Second run: stop.
#   record.sh [mp4|gif] [pulse source...]
# gif also turns the clip into a gif. Sources (e.g. "<sink>.monitor" for desktop sound,
# a mic's source name) are recorded as audio; several get mixed into one track.

dir="$HOME/Videos/recordings"
state="${XDG_RUNTIME_DIR:-/tmp}/record.state"

# --run <geom>: the picker's callback, once a box is picked. Owns the recorder's
# lifetime so the bar cell and the audio mix are torn down however it exits.
if [ "$1" = --run ]; then
    geom="$2"
    read -r mode file sources < "$state"
    set -- $sources
    mods=""
    if [ $# -eq 1 ]; then
        audio="$1"
    elif [ $# -gt 1 ]; then
        # wl-screenrec takes one device: loop every source into a throwaway null sink
        # and record its monitor
        mods=$(pactl load-module module-null-sink sink_name=rec-mix sink_properties=device.description=rec-mix)
        for s; do
            mods="$mods $(pactl load-module module-loopback source="$s" sink=rec-mix latency_msec=20)"
        done
        audio=rec-mix.monitor
    fi
    qs ipc call region recStart "$mode"
    wl-screenrec -g "$geom" -f "$file" ${audio:+--audio --audio-device "$audio"} 2>"$state.log"
    qs ipc call region recStop
    for m in $mods; do pactl unload-module "$m"; done
    exit 0
fi

if pkill -INT -x wl-screenrec; then
    # SIGINT makes wl-screenrec finalise the mp4; wait for it
    while pgrep -x wl-screenrec >/dev/null; do sleep 0.1; done
    read -r mode file _ < "$state"
    rm -f "$state"
    if [ "$mode" = gif ]; then
        gif="${file%.mp4}.gif"
        notify-send -a record "Making gif..."
        ffmpeg -loglevel error -y -i "$file" \
            -vf "fps=15,scale='min(iw,960)':-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" \
            "$gif" && rm -f "$file" && file="$gif"
    fi
    notify-send -a record "Recording saved" "$file"
    exit 0
fi

mode="${1:-mp4}"
[ $# -gt 0 ] && shift
[ "$mode" = gif ] && set --   # gifs have no sound
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d-%H:%M:%S).mp4"
echo "$mode $file $*" > "$state"
qs ipc call region pickOne "[ -n \"\$1\" ] && exec '$0' --run \"\$1\""
