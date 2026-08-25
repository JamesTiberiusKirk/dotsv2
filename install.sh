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

# ---- groups: video = backlight sysfs, input = hidraw (duo's kbd handshake), docker = socket ----
for g in video input docker; do
  getent group "$g" >/dev/null || continue   # pkg missing -> group missing, don't abort
  id -nG "$USER" | grep -qw "$g" || sudo usermod -aG "$g" "$USER"
done

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
# package-provided services that just need enabling (bluez-runit ships the sv dir)
[ ! -d /etc/runit/sv/bluetoothd ] || sudo ln -sf /etc/runit/sv/bluetoothd /etc/runit/runsvdir/default/
# power-profiles-daemon-runit ships the sv dir; the bar's profile selector is
# hidden until this is up (no daemon on the bus -> no rows)
[ ! -d /etc/runit/sv/power-profiles-daemon ] || sudo ln -sf /etc/runit/sv/power-profiles-daemon /etc/runit/runsvdir/default/
# docker-runit ships the sv dir; link it but leave it down — start with `sv up docker`
if [ -d /etc/runit/sv/docker ]; then
  sudo touch /etc/runit/sv/docker/down
  sudo ln -sfn /etc/runit/sv/docker /etc/runit/runsvdir/default/
fi

# ---- keyd: the daemon only reads /etc/keyd, so link the repo config in ----
if [ -d /etc/keyd ] || sudo mkdir -p /etc/keyd; then
  sudo ln -sfn "$DOTS/.config/keyd/default.conf" /etc/keyd/default.conf
  sudo keyd reload 2>/dev/null || true
fi

# ---- udev rules from the repo (hidraw access for duo, etc.) ----
if [ -d "$DOTS/system/etc/udev/rules.d" ]; then
  sudo cp "$DOTS"/system/etc/udev/rules.d/*.rules /etc/udev/rules.d/
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=hidraw
fi

# ---- DNS: stop tailscale mistaking Artix for a systemd box ----
# Arch's filesystem package ships `resolve` (systemd-resolved's NSS module) in
# the hosts line. Artix has no systemd, libnss_resolve.so does not exist, and the
# entry is dead — but tailscale reads it, concludes resolved is running, talks to
# a D-Bus name nobody owns, and MagicDNS silently never applies. Idempotent, so
# existing hosts pick it up on the next converge.
if grep -q '^hosts:.*resolve' /etc/nsswitch.conf; then
  sudo sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf
  restart_net=1
fi
# and hand resolv.conf to openresolv so NetworkManager and tailscale arbitrate
# through it rather than overwriting each other's file
if [ ! -f /etc/NetworkManager/conf.d/rc-manager.conf ]; then
  sudo mkdir -p /etc/NetworkManager/conf.d
  printf '[main]\nrc-manager=resolvconf\n' | sudo tee /etc/NetworkManager/conf.d/rc-manager.conf >/dev/null
  restart_net=1
fi
# quickshell's NetworkManager client does not survive an NM restart, so this is
# deliberately left to the next reboot rather than bouncing the service here
[ -z "${restart_net:-}" ] || echo "note: DNS config changed — reboot (or restart NetworkManager + tailscale) to apply"

# ---- pam_gnome_keyring: auto-unlock the secret keyring at login (must be named "login") ----
grep -q pam_gnome_keyring.so /etc/pam.d/login || sudo sed -i \
  -e '/^session.*include.*system-local-login/a session  optional  pam_gnome_keyring.so auto_start' \
  -e '/^auth.*requisite.*pam_nologin.so/a auth     optional  pam_gnome_keyring.so' \
  /etc/pam.d/login
grep -q pam_gnome_keyring.so /etc/pam.d/passwd || sudo sed -i \
  '/^password.*include.*system-auth/a password optional  pam_gnome_keyring.so' \
  /etc/pam.d/passwd

# ---- elogind sleep drop-ins (hibernate power-off mode; see the conf comments) ----
if [ -d "$DOTS/system/etc/elogind/sleep.conf.d" ]; then
  sudo mkdir -p /etc/elogind/sleep.conf.d
  sudo cp "$DOTS"/system/etc/elogind/sleep.conf.d/*.conf /etc/elogind/sleep.conf.d/
fi

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
# Skipped on binstar for the same reason hypr/scripts/load-plugins.sh bails
# there: hyprglass stops layer surfaces (the quickshell bar) rendering at all on
# an output with a transform, so the bar vanishes when duo(1) rotates to
# portrait. Without this guard a plain install.sh rerun re-enables and loads it.
if [ "$HOST" != binstar ] && command -v hyprpm >/dev/null; then
  hyprpm add https://github.com/hyprnux/hyprglass || true
  hyprpm enable hyprglass || true
fi

echo "done. log out/in (or reboot) for shell + services to settle."
