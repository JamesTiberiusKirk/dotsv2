# binstar — install project state (2026-08-23)

Asus Zenbook Duo (Intel Core Ultra, Arc iGPU, 32G). Artix runit, btrfs, Limine.

## What exists

- `install-system.sh` (repo root) — live-ISO installer: interactive disk/hostname/user
  + two password pairs + swap? prompt up front, then unattended: GPT (1G ESP at
  /boot + btrfs), subvols `@ @home @log @snapshots` (+`@swap` w/ ram*2 swapfile,
  hibernate resume on cmdline — skipped entirely if swap declined), basestrap w/
  ucode autodetect, ParallelDownloads on + known-good mirrors prepended
  (geo.mirror.pkgbuild.com for arch, mirror1.artixlinux.org for artix — default
  lists led with dead mirrors, killed the first real install), Limine via EFI
  fallback, ssh keygen (pubkey printed), https-clones repo to ~user/.dots (origin
  → ssh), runs install.sh in chroot; converge failure is non-fatal + LOUD (system
  still boots, rerun ~/.dots/install.sh after boot).
- `install.sh` — idempotent converge: yay-bin, makepkg speed conf
  (BUILDDIR=/tmp, -j$(nproc), no pkg compression), repo pkgs one pacman batch
  then AUR one-by-one w/ failure summary, chsh zsh, make install + dots-link sync,
  runit services, snapper (QGROUP=), hyprpm best-effort.
  `./install.sh extra-pkgs` installs extras.txt (never by default).
- Package lists: common.txt trimmed 223 → ~177 (dupe browsers/viewers/terminals,
  legacy i3+X11 stack, blue-recorder + heavy AUR builds gone); `extras.txt` =
  on-demand heavy stuff (embedded toolchain, texlive-fontsextra, jdk+maven,
  gimp/inkscape/krita/rawtherapee, libreoffice, steam, hugo, ~8G total).
  Still no binstar.txt (host gets common+fonts; fine until hardware pass).
- `.config/hypr/hosts/binstar.lua` exists (was a hard startup error without it).
- `test-vm.sh` — back on KVM (-cpu host, 8G, smp 8) now that we run on deathstar.

## Verified

- VM (deathstar): full flow → graphical hyprland session.
- Real hardware (32G USB stick test): base install + Limine boot + passwords OK.
  Chroot converge died on dead default mirrors (→ mirror prepend fix); rerun
  after boot converged through the AUR list. USB stick I/O made it take hours —
  not representative. Account later got faillock'd (bad password attempts).
- Windows MSDM license key confirmed present in ACPI (photographed) — safe to
  nuke Windows; BIOS updates via ASUS EZ Flash, no Windows needed.

## Hardware pass (2026-08-23) — done

Plan/details: `hosts/binstar-hardware-pass.md`. Summary:

- `duo/` (repo root, Go, `make install` → `~/go/bin/duo`) — session util, started
  by binstar.lua, no root/runit. `watch` = dock daemon (kbd USB 0b05:1bf2 docked
  → eDP-2 off), `screen`, `brightness` (per-panel or locked + qs OSD), `layout
  stacked|mirror|top-only`, `status`. asusctl dropped (no Zenbook support;
  kernel 7.1 has all UX8406CA quirks).
- binstar.lua: stacked eDP-1/eDP-2 @1.5; starts `duo watch`. NOTE: Hyprland's
  PATH lacks ~/go/bin — binds/exec use the explicit path.
