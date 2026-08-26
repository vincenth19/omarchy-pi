#!/usr/bin/env bash
# Assemble a bootable disk image from an exported rootfs.
#
# Deliberately avoids loop devices and mounting so it runs in an unprivileged
# container: ext4 is populated with `mke2fs -d`, the ESP with mtools, and the
# partitions are dd'd into a GPT disk at fixed offsets.
set -euo pipefail

ROOTFS="${ROOTFS:-/rootfs}"
OUT="${OUT:-/out/omarchy-pi.img}"
VARIANT="${VARIANT:-vm}"
ROOT_MB="${ROOT_MB:-12288}"
ESP_MB="${ESP_MB:-512}"
ESP_START_MB=1

echo "==> Building ESP (${ESP_MB}M)"
ESP=/tmp/esp.img
dd if=/dev/zero of="$ESP" bs=1M count="$ESP_MB" status=none
mkfs.vfat -F32 -n OMARCHYPI "$ESP" >/dev/null

KERNEL_IMG=$(ls "$ROOTFS"/boot/Image* 2>/dev/null | head -1)
INITRAMFS=$(ls "$ROOTFS"/boot/initramfs-*.img 2>/dev/null | grep -v fallback | head -1)
[ -n "$KERNEL_IMG" ] || { echo "No kernel found in $ROOTFS/boot" >&2; exit 1; }
echo "    kernel:    $(basename "$KERNEL_IMG")"
echo "    initramfs: $(basename "${INITRAMFS:-none}")"

if [ "$VARIANT" = "vm" ]; then
  # UEFI: systemd-boot at the removable-media fallback path so firmware
  # boots it with no NVRAM entry (matters for fresh QEMU/UTM VMs).
  mmd   -i "$ESP" ::/EFI ::/EFI/BOOT ::/loader ::/loader/entries
  mcopy -i "$ESP" "$ROOTFS/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" ::/EFI/BOOT/BOOTAA64.EFI
  mcopy -i "$ESP" "$KERNEL_IMG" ::/Image
  [ -n "$INITRAMFS" ] && mcopy -i "$ESP" "$INITRAMFS" ::/initramfs.img

  cat > /tmp/loader.conf <<'EOF'
default omarchy
timeout 1
console-mode max
EOF
  mcopy -i "$ESP" /tmp/loader.conf ::/loader/loader.conf

  {
    echo "title   Omarchy Pi"
    echo "linux   /Image"
    [ -n "$INITRAMFS" ] && echo "initrd  /initramfs.img"
    echo "options root=/dev/vda2 rw console=ttyAMA0 console=tty0"
  } > /tmp/omarchy.conf
  mcopy -i "$ESP" /tmp/omarchy.conf ::/loader/entries/omarchy.conf
else
  # Raspberry Pi boots its own firmware off the FAT partition; no UEFI.
  mcopy -i "$ESP" "$KERNEL_IMG" ::/kernel8.img
  [ -n "$INITRAMFS" ] && mcopy -i "$ESP" "$INITRAMFS" ::/initramfs-linux.img
  for f in "$ROOTFS"/boot/*.dtb; do [ -e "$f" ] && mcopy -i "$ESP" "$f" ::/ ; done
  if [ -d "$ROOTFS/boot/overlays" ]; then
    mmd -i "$ESP" ::/overlays
    for f in "$ROOTFS"/boot/overlays/*; do mcopy -i "$ESP" "$f" ::/overlays/ ; done
  fi
  [ -f /config/boot/config.txt ]  && mcopy -i "$ESP" /config/boot/config.txt  ::/config.txt
  [ -f /config/boot/cmdline.txt ] && mcopy -i "$ESP" /config/boot/cmdline.txt ::/cmdline.txt
fi

echo "==> Building ext4 root (${ROOT_MB}M)"
ROOT=/tmp/root.img
mke2fs -q -t ext4 -L omarchy-root -d "$ROOTFS" "$ROOT" "${ROOT_MB}M"

echo "==> Assembling GPT disk"
TOTAL_MB=$(( ESP_START_MB + ESP_MB + ROOT_MB + 2 ))
rm -f "$OUT"
truncate -s "${TOTAL_MB}M" "$OUT"
sfdisk --quiet --label gpt "$OUT" <<EOF
${ESP_START_MB}MiB,${ESP_MB}MiB,U,*
,,L
EOF
dd if="$ESP"  of="$OUT" bs=1M seek="$ESP_START_MB" conv=notrunc status=none
dd if="$ROOT" of="$OUT" bs=1M seek="$(( ESP_START_MB + ESP_MB ))" conv=notrunc status=none

echo "==> Wrote $OUT ($(du -h "$OUT" | cut -f1))"
