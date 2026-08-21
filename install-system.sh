#!/bin/bash
# Artix (runit) system installer — run as root from the live ISO:
#   curl -LO https://raw.githubusercontent.com/JamesTiberiusKirk/dotsv2/master/install-system.sh
#   bash install-system.sh
# Interactive up front (disk pick + confirm), unattended after.
# Layout: GPT, 1G ESP at /boot, rest btrfs (@ @home @log @snapshots @swap),
# zstd+noatime, Limine, hibernate-capable swapfile (ram*2).
# Clones the dots repo to ~user/.dots and runs install.sh inside the chroot,
# so first boot lands on a fully converged system.
set -euo pipefail

HOSTNAME_DEFAULT=binstar
USER_DEFAULT=darthvader
REPO_HTTPS=https://github.com/JamesTiberiusKirk/dotsv2.git
REPO_SSH=git@github.com:JamesTiberiusKirk/dotsv2.git

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
command -v basestrap >/dev/null || { echo "not an Artix live ISO (basestrap missing)"; exit 1; }
# base ISO may lack fs tools (it lacked sgdisk once, too)
command -v mkfs.fat >/dev/null && command -v mkfs.btrfs >/dev/null \
  || pacman -Sy --needed --noconfirm dosfstools btrfs-progs

# ---- interactive part ----
lsblk -dno NAME,SIZE,MODEL
read -rp "install disk (e.g. nvme0n1): " DISK
DISK=/dev/$DISK
[ -b "$DISK" ] || { echo "$DISK is not a block device"; exit 1; }
read -rp "hostname [$HOSTNAME_DEFAULT]: " NEWHOST; NEWHOST=${NEWHOST:-$HOSTNAME_DEFAULT}
read -rp "username [$USER_DEFAULT]: " NEWUSER; NEWUSER=${NEWUSER:-$USER_DEFAULT}
ask_pw() {  # ask_pw <label> -> sets REPLY_PW
  local a b
  read -rsp "password for $1: " a; echo
  read -rsp "confirm: " b; echo
  [ "$a" = "$b" ] || { echo "passwords don't match"; exit 1; }
  [ -n "$a" ] || { echo "empty password"; exit 1; }
  REPLY_PW=$a
}
ask_pw root;      ROOT_PW=$REPLY_PW
ask_pw "$NEWUSER"; USER_PW=$REPLY_PW
read -rp "THIS WIPES $DISK COMPLETELY. type YES to continue: " OK
[ "$OK" = YES ] || exit 1

# ---- partition + filesystems ----
sfdisk --wipe always "$DISK" <<EOF
label: gpt
,1G,U
,,L
EOF
sleep 1
case $DISK in *nvme*|*mmcblk*) P=p;; *) P=;; esac
ESP=${DISK}${P}1 ROOT=${DISK}${P}2

mkfs.fat -F32 "$ESP"
mkfs.btrfs -f "$ROOT"

mount "$ROOT" /mnt
btrfs subvolume create /mnt/@ /mnt/@home /mnt/@log /mnt/@snapshots /mnt/@swap
umount /mnt

OPTS=compress=zstd,noatime,discard=async
mount -o "$OPTS,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,.snapshots,swap}
mount "$ESP" /mnt/boot
mount -o "$OPTS,subvol=@home"      "$ROOT" /mnt/home
mount -o "$OPTS,subvol=@log"       "$ROOT" /mnt/var/log
mount -o "$OPTS,subvol=@snapshots" "$ROOT" /mnt/.snapshots
mount -o noatime,subvol=@swap      "$ROOT" /mnt/swap
SWAP_SIZE=$(( ($(awk '/MemTotal/{print $2}' /proc/meminfo) * 2 / 1048576) + 1 ))g  # ram*2, rounded up
btrfs filesystem mkswapfile --size "$SWAP_SIZE" /mnt/swap/swapfile
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
swapon /mnt/swap/swapfile

# ---- base system ----
case $(grep -m1 vendor_id /proc/cpuinfo) in
  *Intel*) UCODE=intel-ucode;; *AMD*) UCODE=amd-ucode;; *) UCODE=;;
esac
basestrap /mnt base base-devel runit dbus-runit elogind-runit linux linux-firmware $UCODE \
  btrfs-progs networkmanager networkmanager-runit git openssh limine
fstabgen -U /mnt >> /mnt/etc/fstab

# ---- config inside chroot ----
echo "$NEWHOST" > /mnt/etc/hostname
UUID=$(blkid -s UUID -o value "$ROOT")

artix-chroot /mnt /bin/bash -e <<CHROOT
ln -sf /usr/share/zoneinfo/Europe/Chisinau /etc/localtime
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

useradd -m -G wheel "$NEWUSER"
printf '%s:%s\n' root "$ROOT_PW" "$NEWUSER" "$USER_PW" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

for s in dbus elogind NetworkManager; do
  ln -sf /etc/runit/sv/\$s /etc/runit/runsvdir/default/
done

cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $NEWHOST.localdomain $NEWHOST
EOF

# hibernation: resume hook (after udev, before filesystems) + rebuild initramfs
sed -i 's/^\(HOOKS=.*\) filesystems/\1 resume filesystems/' /etc/mkinitcpio.conf
grep -q ' resume ' /etc/mkinitcpio.conf || { echo "ERROR: resume hook not added to mkinitcpio.conf"; exit 1; }
mkinitcpio -P

# Limine (UEFI fallback path — no efibootmgr entry needed)
mkdir -p /boot/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cat > /boot/limine.conf <<EOF
timeout: 3

/Artix
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=UUID=$UUID rootflags=subvol=@ rw quiet resume=UUID=$UUID resume_offset=$RESUME_OFFSET
    module_path: boot():/initramfs-linux.img
EOF

# ssh key for github, printed at the end
sudo -u "$NEWUSER" mkdir -p -m 700 /home/$NEWUSER/.ssh
sudo -u "$NEWUSER" ssh-keygen -t ed25519 -N "" -f /home/$NEWUSER/.ssh/id_ed25519 -q

# clone the dots repo (https needs no auth; flip origin to ssh for later pushes)
sudo -u "$NEWUSER" -H git clone "$REPO_HTTPS" /home/$NEWUSER/.dots
sudo -u "$NEWUSER" -H git -C /home/$NEWUSER/.dots remote set-url origin "$REPO_SSH"

pacman -Sy
CHROOT

echo
echo "==== github ssh key for $NEWUSER — add at https://github.com/settings/keys ===="
cat /mnt/home/$NEWUSER/.ssh/id_ed25519.pub
echo "================================================================"

# ---- converge: packages (repo+AUR), dots-link, services, snapper — via install.sh ----
# as the user; passwordless sudo just for this run, reverted below. Output is
# logged to ~/install.log on the target; a failure stops the script LOUDLY.
LOG=/mnt/home/$NEWUSER/install.log
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /mnt/etc/sudoers.d/99-install
if artix-chroot /mnt sudo -u "$NEWUSER" -H bash -ec 'cd ~/.dots && ./install.sh' 2>&1 | tee "$LOG"; then
  rm /mnt/etc/sudoers.d/99-install
  echo "done. reboot and remove the USB/ISO."
else
  rm /mnt/etc/sudoers.d/99-install
  echo
  echo "########## install.sh FAILED — last lines of ~/install.log: ##########"
  tail -n 25 "$LOG"
  echo "######################################################################"
  echo "the system still boots (passwords are set); fix, then rerun ~/.dots/install.sh after boot."
  exit 1
fi
