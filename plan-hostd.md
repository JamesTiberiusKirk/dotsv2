# Host hardware rebuild: one daemon (hostd)

## Issues to solve
- **Too many writers to monitor state:**
  - `hosts/*.lua`
  - `monitor-layout.sh`, `monitor-watch.sh`
  - `duo watch`
  - `idle` (hypridle)
  - `Sys.qml`, `Menu.qml`
  - `.scripts/powersave`
  - `kvm-toggle.sh`
  - They fight each other. Most of the comments in those files describe a fight.
- **hyprctl lies.** On 2026-09-22 it said eDP-2 was on while the kernel had it off (`/sys/class/drm/card1-eDP-2/enabled` = disabled). Result: a black screen that looked "on".
- **Ghost HDMI (aquamarine 0.15.0 bug):**
  - A dock HDMI was unplugged but never switched off in the kernel. It still holds CRTC 269.
  - eDP-2 was later put on CRTC 269, and every modeset since gets EINVAL.
  - Disabling HDMI-A-1 via `hl.monitor` does **not** free it (tested).
  - Only fix today: restart Hyprland.
- **Reload stomps runtime state.** Host lua `hl.monitor` rules are re-applied on every `hyprctl reload`. duo's 5s "force it back" loop exists only for this.
- **Brightness keys are broken off binstar.** `.config/hypr/binds.lua` calls `~/go/bin/duo brightness`, but duo is only installed on binstar.
- **No single-instance guard.** A `duo watch` from a Hyprland session that died on Sep 10 was still running 12 days later, spamming the log.

## Shape
- **One Go program, one process, one log:** `hostd/`.
- Sections inside it, switched on per host:
  - **display** (all hosts): layouts, scale, hotplug, dock rules, rotation, dpms, kernel check
  - **brightness** (all laptops): panel backlights, "lock together", keys + OSD
  - **asus-duo** (binstar): keyboard wake-up (Fn layer), Fn keys, keyboard backlight, sleep blanking
- hostd is the **only** thing that touches monitors, backlights, or the Duo keyboard. Everything else asks it.
- CLI = the API, same shape as duo today:
  - `hostd watch`
  - `hostd screen …`, `layout …`, `scale …`, `save`, `rotate …`, `autorotate …`, `dpms on|off`
  - `hostd brightness …`, `hostd kbd …`
  - `hostd status`
- The CLI talks to the daemon over a unix socket in `$XDG_RUNTIME_DIR`. Only the daemon applies changes.
- One daemon per Hyprland session:
  - lock keyed on `HYPRLAND_INSTANCE_SIGNATURE`
  - exits when that session's socket is gone
- Still out: audio, and anything that needs root.

## Rebuilt vs carried over
- **Written new:** the display section, daemon loop, socket, config, kernel check.
- **Carried over from `duo/`** (measured, works):
  - keyboard handshake + backlight + Fn reader (`kbd.go`)
  - accelerometer reading + axis map (`sensors.go`)
  - backlight maths (`brightness.go`)
  - sleep watch via elogind `PrepareForSleep`
- `duo/` is deleted at the end. Nothing is left pointing at it.

## Per-host config (`~/.config/hostd/<host>`)
- Which sections are on.
- Layouts per set of plugged-in screens. Existing `~/.local/state/hypr/layouts/*` files carry over as they are.
- Generic display rules, no brand code:
  - `<output> off while usb <vid:pid> present`. On binstar: eDP-2 while `0b05:1bf2` is present.
  - `autorotate <outputs> from iio <name>` + axis map
  - named presets: stacked / mirror / mirror-flip / top-only
- A manual screen override stays latched until the rule's input changes, same as duo today.

## Kernel check
- After every apply, and every 5s: compare what we want against `/sys/class/drm/card*-<out>/{status,enabled,dpms}`. Not hyprctl.
- Mismatch: re-apply once, then re-check sysfs.
- Still wrong: one `notify-send` with what's wrong + the known fix. Logged, no retry loop until something changes.
- Ghost detection: `disconnected` + `enabled` gets flagged immediately.
- **Limit:** it catches the ghost, it can't free it yet.

## Reload
- `hosts/*.lua` keep env/devices only. **Zero `hl.monitor` lines.**
- hostd re-applies on Hyprland's `configreloaded` event.
- `base.lua` `hyprland.start` runs `hostd watch`. It replaces the `monitor-layout.sh` + `monitor-watch.sh` lines, and binstar.lua's `duo watch` line.

## Stages (each revertible, never left without display management)
1. **Core + display + dock:**
   - hostd skeleton: socket, lock, config, log, display section, kernel check, wallpaper call on layout change
   - delete `monitor-layout.sh`, `monitor-watch.sh`
   - strip `hl.monitor` from `hosts/*.lua`
   - `duo watch` keeps keyboard only (screen/reassert code removed)
   - `Sys.qml` scale + sub-screen → hostd
   - `Menu.qml` `display/arrange` → `hostd save`
2. **Rotation + presets:**
   - rotate/autorotate/layout presets → hostd
   - `Menu.qml` rotate/layout entries, `Sys.qml` autorotate
3. **Brightness + keyboard:**
   - brightness + asus-duo sections in hostd
   - `binds.lua` brightness keys, `Sys.qml` brightness/sync, `Bar.qml:798` kbd backlight → hostd
   - delete `duo/`
4. **DPMS + stragglers:**
   - `idle` dpms via hostd (drop its `monitor-layout.sh` call)
   - `Sys.qml` sleep/resume dpms
   - `powersave` refresh-rate change
   - `kvm-toggle.sh`
   - `Makefile` + `install.sh`: build hostd on every host
   - `hosts/binstar.md` notes

## Out of scope
- Audio (the driver reload needs root and must run before sleep).
- The spurious wakes at 06:59 / 08:14 with the lid closed.
- Fixing aquamarine. Report it upstream separately.

## Still unknown
- Freeing the ghost without restarting Hyprland. Next time it happens, try as root: `echo on` to the connector's `status`, disable it, then `echo detect`.
- Every failing eDP-2 modeset was at 60Hz, and the working ones at 120Hz. That's the backup lead if the ghost theory is wrong.

## Open questions (one at a time)
1. Config format
2. Socket vs state file + signal
