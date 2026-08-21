# binstar — install project state (2026-08-21)

Asus Zenbook Duo. Artix runit, btrfs, Limine. Resumed from dellstar session.

## What exists

- `install-system.sh` (repo root) — live-ISO installer: interactive disk/hostname/user
  + two password pairs up front, then unattended: GPT (1G ESP at /boot + btrfs),
  subvols `@ @home @log @snapshots @swap` (zstd, noatime, discard=async), swapfile
  ram*2 with hibernate (resume + resume_offset on cmdline, resume hook in
  mkinitcpio), basestrap w/ ucode autodetect, dbus/elogind/NetworkManager enabled,
  Limine via EFI fallback path, ssh keygen (pubkey printed at end), https-clones
  this repo to ~user/.dots (origin flipped to ssh), then runs install.sh in the
  chroot with temp NOPASSWD; converge output tees to ~/install.log and a failure
  stops LOUDLY with the log tail. Entry: curl the raw script from GitHub master.
- `install.sh` — idempotent converge: yay-bin (built if missing), repo packages in
  one pacman batch then AUR one-by-one w/ failure summary (yay stdin mode dies in
  chroot — args only), chsh to zsh, `make install` + `dots-link sync --remote -y`
  (DOTS_HOST env for chroot), repo runit services (keyd/ntpd/tailscale), snapper +
  snap-pac + limine-snapper-sync (QGROUP= — no quotas, omarchy freeze bug), hyprpm
  hyprglass best-effort.
- `test-vm.sh` — throwaway UEFI qemu test: fresh disk + FAT usb image carrying the
  working tree (`/mnt2/dots/…` after `mount /dev/sda /mnt2`); `boot` arg boots the
  installed disk. Fresh OVMF vars each run (stale NVRAM broke boot once). Guard
  against concurrent runs (second instance's rm -f clobbered a live install once).
- Package lists: dellstar.txt + deathstar.txt added; common.txt cleaned (dep-installed
  essentials like hyprland/pipewire/zsh added; broken-AUR + hardware + heavy
  toolchains moved per-host; hosts/binstar manifest = copy of dellstar's).

## Verified in VM

Full flow through: partition → basestrap → Limine boot → login (passwords via
chpasswd early) → clone → converge started; repo-package batch + many AUR builds
ran. NOT yet verified end-to-end: converge completing, dots-link result, snapper,
first graphical session (hyprland is in common.txt now; hyprx --shell untested).

## Open problem: dellstar freezes (why we moved to desktop)

dellstar hard-froze 4-5x during VM runs — first blamed KVM (6.18.41-lts + qemu
11.1, whose virtio-vga also segfaults), but it froze under pure TCG too, so the
common factor is sustained all-core load. Idle cores 50-57°C with fan at 0 RPM →
prime suspect: cooling/thermal hard-freeze (no kernel trace ever; logs stop
mid-line). Unconfirmed test: `stress-ng --cpu 4` + watch sensors, no VM. test-vm.sh
currently uses `-accel tcg -smp 2` because of this; on a healthy host switch back
to `-enable-kvm -cpu host` and more cores/RAM for sane speed.

## Next steps (desktop)

1. `git pull`, run `./test-vm.sh` (KVM again — deathstar is healthy), full install,
   `./test-vm.sh boot`, verify: zsh login, symlinks, `hyprx --shell`, snapper,
   `~/install.log` AUR failure summary.
2. Fix whatever the converge still trips on (AUR long-tail).
3. Separately: dellstar cooling (dust/fan), then optionally retest KVM there.
4. Real Zenbook when it arrives: curl install-system.sh from raw GitHub, no USB
   repo needed; add binstar hardware pass (duo screens, asusctl, binstar.txt).
