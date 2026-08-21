#!/bin/bash
# Throwaway UEFI VM to test install-system.sh / install.sh.
#   ./test-vm.sh          fresh run: wipe disk, boot Artix ISO + virtual USB with this repo
#   ./test-vm.sh boot     boot the installed disk (test first-boot install.sh)
set -euo pipefail

DOTS=$(dirname "$(readlink -f "$0")")
WORK=~/isos
MIRROR=https://mirror1.artixlinux.org/iso
DISK=$WORK/binstar-test.qcow2
USB=$WORK/repo-usb.img
OVMF=/usr/share/edk2/x64

mkdir -p "$WORK"

# refuse to clobber a running VM's disk (rm -f bypasses qemu's own file lock)
if pgrep -x qemu-system-x86 >/dev/null; then  # comm truncates to 15 chars
  echo "a qemu VM is already running — close it first"; exit 1
fi

# latest base-runit ISO, downloaded once
ISO_NAME=$(curl -s "$MIRROR/" | grep -oE 'artix-base-runit-[0-9]+-x86_64\.iso' | sort -u | tail -1) \
  || { echo "mirror unreachable: $MIRROR"; exit 1; }
ISO=$WORK/$ISO_NAME
[ -f "$ISO" ] || curl -Lo "$ISO" "$MIRROR/$ISO_NAME"

if [ "${1:-}" != boot ]; then
  # fresh throwaway disk + virtual USB stick carrying the repo
  rm -f "$DISK"
  qemu-img create -f qcow2 "$DISK" 40G
  rm -f "$USB"
  truncate -s 2G "$USB"
  mkfs.fat -F32 "$USB"
  mcopy -i "$USB" -s "$DOTS" ::/dots   # mtools: copy repo in without mounting
  CDROM=(-cdrom "$ISO" -boot d)
else
  CDROM=()
fi

cp -f "$OVMF/OVMF_VARS.4m.fd" "$WORK/vars.fd"
qemu-system-x86_64 \
  -name test-vm \
  -accel tcg -m 4G -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF/OVMF_CODE.4m.fd" \
  -drive if=pflash,format=raw,file="$WORK/vars.fd" \
  -drive file="$DISK",if=virtio \
  -drive file="$USB",format=raw,if=none,id=usb -device usb-storage,drive=usb \
  -usb -device usb-tablet \
  "${CDROM[@]}"

# in the live VM:  mount /dev/sda1 /mnt2 && /mnt2/dots/install-system.sh
