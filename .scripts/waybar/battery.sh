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

class="discharging"
icon=" "

case "$status" in
    Charging)
        class="charging"
        icon=" "
        ;;
    Full)
        class="full"
        icon=" "
        ;;
    "Not charging")
        class="plugged"
        icon=" "
        ;;
esac

if [ "$capacity" -le 15 ]; then
    class="$class critical"
elif [ "$capacity" -le 30 ]; then
    class="$class warning"
fi

text="${icon}${capacity}%"
tooltip="Battery: ${capacity}% (${status})"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
    "$(json_escape "$text")" \
    "$(json_escape "$tooltip")" \
    "$(json_escape "$class")"
