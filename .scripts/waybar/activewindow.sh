#!/bin/bash

# Get monitor from WAYBAR_OUTPUT env
monitor="${WAYBAR_OUTPUT}"

# Example: Display different icons or messages per monitor
if [ "$monitor" == "HDMI-A-1" ]; then
    echo "󰍹 Main"
elif [ "$monitor" == "DP-1" ]; then
    echo "󰍺 Secondary"
else
    echo "󰍻 $monitor"
fi
