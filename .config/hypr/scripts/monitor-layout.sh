#!/usr/bin/env bash
# Detect connected outputs and apply the matching layout via hyprctl.
# Re-run manually with `hyprctl reload` is not enough — call this script
# directly (or bind it) after dock/undock to repick the profile.
set -u

MONS=$(hyprctl monitors all -j 2>/dev/null) || exit 0

# Sorted, comma-separated list of currently connected output names.
profile=$(printf '%s' "$MONS" | jq -r '[.[].name] | sort | join(",")')

apply() {
    for line in "$@"; do
        hyprctl keyword monitor "$line" >/dev/null
    done
}

case "$profile" in
    "DP-0,DP-3,DP-5,HDMI-0")
        # deathstar — 4-monitor desktop layout (matches autorandr desktop-4)
        apply \
            "DP-0,2560x1440@144,1920x1080,1" \
            "DP-3,1920x1080@60,2240x0,1" \
            "DP-5,1920x1080@60,0x1080,1" \
            "HDMI-0,1920x1080@100,4480x1080,1"
        ;;
    "eDP-1")
        # dellstar / legion solo
        apply "eDP-1,preferred,0x0,1"
        ;;
    *)
        # Unknown layout: let Hyprland auto-place each output.
        for name in $(printf '%s' "$MONS" | jq -r '.[].name'); do
            hyprctl keyword monitor "$name,preferred,auto,1" >/dev/null
        done
        ;;
esac
