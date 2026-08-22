# binstar — install project state (2026-08-22)

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

## Next steps

1. NVMe install on the Zenbook: curl install-system.sh from raw master, pick
   internal nvme, swap = Y. Should converge unattended with the mirror fix.
2. Verify: zsh login, symlinks, `hyprx --shell`, snapper, ~/install.log summary.
3. binstar hardware pass: duo screens (binstar.lua), asusctl, binstar.txt.
4. dellstar cooling (dust/fan) — froze under sustained load, likely thermal;
   then optionally re-enable KVM there.
5. Maybe: prune-on-converge for packages (remove what's not in lists) — discussed,
   undecided.
