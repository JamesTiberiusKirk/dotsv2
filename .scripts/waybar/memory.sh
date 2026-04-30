#!/bin/sh
# Output: "🧠 used / cache / total"
awk '
function fmt(kb,    g) {
    g = kb / 1024 / 1024
    return sprintf((g >= 10 ? "%.0fG" : "%.1fG"), g)
}
/^MemTotal:/      { total = $2 }
/^MemAvailable:/  { avail = $2 }
/^Buffers:/       { buf = $2 }
/^Cached:/        { cac = $2 }
/^SReclaimable:/  { sr = $2 }
/^Shmem:/         { sh = $2 }
END {
    used = total - avail; if (used < 0) used = 0
    cache = buf + cac + sr - sh; if (cache < 0) cache = 0
    printf "🧠 %s / %s / %s\n", fmt(used), fmt(cache), fmt(total)
}
' /proc/meminfo
