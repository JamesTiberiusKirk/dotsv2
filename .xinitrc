#!/bin/sh

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=i3
export DESKTOP_SESSION=i3

# Source your profile
[ -f ~/.profile ] && . ~/.profile

# Merge X resources (if you create ~/.Xresources later)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Ensure a DBus session exists so keyring/secret services can register
if command -v dbus-launch >/dev/null 2>&1 && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax --exit-with-session)"
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
fi

wait_for_secret_service() {
    if ! command -v dbus-send >/dev/null 2>&1; then
        return
    fi

    attempts=0
    while [ $attempts -lt 50 ]; do
        if dbus-send --session --dest=org.freedesktop.DBus \
            --type=method_call --print-reply \
            /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
            string:org.freedesktop.secrets 2>/dev/null | grep -q "boolean true"; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 0.1
    done
}

# Set keyboard repeat rate (adjust to preference)
# First number: delay before repeat starts (ms)
# Second number: repeat rate (repeats per second)
xset r rate 300 25

# Touchpad settings
# Find touchpad device ID and configure it
TOUCHPAD_ID=$(xinput list | grep -i touchpad | grep -o 'id=[0-9]*' | grep -o '[0-9]*' | head -1)
if [ -n "$TOUCHPAD_ID" ]; then
    # Enable natural (inverted) scrolling
    xinput set-prop $TOUCHPAD_ID "libinput Natural Scrolling Enabled" 1
    # Lower scroll sensitivity (scroll factor - lower = less sensitive)
    xinput set-prop $TOUCHPAD_ID "libinput Scrolling Pixel Distance" 50
fi

# Disable bell
xset b off

# Monitor setup - handles both docked and undocked scenarios
# Check if external monitors are connected
if xrandr | grep -q "DVI-I-1 connected"; then
    # Docked: Setup multi-monitor
    xrandr --output eDP-1 --mode 1920x1080 --pos 0x0 --rotate normal \
           --output DVI-I-1 --mode 2560x1440 --pos 1920x0 --rotate normal --primary \
           --output DVI-I-2 --mode 1920x1080 --pos 4480x0 --rotate normal
else
    # Undocked: Just laptop screen
    xrandr --output eDP-1 --auto --primary
fi

# Set wallpaper (same as Hyprland) - zoom to fit/fill screen
feh --bg-fill ~/Pictures/wallpapers/interior-of-a-barn.jpg &

# Start compositor (picom)
picom &

# Set GTK dark theme
gsettings set org.gnome.desktop.interface gtk-theme "Materia-dark-compact"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"

# Start gnome-keyring-daemon for credential storage
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh)"
    export SSH_AUTH_SOCK
    wait_for_secret_service
fi

# Start system tray apps (from your Hyprland autostart)
pasystray &
blueman-applet &
dunst &
owncloud &
flameshot &
~/bin/rquickshare &

# Screen locker (optional - locks screen on suspend/sleep)
# Pause notifications before locking, resume after
# xss-lock -- sh -c 'dunstctl set-paused true; i3lock -c 000000; dunstctl set-paused false' &

# Hide mouse cursor after inactivity (optional)
unclutter --timeout 3 &

# Update environment variables for X11
export XDG_CURRENT_DESKTOP=i3
export QT_QPA_PLATFORM=xcb
export QT_QPA_PLATFORMTHEME=qt6ct

# Finally, exec i3
exec i3
