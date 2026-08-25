#!/bin/sh

status=$(tailscale status --json 2>/dev/null)

if [ -z "$status" ] || [ "$(echo "$status" | jq -r '.BackendState')" != "Running" ]; then
    echo '{"text": "🔒 OFF", "class": "off"}'
    exit 0
fi

hostname=$(echo "$status" | jq -r '.Self.HostName')
echo "{\"text\": \"🔒 $hostname\", \"class\": \"on\"}"
