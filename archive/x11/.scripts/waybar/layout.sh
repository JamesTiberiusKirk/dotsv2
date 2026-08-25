#!/usr/bin/env bash
layout=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // "?"')
echo "{\"text\": \" $layout \", \"class\": \"layout-$layout\", \"alt\": \"$layout\"}"
