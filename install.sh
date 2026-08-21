#!/bin/bash
# Converge this machine: packages, dots-link, services, snapshots.
# Run as your user from ~/.dots — install-system.sh runs it in the chroot,
# and it's idempotent, so rerun any time to repair/update.
set -euo pipefail

DOTS=$(dirname "$(readlink -f "$0")")
LISTS=$DOTS/.config/installed_packages
HOST=$(cat /etc/hostname)

[ "$(id -u)" != 0 ] || { echo "run as your user, not root"; exit 1; }

# ---- yay (built from AUR; makepkg refuses root, hence the user check above) ----
if ! command -v yay >/dev/null; then
  t=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$t"
  (cd "$t" && makepkg -si --noconfirm)
  rm -rf "$t"
fi

# ---- packages: common + fonts + per-host (pacman ones already done in chroot, --needed skips them) ----
files=$(ls "$LISTS/common.txt" "$LISTS/fonts.txt" "$LISTS/$HOST.txt" 2>/dev/null || true)
sort -u $files \
  | yay -S --needed --noconfirm - || echo "WARN: some packages failed — rerun later"

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
  sudo snapper --no-dbus create-config /
  # snapper recreates /.snapshots as a plain subvol; put our @snapshots back
  sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
  sudo mkdir -p /.snapshots && sudo mount /.snapshots
  sudo snapper --no-dbus set-config QGROUP=  # ponytail: no quotas — omarchy #3922 hourly-freeze regression
fi

# ---- hyprland plugins (best effort — needs hyprland headers/session) ----
command -v hyprpm >/dev/null && { hyprpm add https://github.com/hyprnux/hyprglass || true; hyprpm enable hyprglass || true; } || true

echo "done. log out/in (or reboot) for shell + services to settle."