- `hyprctl keyword` is DEAD with the lua parser (silently, exit 0) —
  monitor-layout.sh rewritten to `hyprctl eval hl.monitor(...)`; binstar cases
  added (incl. eDP-1-only branch keeping scale 1.5 vs dellstar's 1).
- Touch mapped to panels in base.lua (elan9008→eDP-1, elan9009→eDP-2 —
  bottom touches used to land on the top screen).
- The two panels can be driven independently (`duo brightness set N top|bottom`)
  or locked together (`duo brightness sync on|off`, default on, state in
  ~/.local/state/duo/brightness-sync). The lock lives in duo rather than the
  shell because the brightness keys have to honour it too — split across Go and
  QML the two would drift. Unlocked, the keys move eDP-1 only.
  The bar's `☀` cell opens a display panel: one slider per DRM backlight, the
  lock (only with 2+ panels), sub-screen and auto-rotate toggles (binstar only).
- Brightness keys → `duo brightness` (writes were denied: user wasn't in
  `video`; install.sh now adds the group — needs relogin).
- quickshell Sys.qml backlight glob landed on asus_screenpad (=0, icon showed
  0) — now prefers intel_backlight.
- Volume keys "dead" root cause was twofold: no audio sink at all (Dummy
  Output) — sof-firmware missing → binstar.txt (+ intel-media-driver,
  vulkan-intel, usbutils); and the Fn layer being off (below). Both fixed;
  speakers + mic confirmed live after reboot.
- Suspend bind: systemctl → loginctl (all runit hosts).

### Fn row / keyboard (the big one)

Kernel 7.1 `hid-asus` has NO entry for the CA keyboard (`0b05:1bf2`), so it runs
on generic usbhid and boots with its Fn layer OFF — every Fn chord arrived as a
bare KEY_F1..F6 (verified with libinput, with and without Fn).

Fix: `duo` sends the ASUS init handshake itself — feature report `0x5a` +
ASCII "ASUS Tech.Inc.\0" via HIDIOCSFEATURE on the vendor hidraw node. Node is
found by scanning report descriptors for `85 5a` (interface numbering isn't
stable); on this box that's `/dev/hidraw4` = usb iface 1.4. Needs the `input`
group + `system/etc/udev/rules.d/90-asus-duo-keyboard.rules`. Firmware NAKs the
first tries, hence the backoff retries. Must be re-sent on every re-dock.

After the handshake:
- volume/mute keys → normal consumer events → existing Hyprland binds work.
- brightness + kbd-backlight keys do NOT reach the input layer at all. They come
  as vendor reports on the 0x5a channel: `5a 10` bri down, `5a 20` bri up,
  `5a c7` kbd backlight, `5a 00` release. `duo watch` reads that node and acts
  on them directly (so the XF86MonBrightness binds are dead weight on binstar).
- kbd backlight write: `5a ba c5 c4 <0-3>`, same node. Confirmed working.
- Fn keys work over bluetooth too, not just docked: the vendor channel exists
  on the BT id (0b05:1bf3) as well, so duo separates "keyboard reachable"
  (either transport → handshake + key reader) from "docked" (USB only → screen
  off). The handshake is also re-sent on dock changes: placing or lifting the
  keyboard resets its Fn layer even when the BT link never drops.
- The udev rule matches the parent HID device (`bus:vendor:product`), not
  ATTRS{idVendor} — bluetooth HID exposes no such attrs, which left the
  wireless node root-only. Note udev only applies node permissions on `add`,
  so `udevadm trigger` needs `--action=add` to take effect without a replug.
- keyd needs the per-node id, not `k:0b05:1bf2`. The keyboard exposes four
  nodes under that one vendor:product, and event6 reports keys AND absolute
  coordinates — matched by vendor:product, keyd grabs event6 too and replays
  the touchpad through its virtual pointer as ABSOLUTE motion (finger on the
  pad = cursor teleports to that corner). keyd 2.6 ids have a third field, a
  per-node hash, so `0b05:1bf2:fb4e90cd` pins it to event29, the real keyboard.
  capslock→ctrl and the alt+hjkl nav layer confirmed working; the touchpad was
  only spot-checked, not corner-by-corner. Get the hash from `sudo keyd
  monitor`. UNVERIFIED: whether the hash survives a dock/undock cycle or a
  reboot. If it shifts, this line is dead and capslock falls back to
  hypr/base.lua kb_options — test with a replug before trusting it.
  Bluetooth (0b05:1bf3) has its own hash, not captured yet — capslock→ctrl for
  the detached case still comes from hypr/base.lua kb_options. Those device
  blocks are also fragile: Hyprland matches on device name and the keyboard
  shows up as `…-keyboard`, `…-keyboard-1`, `…-keyboard-2` depending on
  enumeration order, so only whichever one holds the rule gets it. A global
  `kb_options` in the input block would sidestep that if it ever bites.
- /etc/keyd was EMPTY — keyd only reads there, so the repo config had never
  been active on any host. install.sh now symlinks it in.
- Shell integration: OSD gained a `kbd` mode (`qs ipc call osd kbd <n>`) and the
  bar a `⌨ n/3` cell next to the brightness one (click cycles). The level can't
  be read back from the firmware and daemon/CLI/bar are three processes, so it
  lives in `$XDG_RUNTIME_DIR/duo-kbd-backlight`; Sys.qml polls that file so a
  quickshell restart doesn't lose it. Cell hides when the keyboard is detached.

Sources: DrSAR's PoC in asusctl issue #25 (repo moved to
OpenGamingCollective/asusctl), mainline hid-asus.c `asus_kbd_init()`.

Also fixed along the way: bluetoothd was never enabled (bluez-runit ships the
sv dir, install.sh now symlinks it); hyprpm state lives in /var/cache/hyprpm
and needs a real sudo prompt, so `hyprpm add` must be run by hand, not by an
agent shell; theme-apply's gsettings half was silently failing without a
session bus.

### Rotation / portrait

- `duo orientation` — accel + hinge angles + derived orientation.
  Sensors: `iio:device0` accel_3d, `iio:device2` hinge (3 labelled angles:
  hinge/screen/keyboard — usable later to tell laptop from book mode),
  `iio:device1` als. iio-sensor-proxy is installed but NOT used (no runit
  service, needs D-Bus); duo reads sysfs directly.
- **x is inverted vs the iio-sensor-proxy convention on this panel** — measured,
  not assumed: left edge up = x ≈ +9.4, right edge up = x ≈ -8.6, upright
  y ≈ -9. Threshold 5.0 m/s², plus two stable polls before acting.
