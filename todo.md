# TODOs
- [x] remove `--shell` from the hyprx script and just make it defualt
- [x] see if u can make the password promt not open up on running hyprland manually
- [x] make browser bitwarden float by default
- [x] enable hyprglass agian
- [x] remove all the x11 stuff (i3, waybar, dunst, wofi, picom, .xinitrc, .Xresources)
- [ ] on startup in laptop mode sub screen was on until i took kb off and put it on again
    - tried settling the initial read + re-asserting after 4s in duo/watch.go, still broken
- [ ] palm rejection
- [ ] interactable quickshell module for the displays brightness and layout
- [ ] figure out whats going on with the shell frame around the center
- [ ] actually properly figure out keyd bindings
    - parity between docked and undocked
    - undocked alt +hjkl does not work
- [ ] look at the actual sleep again, funky issues with keyboard backlight to sleeping
- [ ] steal the mod space menu from omarchy. so it includes not just apps but other actions like poweroff, reboot, suspend, hibernate etc
- [ ] steal theme switcher from omarchy
- [ ] setup power profiles (like in omarchy)
- [ ] setup clanker usage (rip from omarchy)
- [ ] startup we get flashed with the keybaord brightness inicator at the bottom
    - duo/kbd.go:47 fires the OSD on the startup backlight apply
- [ ] figure out autorotate
    - state file is in $XDG_RUNTIME_DIR so it resets to off every reboot
- [ ] quickshell stuff
    - center window element shows same across screens, needs to what its got on its own screen
        - sometimes that does not happen....
    - show an indicator for the currently active monitor
- [ ] keyboard slate over bluetooth works just fine as inteded
    - but i connect it to the pogos, the only thing that is working is the function keuys we mapped and the tocuhopad, actual keys dont work
    - hyprland can't open keyd's virtual keyboard at startup (EPERM); `sudo sv restart keyd` after login fixes it
- [ ] sleep time out so it goes into hibernate
- [ ] a propper fully fledged notif center

## PLAN (approved): system-file sync in dots-link + T650 wake fix
Problem: unifying receiver USB-autosuspends after 2s (046d:c52b, power/control=auto) → T650 feels asleep. Fix via udev rule, deployed through a new system-sync step in dots-link.

Settled design (do not re-litigate):
- copy, not symlink (early-boot: /home may not be mounted when udev reads rules)
- check without sudo (byte-compare repo vs installed, files are world-readable); sudo only to apply
- per-file approval; `--yes` skips prompts (install.sh chroot needs this)
- lives in dots-link sync; one-off edits (nsswitch/pam/NM) stay install.sh-only

Files:
- NEW `system/etc/udev/rules.d/60-logitech-receiver-no-autosuspend.rules`:
  `ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="c52b", TEST=="power/control", ATTR{power/control}="on"`
  (must be add|change — `udevadm trigger` emits change, add-only never applies without replug)
- NEW `dots-link/system.go`: hardcoded 4-mapping table:
  - system/etc/udev/rules.d → /etc/udev/rules.d; hook once after all copies: `udevadm control --reload` + `udevadm trigger --subsystem-match=usb` (+hidraw/cpu/pci like install.sh)
  - system/etc/elogind/sleep.conf.d → /etc/elogind/sleep.conf.d
  - system/etc/elogind/system-sleep → /lib/elogind/system-sleep, chmod 755
  - system/etc/runit/sv → /etc/runit/sv (DIRECTORY TREES — walk, not flat) + ensure enable symlink in /etc/runit/runsvdir/default/
- EDIT `dots-link/sync.go`: system diff computed in PLAN phase, rendered with home plan, applied in applySync. NOT "at the end of runSync" — early returns (dry-run, "nothing to do" when home is clean) would skip it.
- mkdir -p dst dirs; unreadable dst = flagged "verify with sudo", never guessed
- skipped: deletion of repo-removed files (no system manifest; add when it bites); install.sh copy blocks stay (idempotent dupe, dedup later)
- after implementing: apply rule to this machine + reload so the fix is live now
