#!/usr/bin/env bash
# Boot the built aarch64 image in QEMU on an Apple Silicon Mac.
#
#   ./scripts/run-vm.sh              graphical window (look at the desktop)
#   HEADLESS=1 ./scripts/run-vm.sh   serial console only (scripted testing)
#
# SSH into the running VM with:  ssh -p 2222 omarchy@localhost
set -euo pipefail

IMG="${IMG:-work/out/omarchy-pi.img}"
MEM="${MEM:-8192}"          # match the Pi 5 8GB target
CPUS="${CPUS:-4}"           # Pi 5 has 4 cores
SSH_PORT="${SSH_PORT:-2222}"
FW_CODE="${FW_CODE:-/opt/homebrew/share/qemu/edk2-aarch64-code.fd}"
VARS="${VARS:-work/efi-vars.fd}"

[ -f "$IMG" ] || { echo "Image not found: $IMG" >&2; exit 1; }

# UEFI needs a writable variable store, padded to 64M for edk2.
#
# Recreate it every boot rather than persisting it. A saved BootOrder entry
# encodes the disk's PCI device path and partition GUID, both of which change
# when the image is rebuilt or devices are added -- the stale entry then fails
# and the firmware drops to the UEFI shell instead of booting. An empty
# varstore makes the firmware fall back to the removable-media path
# (\EFI\BOOT\BOOTAA64.EFI), which always matches what we wrote.
mkdir -p "$(dirname "$VARS")"
dd if=/dev/zero of="$VARS" bs=1m count=64 status=none

ARGS=(
  -accel hvf -cpu host -machine virt,gic-version=3
  -smp "$CPUS" -m "$MEM"
  -drive "if=pflash,format=raw,readonly=on,file=$FW_CODE"
  -drive "if=pflash,format=raw,file=$VARS"
  -drive "if=virtio,format=raw,file=$IMG"
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
  -device virtio-net-pci,netdev=net0
  -device virtio-rng-pci
  -device qemu-xhci -device usb-kbd -device usb-tablet
)

if [ "${HEADLESS:-0}" = "1" ]; then
  ARGS+=( -display none -serial mon:stdio )
else
  ARGS+=( -device virtio-gpu-pci -display default,show-cursor=on -serial file:work/serial.log )
fi

echo "Booting $IMG  (ssh -p $SSH_PORT omarchy@localhost)"
exec qemu-system-aarch64 "${ARGS[@]}"
