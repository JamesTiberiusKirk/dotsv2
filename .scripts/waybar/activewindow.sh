#!/bin/sh

monitor="${WAYBAR_OUTPUT:-$1}"   # read from env or arg
primary_monitor="HDMI-A-1"

# Get focused monitor
focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')

# Get active window for a given monitor
get_active_window() {
    local mon=$1
    hyprctl clients -j | jq -r --arg mon "$mon" \
        '.[] | select(.monitor == $mon and .mapped == true and .class != null) | select(.title != null) | select(.floating == false or .fullscreen == true) | .title' \
        | head -n1
}

if [ "$focused_monitor" == "$monitor" ]; then
    title=$(get_active_window "$monitor")
else
    title=$(get_active_window "$primary_monitor")
fi

# Fallback if no window found
if [ -z "$title" ]; then
    title="No window"
fi

# Output for Waybar
echo "$title"

