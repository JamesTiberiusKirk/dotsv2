#!/bin/sh
# Diagnostic only — not part of the duo binary, not built by the Makefile.
# lidlog — leave this running, close/open the lid, read the log.
# Prints a line whenever any of these change, plus a line when the wall clock
# jumps (which is the only honest proof the machine was actually asleep:
# counters can stay put, time cannot).
set -u

kbd() {
  for d in /sys/bus/hid/devices/*0B05:1BF2*; do [ -e "$d" ] && { echo usb; return; }; done
  for d in /sys/bus/hid/devices/*0B05:1BF3*; do [ -e "$d" ] && { echo bt; return; }; done
  echo none
}
lid()  { cat /proc/acpi/button/lid/*/state 2>/dev/null | awk '{print $2}'; }
succ() { cat /sys/power/suspend_stats/success 2>/dev/null; }
fail() { cat /sys/power/suspend_stats/fail 2>/dev/null; }
hw()   { cat /sys/power/suspend_stats/total_hw_sleep 2>/dev/null; }
bl()   { cat "${XDG_RUNTIME_DIR:-/tmp}/duo-kbd-backlight" 2>/dev/null || echo -; }
say()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

pl=$(lid) pk=$(kbd) pb=$(bl) ps=$(succ) pf=$(fail) ph=$(hw) pt=$(date +%s)
say "start  lid=$pl kbd=$pk backlight=$pb suspends=$ps fails=$pf"

while sleep 1; do
  t=$(date +%s); gap=$((t - pt - 1)); pt=$t
  [ "$gap" -gt 2 ] && say "WOKE   after ${gap}s off the clock"

  l=$(lid);  [ "$l" != "$pl" ] && { say "lid    $pl -> $l"; pl=$l; }
  k=$(kbd);  [ "$k" != "$pk" ] && { say "kbd    $pk -> $k"; pk=$k; }
  b=$(bl);   [ "$b" != "$pb" ] && { say "light  $pb -> $b"; pb=$b; }
  s=$(succ); [ "$s" != "$ps" ] && { say "SLEPT  suspend #$s ok, hw_sleep +$(( ($(hw) - ph) / 1000000 ))s"; ps=$s; ph=$(hw); }
  f=$(fail); [ "$f" != "$pf" ] && { say "FAILED suspend attempt, fails=$f step=$(cat /sys/power/suspend_stats/last_failed_step)"; pf=$f; }
done
