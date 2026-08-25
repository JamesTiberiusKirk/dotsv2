#!/bin/sh

running=$(pgrep -cf 'qemu-system-|VirtualBoxVM|vmware-vmx')
echo "{\"text\": \"$running 󰒋\", \"class\": \"on\"}"
