#!/bin/sh
# Output: "🔁 used / total"
awk '
function fmt(kb,    g) {
    g = kb / 1024 / 1024
    return sprintf((g >= 10 ? "%.0fG" : "%.1fG"), g)
}
/^SwapTotal:/ { total = $2 }
/^SwapFree:/  { free = $2 }
END {
    used = total - free; if (used < 0) used = 0
    printf "🔁 %s / %s\n", fmt(used), fmt(total)
}
' /proc/meminfo
