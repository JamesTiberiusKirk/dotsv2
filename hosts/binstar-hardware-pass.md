# binstar hardware pass — plan (v2: duo util)

Issues to solve:
- monitors: side-by-side, scale 1.0 — wrong. Panels stacked, need 1.5
- keyboard dock/undock does nothing (bottom screen stays on)
- brightness keys dead: `brightnessctl` write denied (user not in `video` group)
- brightness should drive BOTH panels
- quickshell brightness icon shows 0 (reads `asus_screenpad`, not `intel_backlight`)
- touching bottom screen sends input to top screen (touch not mapped to output)
- volume keys reported dead — `wpctl` works manually, binds registered; key events unverified
- suspend bind runs `systemctl` — broken on runit
- no binstar.txt

Hardware facts (verified):
- eDP-1 top, eDP-2 bottom, both 2880x1800@120
- backlights: `intel_backlight` (eDP-1) + `card1-eDP-2-backlight`, both max 400 → 1:1
- keyboard docked = USB `0b05:1bf2`, detached = BT
- touchscreens: ELAN9008 (04F3:4447), ELAN9009 (04F3:4448) — which panel is which: verify during impl
- kernel 7.1 has all UX8406CA quirks; asusctl dropped (no Zenbook support)

Decisions:
- battery cap: dropped for now
- span (two panels as one long screen): not possible in Hyprland — parked, watch upstream
- proper Go util instead of script pile

# duo util (new, Go)

Shape:
- `duo/` dir at repo root, built like dots-link: `make install` → `~/go/bin/duo`
- no runit, no root: session tool, started by `binstar.lua` `hl.on("hyprland.start")` → `duo watch`
- talks to Hyprland via `hyprctl` (IPC socket later if needed)
- host-scoped: only binstar.lua starts it

Commands:
- `duo watch` — daemon:
  - udev monitor (usb): `0b05:1bf2` add → eDP-2 disable; remove → re-enable @1.5
  - initial dock state at startup from `/sys/bus/usb/devices/*/idProduct`
- `duo screen on|off|toggle` — manual eDP-2 control
- `duo brightness up|down|set <pct>` — writes BOTH backlights + `qs ipc call osd brightness`
- `duo layout stacked|mirror|top-only` — monitor rule presets via hyprctl
- `duo status` — dock state, layout, brightness

Future (design for, don't build):
- orientation sensor → portrait
- pen buttons (try plain Hyprland tablet config first)

# monitor layout fix

- `.config/hypr/hosts/binstar.lua`:
  - eDP-1: 2880x1800@120, 0x0, scale 1.5
  - eDP-2: 2880x1800@120, 0x1200, scale 1.5
  - start `duo watch` here
- `.config/hypr/scripts/monitor-layout.sh`:
  - add `"eDP-1,eDP-2"` case, same layout
  - gotcha: eDP-2 off → key = `"eDP-1"` = dellstar's case → resets scale to 1
  - fix: branch on host (`${HOSTNAME:-$(cat /etc/hostname)}`; no `hostname` binary here)

# touch → wrong screen fix

- Hyprland config, not util: `hl.device({ name = "<elan touch device>", output = "eDP-1|eDP-2" })`
- goes in base.lua device block (convention: absent devices silently ignored)
- verify which ELAN id = which panel by touching each

# brightness keys fix

- install.sh: `sudo usermod -aG video $USER` (idempotent, all hosts)
- `binds.lua`: XF86MonBrightness* → `duo brightness up|down` (replaces brightnessctl one-liner)

# quickshell icon fix

- `.config/quickshell/common/Sys.qml:69,76`: globs `/sys/class/backlight/*` + `head -1` → lands on screenpad (0)
- fix: prefer `intel_backlight`, fallback to first device (keeps other hosts working)

# volume keys

- diagnose first: press keys, watch `wpctl get-volume`
- if events dead → likely asus-hid fn-key issue, investigate then
- add OSD call to volume binds regardless (no feedback today)

# suspend bind fix

- `binds.lua`: SUPER+CTRL+Q `systemctl suspend` → `loginctl suspend`

# binstar.txt

- new `.config/installed_packages/binstar.txt`, hardware-only:
  - intel-media-driver, vulkan-intel, usbutils
- NO comment lines (install.sh doesn't strip host lists)
- check audio / sof-firmware during impl, add if missing

# journal

- update `hosts/binstar.md`

# deferred

- battery charge cap (dropped for now)
- span layout — not supported by Hyprland, watch upstream
- orientation / portrait (util is designed to grow into it)
- pen support (config first, util if flaky)
- keyboard backlight while detached
- keyd id for internal keyboard
- lid-switch handling
- `i915.enable_psr=0` — only if flicker shows up

# verify

- `hyprctl monitors`: stacked, both 1.5
- dock keyboard → eDP-2 off; lift → on (`duo status` agrees)
- brightness keys: both sysfs values move together, OSD shows, icon correct
- touch each panel → cursor/input lands on that panel
- `duo layout mirror` / `top-only` / `stacked` round-trip
- volume keys after diagnosis
- SUPER+CTRL+Q suspends + resumes
- rerun `./install.sh` — idempotent
- `make install` builds duo cleanly

No git ops — unstaged, darhvader commits.
