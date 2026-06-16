#!/usr/bin/env bash
# KVM toggle — one script for both sides of the KVM switch.
#
# Run it BEFORE switching the KVM away (disables the shared monitors so the
# physical disconnect can't SIGSEGV Hyprland — see crash PR #14893), and again
# AFTER switching back (re-enables + repositions them). It picks the direction
# from DP-1's current state.
#
# Shared monitors: DP-1 (center) + HDMI-A-1 (right). Runtime monitor changes go
# through `hyprctl eval` + hl.monitor(); `hyprctl keyword monitor` is dead under
# the Lua config.
set -u

# output | mode | position | scale   (mirrors hosts/deathstar.lua)
MONITORS=(
    "DP-1|2560x1440@144|1920x1080|1"
    "HDMI-A-1|preferred|4480x1080|1"
)

# Pivot on DP-1: if it's currently disabled we're coming back -> enable,
# otherwise we're about to leave -> disable. (Empty = not present; treat as
# "about to leave" and disable, which is a harmless no-op if already gone.)
disabled=$(hyprctl monitors all -j | jq -r '.[] | select(.name=="DP-1") | .disabled')

if [ "$disabled" = "true" ]; then
    echo "KVM attach — re-enabling shared monitors"
    for m in "${MONITORS[@]}"; do
        IFS='|' read -r out mode pos scale <<<"$m"
        printf '  enabling %s (%s @ %s) ... ' "$out" "$mode" "$pos"
        # disabled=false is required — re-applying a rule does not clear the flag.
        hyprctl eval "hl.monitor({output=\"$out\", mode=\"$mode\", position=\"$pos\", scale=$scale, disabled=false})"
    done
else
    echo "KVM detach — disabling shared monitors"
    for m in "${MONITORS[@]}"; do
        IFS='|' read -r out _ _ _ <<<"$m"
        printf '  disabling %s ... ' "$out"
        hyprctl eval "hl.monitor({output=\"$out\", disabled=true})"
    done
fi
