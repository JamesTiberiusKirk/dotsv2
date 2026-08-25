#!/bin/sh

if ! pgrep -x dockerd > /dev/null; then
    echo '{"text": "󰡨 OFF", "class": "off"}'
    exit 0
fi

running=$(docker ps -q | wc -l)
echo "{\"text\": \"$running 󰡨\", \"class\": \"on\"}"
