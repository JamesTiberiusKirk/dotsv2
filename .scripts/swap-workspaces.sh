#!/bin/bash
# Swap visible workspaces between two monitors

INFO=$(i3-msg -t get_workspaces)

FOCUSED_WS=$(echo "$INFO" | jq -r '.[] | select(.focused) | .name')
FOCUSED_OUT=$(echo "$INFO" | jq -r '.[] | select(.focused) | .output')

OTHER_WS=$(echo "$INFO" | jq -r ".[] | select(.visible and .focused==false) | .name")
OTHER_OUT=$(echo "$INFO" | jq -r ".[] | select(.visible and .focused==false) | .output")

[ -z "$OTHER_WS" ] || [ "$OTHER_OUT" = "null" ] && exit 0

i3-msg "move workspace to output $OTHER_OUT; workspace $OTHER_WS; move workspace to output $FOCUSED_OUT; focus output $FOCUSED_OUT"
