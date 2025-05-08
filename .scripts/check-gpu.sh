#!/bin/sh

echo "=== GPU Status Report ==="

# 1. List DRM drivers
echo -e "\n[Kernel GPU drivers]"
for d in /sys/class/drm/card*/device/driver; do
    card=$(echo $d | cut -d'/' -f5)
    driver=$(basename $(readlink $d))
    vendor=$(cat /sys/class/drm/$card/device/vendor)
    if [ "$vendor" == "0x1002" ]; then
        vendor="AMD"
    elif [ "$vendor" == "0x10de" ]; then
        vendor="NVIDIA"
    else
        vendor="Unknown"
    fi
    echo "$card → $vendor ($driver)"
done

# 2. OpenGL renderer
if command -v glxinfo &>/dev/null; then
    echo -e "\n[OpenGL renderer]"
    glxinfo | grep "OpenGL renderer"
else
    echo -e "\n[OpenGL renderer]"
    echo "glxinfo not installed"
fi

# 3. Vulkan devices
if command -v vulkaninfo &>/dev/null; then
    echo -e "\n[Vulkan devices]"
    vulkaninfo | grep "deviceName"
else
    echo -e "\n[Vulkan devices]"
    echo "vulkaninfo not installed"
fi

# 4. NVIDIA-SMI check
if command -v nvidia-smi &>/dev/null; then
    echo -e "\n[NVIDIA-SMI processes]"
    nvidia-smi || echo "NVIDIA driver loaded but GPU may be inactive"
else
    echo -e "\n[NVIDIA-SMI processes]"
    echo "nvidia-smi not installed"
fi

# 5. PCI runtime power status
echo -e "\n[PCI power states]"
for dev in /sys/bus/pci/devices/*; do
    vendor=$(cat $dev/vendor 2>/dev/null)
    if [ "$vendor" == "0x10de" ] || [ "$vendor" == "0x1002" ]; then
        status=$(cat $dev/power/runtime_status 2>/dev/null)
        control=$(cat $dev/power/control 2>/dev/null)
        echo "$(basename $dev) → $vendor → $status (control: $control)"
    fi
done

echo -e "\n[Hyprland logs (recent)]"
journalctl --user-unit=hyprland -n 20 --no-pager 2>/dev/null || echo "Hyprland log not found"

echo -e "\n=== End of Report ==="

