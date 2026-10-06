#!/usr/bin/env bash
# Detect connected outputs and apply the matching layout via hyprctl.
#
# Layouts are keyed by profile: the sorted, comma-separated list of outputs the
# kernel reports as *connected* — not the ones currently lit. Keying on lit
# outputs made desired state a function of current state: turning the sub screen
# off changed the profile, which applied a different layout, which rescaled the
# main screen and moved the external one. On/off is now a state inside a
# profile, never a profile switch.
#
# Reading the kernel also means a ghost output (hyprctl claims it is there, the
# connector says `disconnected`) stops counting as present.
#
# Two paths. Hosts whose config loads monitors.lua (binstar) take the block
# right after the lock: monitors.lua owns every rule, profiles are keyed by
# monitor identity, and this script only edits saved layouts and re-runs it.
# Every other host takes the old path below: profiles keyed by connector, rules
# applied here by eval, and a saved profile in $STORE wins over the built-in
# cases.
#
# Called at startup from base.lua, on every hotplug by monitor-watch.sh, after
# sleep and screen-off by hypridle (scripts/idle), and by the display popout's
# scale pills / the menu's "save arrangement".
set -u

STORE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/layouts"

mkdir -p "$STORE"

# Serialise every writer: the hotplug watcher, idle's on-resume call, base.lua
# at startup, Sys.qml's scale pills and Menu.qml's save can all land at once,
# and two interleaved applies leave the outputs half-moved.
exec 9>"$STORE/.lock"
flock 9

MONS=$(hyprctl monitors -j 2>/dev/null) || exit 0
HOST=${HOSTNAME:-$(cat /etc/hostname)}

