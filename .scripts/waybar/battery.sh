#!/bin/sh
# Workaround for waybar 0.15.0 battery module: it inotify-watches every
# /sys/class/power_supply entry and aborts when an HID/BT peripheral battery
# disappears across suspend. This reads only BAT0/BAT1.

bat=
for d in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do
    [ -d "$d" ] && { bat=$d; break; }
done

if [ -z "$bat" ]; then
    echo '{"text": ""}'
    exit 0
fi

cap=$(cat "$bat/capacity" 2>/dev/null || echo 0)
status=$(cat "$bat/status" 2>/dev/null || echo Unknown)

case "$status" in
    Charging)            icon="⚡" ; alt=charging ;;
    Full|"Not charging") icon="☻" ; alt=full ;;
    *)                   icon="🔋" ; alt=discharging ;;
esac

class=
[ "$alt" = discharging ] && [ "$cap" -le 30 ] && class=critical

if [ -n "$class" ]; then
    printf '{"text": "%s %s%%", "alt": "%s", "class": "%s", "percentage": %s}\n' "$icon" "$cap" "$alt" "$class" "$cap"
else
    printf '{"text": "%s %s%%", "alt": "%s", "percentage": %s}\n' "$icon" "$cap" "$alt" "$cap"
fi
