#!/bin/sh
# Claude Code hook for LCARS crew state. Usage: lcars-hook.sh working|orders|idle|end
# Does nothing unless the LCARS shell is on (flag file). Never prints, always exits 0.
[ -e "$XDG_RUNTIME_DIR/lcars-on" ] || exit 0
exec >/dev/null 2>&1
cat >/dev/null
s=${GTMUX##*,}
case $s in ""|*/*) exit 0 ;; esac
d=$XDG_RUNTIME_DIR/lcars-agents
if [ "$1" = end ]; then rm -f "$d/$s.json"; exit 0; fi
mkdir -p "$d"
cwd=$(printf %s "$PWD" | sed 's/\\/\\\\/g;s/"/\\"/g')
printf '{"state":"%s","t":%s,"cwd":"%s"}\n' "$1" "$(date +%s)" "$cwd" > "$d/$s.json.tmp" && mv "$d/$s.json.tmp" "$d/$s.json"
exit 0