# Hosts whose config loads monitors.lua: that file is the only thing that turns
# state into monitor rules, so this script just edits the saved layout and
# re-runs it. Profiles there are keyed by monitor identity (EDID), not port.
# Everything below this block is the old path for hosts not yet migrated.
MONS_LUA="$HOME/.config/hypr/monitors.lua"
if grep -qs 'monitors.lua' "$HOME/.config/hypr/hosts/$HOST.lua"; then
    RUN=${XDG_RUNTIME_DIR:-/tmp}
    MAP="$RUN/hypr-monitors"
    # monitors.lua is the single point of failure for every screen: say so loudly
    rerun() {
        local out
        out=$(hyprctl eval "dofile(\"$MONS_LUA\") return \"\"" 2>&1)
        case $out in error*|*rror*) echo "monitors.lua: $out" >&2; notify-send -u critical "monitors.lua" "$out" ;; esac
    }
    # the dry run refreshes the connector -> identity map without touching screens
    lua "$MONS_LUA" >/dev/null
    file="$STORE/$(sed -n 's/^profile //p' "$MAP")"
    id_of() { awk -v c="$1" '$1==c{print $2}' "$MAP"; }
    # live geometry: name,WxH,hz,pos,scale,transform (lit outputs only)
    live() { printf '%s' "$MONS" | jq -r '.[] | "\(.name),\(.width)x\(.height),\(.refreshRate|round),\(.x)x\(.y),\(.scale),\(.transform)"'; }

    case "${1:-}" in
    scale)
        # Changes one number. Not a snapshot: whatever else is on screen
        # (powersave Hz, duo rotation, a dark panel) stays out of the file.
        id=$(id_of "${2:-}")
        [ -n "$id" ] || { echo "no such output: ${2:-}" >&2; exit 1; }
        if grep -q "^$id," "$file" 2>/dev/null; then
            awk -F, -v OFS=, -v id="$id" -v s="${3:-}" '$1==id{$4=s}1' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
        else
            live | awk -F, -v OFS=, -v c="$2" -v id="$id" -v s="${3:-}" \
                '$1==c{print id, $2"@"$3, $4, s, ($1 ~ /^eDP/ ? 0 : $6)}' >>"$file"
        fi
        rerun
        ;;
    save)
        # Records the arrangement, not the moment. Left out on purpose: powersave's
        # refresh (the saved mode is kept), and on the built-in panels anything duo
        # owns — rotation, mirroring, power. A panel that is rotated, mirrored or
        # dark keeps its previous line.
        ultra=$(cat "$RUN/ultrasave" 2>/dev/null)
        rot=$(cat "$RUN/duo/rotation" 2>/dev/null || echo normal)
        dmode=$(cat "$RUN/duo/mode" 2>/dev/null || echo stacked)
        tmp="$file.tmp"
        : >"$tmp"
        while IFS=, read -r name res hz pos s t; do
            id=$(id_of "$name")
            [ -n "$id" ] || continue
            old=$(grep "^$id," "$file" 2>/dev/null)
            mode="$res@$hz"
            [ "$ultra" = 1 ] && [ -n "$old" ] && mode=$(cut -d, -f2 <<<"$old")
            if [[ $name == eDP* ]]; then
                if [ "$rot" != normal ] || [ "$dmode" != stacked ]; then
                    [ -n "$old" ] && echo "$old" >>"$tmp"
                    continue
                fi
                t=0
            fi
            echo "$id,$mode,$pos,$s,$t" >>"$tmp"
        done < <(live)
        # outputs not lit right now (eDP-2 under the keyboard) keep their line
        [ -f "$file" ] && grep -vF -f <(cut -d, -f1 "$tmp" | sed 's/$/,/') "$file" >>"$tmp"
        mv "$tmp" "$file"
        echo "saved $file"
        ;;
    *)
        rerun
        # A monitor the kernel refused to light (atomic commit EINVAL, seen
        # after waking from DPMS) stays "enabled" at 0x0 until Hyprland
        # restarts — no rule change revives it — and breaks everything that
        # draws on every output (grim, wayfreeze, awww). Say so, instead of a
        # silent black screen. The wait lets the modeset settle first.
        sleep 1
        stuck=$(hyprctl monitors all -j 2>/dev/null |
            jq -r '.[] | select((.disabled | not) and .width == 0) | "\(.name): \(.description)"')
        if [ -n "$stuck" ]; then
            echo "stuck: $stuck" >&2
            # The fix is a Hyprland restart, which deletes Hyprland's log, so
            # keep the evidence before anyone gets the chance.
            snap="$STORE/../stuck/$(date +%F_%H%M%S)"
            mkdir -p "$snap"
            { echo "$stuck"; echo "caller: $(ps -o args= -p $PPID)"; } >"$snap/stuck"
            tail -n 3000 "$RUN/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/hyprland.log" >"$snap/hyprland.log" 2>&1
            hyprctl monitors all >"$snap/monitors" 2>&1
            for d in /sys/class/drm/card*-*/; do
                echo "$(basename "$d") $(cat "$d/status") $(cat "$d/enabled") $(head -1 "$d/modes")"
            done >"$snap/drm" 2>&1
            tail -n 300 "${XDG_STATE_HOME:-$HOME/.local/state}/duo/log" >"$snap/duo.log" 2>&1
            notify-send -u critical "monitor stuck" "$stuck
replug its cable, or restart Hyprland
logs: $snap"
        fi
        ;;
    esac
    exit 0
fi

