#!/bin/sh
# Example: ~/.scripts/waybar/workspace_icons.sh
hyprctl clients -j | jq '...'
# Process output and print JSON with workspace numbers and icons
