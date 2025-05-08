#!/bin/sh

echo "=== Disabling NVIDIA GPU ==="

# List of NVIDIA devices (GPU, audio, USB, Type-C)
DEVICES=("0000:01:00.0" "0000:01:00.1" "0000:01:00.2" "0000:01:00.3")

for dev in "${DEVICES[@]}"; do
    if [ -e /sys/bus/pci/devices/$dev/remove ]; then
        echo "Removing $dev..."
        echo 1 | sudo tee /sys/bus/pci/devices/$dev/remove
    else
        echo "$dev not found or already removed"
    fi
done

echo "=== NVIDIA GPU disable script completed ==="