- A mirrored output is ABSENT from `hyprctl monitors` even though it is on —
  only `hyprctl monitors all` lists it (with `disabled: false`). Anything asking
  "is eDP-2 on?" must use `all`, or it reports the sub screen as off whenever
  the layout is mirrored.
- Monitor rules are merge-not-replace: a rule that omits `mirror` leaves a
  previously set one in place, exactly as one omitting `disabled` leaves the
  output off. `layout stacked` out of `layout mirror` did nothing until every
  rule started passing `mirror = "none"` explicitly.
- `duo layout mirror-flip` is tent/share mode: both panels show the same thing
  with eDP-1 at transform 2 (180°), for someone sitting opposite.
- IIO device indices are NOT stable across boots — they follow probe order. On
  this machine the three HID sensors (als, accel_3d, hinge) can land on any of
  iio:device0..2. duo resolves them by their `name` file; hardcoding
  `iio:device0` is what silently broke autorotate (accel reads hit the ALS,
  which has no in_accel_* nodes, so every rotation failed "no accelerometer").
- `duo rotate auto|normal|left-up|right-up|bottom-up`, `duo autorotate on|off`
  (opt-in, off by default, remembered in ~/.local/state/duo/autorotate — NOT
  $XDG_RUNTIME_DIR, which is wiped each boot and silently reset it to off).
- Portrait re-lays the panels side by side, not just transformed. Sides are as
  OBSERVED: left-up puts eDP-1 on the right. Both monitor rules go in ONE
  hyprctl eval — applied separately there's an instant where one is rotated
  and the other isn't, and Hyprland shows an overlap warning.
- **hyprglass breaks layer surfaces on transformed outputs** — the quickshell
  bar renders nothing at all in portrait (space still reserved). Verified by
  unloading the plugin: bar came straight back. load-plugins.sh now skips it
  on binstar; other hosts unaffected, plugins.lua already fails soft.

Deferred: battery charge cap (dropped for now), span-as-one-screen (Hyprland
can't), hinge-based mode detection (don't auto-rotate in laptop mode), pen
pressure/buttons, other Duo
vendor keys (screenpad toggle 0x6a, screen swap 0x9c, MyASUS 0x86 — same 0x5a
channel, just need entries in duo's map), kbd backlight while detached (BT id
is 0b05:1bf3), keyd id for the bluetooth transport (0b05:1bf3 + its own
per-node hash), i915.enable_psr=0. Lid switch and hibernate are done — see
the Sleep / hibernate section.

## Sleep / hibernate (2026-08-23) — done

Use `loginctl suspend|hibernate|hybrid-sleep|poweroff|reboot` for everything.
polkit's `allow_active=yes` means no password from an active seat session.
Never `zzz`/`ZZZ` — runit's own scripts poke /sys/power/state directly, which
needs root and bypasses elogind (no inhibitor checks, nothing told to save).

### Lid close "sometimes" doesn't suspend — not a bug

elogind ignores the lid switch for 30s after every resume
(`HoldoffTimeoutSec`, default 30s), so rapid open/close testing misses every
other cycle. Measured with duo/lidlog.sh: nothing under 30s ever suspended,
nothing over 30s ever failed, zero exceptions. Lower it in
/etc/elogind/logind.conf if it ever gets annoying.

Suspend is s2idle (`/sys/power/mem_sleep` = `[s2idle] deep`) — rails stay up,
so the keyboard backlight stays lit while asleep. That is what s2idle looks
like, not a failure; `success` in /sys/power/suspend_stats and the wall-clock
gap both confirm real sleep.

### Hibernate froze the machine — fixed

Symptom: image written, power actually cut, then the screen came back on fully
frozen (no keyboard, touch or pad); only a power-button hold recovered, after
which it resumed the session correctly.

Cause: elogind's `HibernateMode` defaults to `platform shutdown` — a list whose
first entry it writes to /sys/power/disk immediately before hibernating, so
setting that file by hand is always stomped. `platform` enters ACPI S4 and this
firmware bounces straight back out ~40ms later, returning from a sleep that
never happened with devices already torn down (and cs35l41-hda then times out
with -110 on restore).

Fix: system/etc/elogind/sleep.conf.d/10-hibernate-shutdown.conf sets
`HibernateMode=shutdown` — image, then a plain pm_power_off(), no ACPI.
install.sh copies it. Resume needed nothing; resume=UUID + resume_offset= were
already on the limine cmdline. A ~2s frozen-looking flash on the way down is
cosmetic (panel relighting during teardown).

Dead ends ruled out on the way: /proc/acpi/wakeup S4 sources (AWAC, TXHC, TDM0,
TRP0, TRP1 — disabling all five changed nothing), USB-C charger wake, and
`hibernate=shutdown` on the kernel cmdline (elogind overrides it anyway).

## Next steps

1. dellstar cooling (dust/fan) — froze under sustained load, likely thermal;
   then optionally re-enable KVM there.
2. Maybe: prune-on-converge for packages (remove what's not in lists) — discussed,
   undecided.
3. Slow login / slow quickshell startup — cause not confirmed; hyprpm rebuild
   during autostart is the prime suspect and is now guarded off on binstar.
