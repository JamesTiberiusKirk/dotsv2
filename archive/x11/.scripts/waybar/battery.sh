#!/usr/bin/env bash

set -eu

find_battery() {
    for supply in /sys/class/power_supply/*; do
        [ -d "$supply" ] || continue
        [ -r "$supply/type" ] || continue
        case "$(basename "$supply")" in BAT*) ;; *) continue ;; esac
        if [ "$(cat "$supply/type")" = "Battery" ]; then
            printf '%s\n' "$supply"
            return 0
        fi
    done
    return 1
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if ! battery_dir="$(find_battery)"; then
    printf '{"text":"","tooltip":"","class":"hidden"}\n'
    exit 0
fi

status="$(cat "$battery_dir/status" 2>/dev/null || printf 'Unknown')"
capacity="$(cat "$battery_dir/capacity" 2>/dev/null || printf '0')"

# Clamp capacity to 0..100 and map to a 0..10 level index (rounded).
[ "$capacity" -lt 0 ] && capacity=0
[ "$capacity" -gt 100 ] && capacity=100
level=$(( (capacity + 5) / 10 ))
[ "$level" -gt 10 ] && level=10

# Nerd Font MDI battery glyphs, indexed 0 (empty) .. 10 (full).
discharge_icons=(
    $'\U000F008E' $'\U000F007A' $'\U000F007B' $'\U000F007C' $'\U000F007D'
    $'\U000F007E' $'\U000F007F' $'\U000F0080' $'\U000F0081' $'\U000F0082'
    $'\U000F0079'
)
charge_icons=(
    $'\U000F089F' $'\U000F089C' $'\U000F0086' $'\U000F0087' $'\U000F0088'
    $'\U000F089D' $'\U000F0089' $'\U000F089E' $'\U000F008A' $'\U000F008B'
    $'\U000F0085'
)

class="discharging"
icon="${discharge_icons[$level]}"

case "$status" in
    Charging)
        class="charging"
        icon="${charge_icons[$level]}"
        ;;
    Full)
        class="full"
        icon=$'\U000F0079'
        ;;
    "Not charging")
        class="plugged"
        ;;
esac

extra=""
if [ "$capacity" -le 15 ]; then
    extra="critical"
elif [ "$capacity" -le 30 ]; then
    extra="warning"
fi

if [ -n "$extra" ]; then
    class_json="[\"$class\",\"$extra\"]"
else
    class_json="\"$class\""
fi

text="${icon} ${capacity}%"
tooltip="Battery: ${capacity}% (${status})"

printf '{"text":"%s","tooltip":"%s","class":%s}\n' \
    "$(json_escape "$text")" \
    "$(json_escape "$tooltip")" \
    "$class_json"
