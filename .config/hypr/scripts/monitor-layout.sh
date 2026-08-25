#!/usr/bin/env bash
# Detect connected outputs and apply the matching layout via hyprctl.
# Re-run manually with `hyprctl reload` is not enough — call this script
# directly (or bind it) after dock/undock to repick the profile.
set -u

MONS=$(hyprctl monitors -j 2>/dev/null) || exit 0
HOST=${HOSTNAME:-$(cat /etc/hostname)}

# Sorted, comma-separated list of currently connected output names.
profile=$(printf '%s' "$MONS" | jq -r '[.[].name] | sort | join(",")')

# The lua config parser rejects `hyprctl keyword`, so rules go through eval.
apply() {
    for line in "$@"; do
        IFS=, read -r out mode pos scale <<<"$line"
        # disabled=false matters: a rule without it won't revive a disabled output
        hyprctl eval "hl.monitor({ output = \"$out\", mode = \"$mode\", position = \"$pos\", scale = $scale, disabled = false }) return \"\"" >/dev/null
    done
}

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
        # Unknown layout: let Hyprland auto-place each output.
        for name in $(printf '%s' "$MONS" | jq -r '.[].name'); do
            apply "$name,preferred,auto,1"
        done
        ;;
esac
