#!/bin/sh

# Source your profile
[ -f ~/.profile ] && . ~/.profile

# Merge X resources (if you create ~/.Xresources later)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Set keyboard layout to US International
setxkbmap -layout us -variant intl

# Set keyboard repeat rate (adjust to preference)
xset r rate 300 50

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

# Start system tray apps (from your Hyprland autostart)
pasystray &
blueman-applet &
dunst &
owncloud &

# Screen locker (optional - locks screen on suspend/sleep)
xss-lock -- i3lock -c 000000 &

# Hide mouse cursor after inactivity (optional)
unclutter --timeout 3 &

# Update environment variables for X11
export XDG_CURRENT_DESKTOP=i3
export QT_QPA_PLATFORM=xcb
export QT_QPA_PLATFORMTHEME=qt6ct

# Finally, exec i3
exec i3