# The DRM card Hyprland is actually driving, found by matching a connector name
# against the compositor's output names. A multi-GPU host has connectors on
# cards nobody is scanning out to; globbing card* would put those in the profile
# key and it would never match anything saved.
drm_dir() {
    local d n names
    names=$(hyprctl monitors all -j 2>/dev/null | jq -r '.[].name') || return 1
    for d in /sys/class/drm/card*-*/; do
        n=$(basename "$d"); n=${n#card*-}
        if printf '%s\n' "$names" | grep -qxF "$n"; then
            echo "${d%%-*}"
            return 0
        fi
    done
    return 1
}

# Sorted, comma-separated list of connected outputs, from the kernel.
CARD=$(drm_dir) || CARD=

OVERRIDE="${XDG_STATE_HOME:-$HOME/.local/state}/duo/screen-override"

# duo's intent for eDP-2: it follows the keyboard unless a manual `duo screen
# on|off` has latched an override. Kept in sync with monitors.lua and
# duo/watch.go docked().
edp2_wanted() {
    local ov v
    ov=$(cat "$OVERRIDE" 2>/dev/null) || ov=
    if [ -n "$ov" ]; then
        echo "$ov"
        return
    fi
    # the pogo-pin keyboard enumerates as USB 0b05:1bf2 while it covers eDP-2
    for v in /sys/bus/usb/devices/*/idVendor; do
        [ "$(cat "$v" 2>/dev/null)" = 0b05 ] || continue
        [ "$(cat "${v%idVendor}idProduct" 2>/dev/null)" = 1bf2 ] || continue
        echo off
        return
    done
    echo on
}

if [ -n "$CARD" ]; then
    profile=$(
        for f in "$CARD"-*/status; do
            [ "$(cat "$f" 2>/dev/null)" = connected ] || continue
            n=$(basename "${f%/status}")
            echo "${n#card*-}"
        done | sort | paste -sd,
    )
else
    # No card matched (nested/headless backend): fall back to the compositor.
    profile=$(printf '%s' "$MONS" | jq -r '[.[].name] | sort | join(",")')
fi

# The lua config parser rejects `hyprctl keyword`, so rules go through eval.
# One eval for the whole layout: separate calls per output leave a transient
# state where some panels have moved and others have not, which the watcher then
# reacts to. duo/rotate.go learnt the same thing.
apply() {
    local line out mode pos scale transform code=
    for line in "$@"; do
        IFS=, read -r out mode pos scale transform <<<"$line"
        # duo(1) owns eDP-2's power on the Duo: it follows the keyboard docking
        # over the panel, so it changes at runtime and nothing this script could
        # record would stay true. Dropping `disabled` from the rule is NOT
        # enough — measured 2026-09-25, a rule without it revived a disabled
        # eDP-2 anyway (duo/hypr.go:13 claims otherwise; the claim is wrong, or
        # only held on an older Hyprland). So emit no rule at all for it.
        #
        # Skip on duo's *intent*, never on the panel's current power. Reading
        # power here raced the modeset and oscillated the panel: duo disables
        # eDP-2, that fires monitorremoved, the watcher's 0.5s debounce expires
        # before the modeset settles, this script still reads `enabled` and
        # re-emits disabled=false, duo turns it off again, forever. Measured
        # 2026-09-25: the panel flipped on at 3s, 7s and 11s between duo's 5s
        # reassert ticks. Intent is a state file plus a USB glob — no race.
        #
        # This is not the feedback loop the profile re-key fixed: that was the
        # profile *key* depending on lit outputs. Skipping one rule changes no
        # other output and no key.
        if [ "$out" = eDP-2 ] && [ "$(edp2_wanted)" = off ]; then
            continue
        fi
        # disabled=false matters: a rule without it won't reliably revive an output
        code+="hl.monitor({ output = \"$out\", mode = \"$mode\", position = \"$pos\", scale = $scale, transform = ${transform:-0}, disabled = false }) "
    done
    [ -n "$code" ] || return 0
    hyprctl eval "$code return \"\"" >/dev/null
}

# Live scale change for one output, then re-save the profile so the next
# hotplug replays it instead of resetting the panel. Re-execs for the save:
# $MONS above is a snapshot taken before the change, so saving in this same
# process would persist the scale we just replaced. exec keeps fd 9, so the
# lock is still ours and the re-exec cannot deadlock on it.
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

# Freeze whatever is on screen right now as this profile's layout. Snapshots the
# compositor rather than parsing anyone's config, so any editor that applies
# live is a valid front-end. Still reads lit outputs only: a dark one has no
# meaningful geometry to record, and on the Duo eDP-2's position is duo's to
# own. An output absent from the file simply gets no rule and keeps what it has.
if [ "${1:-}" = save ]; then
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
        # dellstar/legion. On binstar both panels are always connected, so this
        # is only reached if eDP-2's connector went away — keep the scale anyway,
        # a plain 1 here would shrink the UI.
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
