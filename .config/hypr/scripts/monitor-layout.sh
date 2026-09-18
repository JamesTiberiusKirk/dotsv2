#!/usr/bin/env bash
# Detect connected outputs and apply the matching layout via hyprctl.
#
# Layouts are keyed by profile: the sorted, comma-separated list of connected
# output names. A saved profile in $STORE wins over the built-in cases below,
# so a new setup is arranged visually (wdisplays, `display/arrange` in the
# menu) and frozen with `monitor-layout.sh save` — no editing this file.
#
# Called at startup from base.lua and on every hotplug by monitor-watch.sh.
# `hyprctl reload` is NOT enough — it re-runs hosts/<host>.lua, not this.
set -u

STORE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/layouts"
OVERRIDE="${XDG_STATE_HOME:-$HOME/.local/state}/duo/screen-override"

MONS=$(hyprctl monitors -j 2>/dev/null) || exit 0
HOST=${HOSTNAME:-$(cat /etc/hostname)}

# Sorted, comma-separated list of currently connected output names.
profile=$(printf '%s' "$MONS" | jq -r '[.[].name] | sort | join(",")')

# The lua config parser rejects `hyprctl keyword`, so rules go through eval.
apply() {
    for line in "$@"; do
        IFS=, read -r out mode pos scale transform <<<"$line"
        # duo(1) owns eDP-2 on the Duo and latches a manual `duo screen off` in
        # this file. Replaying a saved profile forces disabled=false, which
        # switched the panel back on behind duo's back — it turned it off again
        # a few seconds later, the watcher saw monitorremoved and replayed
        # again, and the two flipped the screen forever.
        if [ "$out" = eDP-2 ] && [ "$(cat "$OVERRIDE" 2>/dev/null)" = off ]; then
            continue
        fi
        # disabled=false matters: a rule without it won't revive a disabled output
        hyprctl eval "hl.monitor({ output = \"$out\", mode = \"$mode\", position = \"$pos\", scale = $scale, transform = ${transform:-0}, disabled = false }) return \"\"" >/dev/null
    done
}

# Live scale change for one output, then re-save the profile so the next
# hotplug replays it instead of resetting the panel. Re-execs for the save:
# $MONS above is a snapshot taken before the change, so saving in this same
# process would persist the scale we just replaced.
if [ "${1:-}" = scale ]; then
    line=$(printf '%s' "$MONS" |
        jq -r --arg o "${2:-}" --arg s "${3:-}" \
            '.[]|select(.name==$o)|"\(.name),\(.width)x\(.height)@\(.refreshRate|floor),\(.x)x\(.y),\($s),\(.transform)"')
    [ -n "$line" ] || { echo "no such output: ${2:-}" >&2; exit 1; }
    apply "$line"
    # the modeset is not instant; without the wait the re-read in `save` can
    # still report the old scale and write it straight back
    sleep 0.5
    exec "$0" save
fi

# Freeze whatever is on screen right now as this profile's layout. Snapshots
# the compositor rather than parsing anyone's config, so any editor that
# applies live (wdisplays, nwg-displays) is a valid front-end. Disabled outputs
# are absent from `hyprctl monitors`, which is what we want: eDP-2 off is a
# different profile, not this one with a hole in it.
if [ "${1:-}" = save ]; then
    mkdir -p "$STORE"
    printf '%s' "$MONS" |
        jq -r '.[] | "\(.name),\(.width)x\(.height)@\(.refreshRate|floor),\(.x)x\(.y),\(.scale),\(.transform)"' \
        >"$STORE/$profile"
    echo "saved $STORE/$profile"
    exit 0
fi

if [ -f "$STORE/$profile" ]; then
    mapfile -t saved <"$STORE/$profile"
    apply "${saved[@]}"
    exit 0
fi

case "$profile" in
    "DP-1,DP-2,DP-3,HDMI-A-1")
        # deathstar — 4-monitor desktop layout.
        # Mapped from autorandr's X11 connector names to Hyprland's names:
        # DP-0 -> DP-1, DP-3 -> DP-2, DP-5 -> DP-3, HDMI-0 -> HDMI-A-1
        apply \
            "DP-2,1920x1080@60,2240x0,1" \
            "DP-3,1920x1080@60,0x1080,1" \
            "DP-1,2560x1440@144,1920x1080,1" \
            "HDMI-A-1,preferred,4480x1080,1"
        ;;
    "eDP-1,eDP-2")
        # binstar — Zenbook Duo stacked panels (duo(1) handles dock/undock)
        apply \
            "eDP-1,2880x1800@120,0x0,1.5" \
            "eDP-2,2880x1800@120,0x1200,1.5"
        ;;
    "eDP-1")
        # binstar with the bottom panel off shares dellstar/legion's profile
        # key but must keep its scale — a plain 1 here would shrink the UI.
        if [ "$HOST" = binstar ]; then
            apply "eDP-1,2880x1800@120,0x0,1.5"
        else
            apply "eDP-1,preferred,0x0,1"
        fi
        ;;
    *)
        # Unknown layout and nothing saved: let Hyprland auto-place each output.
        # Arrange it once and `save` to stop landing here.
        for name in $(printf '%s' "$MONS" | jq -r '.[].name'); do
            apply "$name,preferred,auto,1"
        done
        ;;
esac
