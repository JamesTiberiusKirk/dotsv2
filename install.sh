#!/bin/bash
# Converge this machine: packages, dots-link, services, snapshots.
# Run as your user from ~/.dots — install-system.sh runs it in the chroot,
# and it's idempotent, so rerun any time to repair/update.
set -euo pipefail

DOTS=$(dirname "$(readlink -f "$0")")
LISTS=$DOTS/.config/installed_packages
HOST=$(cat /etc/hostname)

[ "$(id -u)" != 0 ] || { echo "run as your user, not root"; exit 1; }

# `./install.sh extra-pkgs` — heavy optional stuff (extras.txt), on demand only
[ "${1-}" != extra-pkgs ] || exec yay -S --needed $(grep -v '^#' "$LISTS/extras.txt")

# ---- yay (built from AUR; makepkg refuses root, hence the user check above) ----
if ! command -v yay >/dev/null; then
  t=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$t"
  (cd "$t" && makepkg -si --noconfirm)
  rm -rf "$t"
fi

# ---- Arch repos on top of Artix (discord, httpie, etc. live there) ----
if ! grep -q '^\[extra\]' /etc/pacman.conf; then
  sudo pacman -S --needed --noconfirm artix-archlinux-support
  grep -q 'geo.mirror.pkgbuild.com' /etc/pacman.d/mirrorlist-arch 2>/dev/null \
    || echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' | sudo tee -a /etc/pacman.d/mirrorlist-arch >/dev/null
  printf '\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch\n\n[multilib]\nInclude = /etc/pacman.d/mirrorlist-arch\n' | sudo tee -a /etc/pacman.conf >/dev/null
  sudo pacman-key --populate archlinux
  sudo pacman -Sy
fi

# ---- makepkg: build in RAM, all cores, skip package compression ----
sudo mkdir -p /etc/makepkg.conf.d
printf 'BUILDDIR=/tmp/makepkg\nMAKEFLAGS="-j$(nproc)"\nPKGEXT=".pkg.tar"\n' | sudo tee /etc/makepkg.conf.d/speed.conf >/dev/null

# ---- packages: common + fonts + per-host (pacman ones already done in chroot, --needed skips them) ----
files=$(ls "$LISTS/common.txt" "$LISTS/fonts.txt" "$LISTS/$HOST.txt" 2>/dev/null || true)
all=$(sort -u $files)
# repo packages first via pacman (one reliable batch), then AUR one at a time —
# yay aborts a whole transaction over one unresolvable AUR dep, and `yay -S -`
# (stdin mode) reopens /dev/tty which dies in a chroot, so: args only.
repo=$(echo "$all" | while read -r p; do pacman -Si "$p" >/dev/null 2>&1 && echo "$p"; done)
aur=$(comm -23 <(echo "$all") <(echo "$repo"))
# interactive by default so conflicts can be resolved at the prompt;
# install-system.sh sets DOTS_NOCONFIRM=1 for the unattended chroot run
sudo pacman -S --needed ${DOTS_NOCONFIRM:+--noconfirm} $repo
failed=
for p in $aur; do
  yay -S --needed --noconfirm "$p" || failed="$failed $p"
done
[ -z "$failed" ] || echo "WARN: AUR packages failed:$failed — rerun install.sh later"

# ---- login shell: zsh (arrives with the package pass; useradd left bash) ----
[ "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/zsh ] || sudo chsh -s /usr/bin/zsh "$USER"

# ---- dots-link: build + link this host's manifest (go comes from the package pass) ----
export PATH=$PATH:$HOME/go/bin
(cd "$DOTS" && make install)
# DOTS_HOST: in the install chroot the kernel hostname is still the live ISO's
DOTS_HOST=$HOST dots-link sync --remote --yes

# ---- runit services from the repo (keyd, ntpd, tailscale) + install-time ones ----
for sv in "$DOTS"/system/etc/runit/sv/*/; do
  name=$(basename "$sv")
  sudo cp -r "$sv" /etc/runit/sv/
  sudo ln -sf "/etc/runit/sv/$name" /etc/runit/runsvdir/default/
done

# ---- snapper + bootable snapshots (omarchy-style, no btrfs quotas) ----
yay -S --needed --noconfirm snapper snap-pac limine-snapper-sync || true
if ! sudo snapper list-configs 2>/dev/null | grep -q root; then
  sudo umount /.snapshots 2>/dev/null || true
  sudo rmdir /.snapshots 2>/dev/null || true  # create-config makes the subvol itself, dies if the dir exists
  sudo snapper --no-dbus create-config /
  # snapper recreates /.snapshots as a plain subvol; put our @snapshots back
  sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
  sudo mkdir -p /.snapshots && sudo mount /.snapshots
  sudo snapper --no-dbus set-config QGROUP=  # ponytail: no quotas — omarchy #3922 hourly-freeze regression
fi

# ---- hyprland plugins (best effort — needs hyprland headers/session) ----
command -v hyprpm >/dev/null && { hyprpm add https://github.com/hyprnux/hyprglass || true; hyprpm enable hyprglass || true; } || true

echo "done. log out/in (or reboot) for shell + services to settle."
