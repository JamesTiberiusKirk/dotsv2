#!/bin/sh

if ! pgrep -x libvirtd > /dev/null; then
    echo '{"text": "󰒋 OFF", "class": "off"}'
    exit 0
fi

running=$(virsh -c qemu:///system list --name 2>/dev/null | grep -c .)
echo "{\"text\": \"$running 󰒋\", \"class\": \"on\"}"
