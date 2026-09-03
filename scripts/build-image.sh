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
ROOT_MB="${ROOT_MB:-auto}"
ESP_MB="${ESP_MB:-512}"
ESP_START_MB=1

# Give the root partition a known PARTUUID so the kernel can find it without
# depending on a device node. The Pi 5 boots from SD, NVMe or USB and each
# presents a different name (mmcblk0p2 / nvme0n1p2 / sda2); PARTUUID is
# resolved by the kernel itself, before any initramfs runs, so one image works
# on all of them. Must be settled before the ESP is written, since both the
# systemd-boot entry and cmdline.txt embed it.
ROOT_PARTUUID="${ROOT_PARTUUID:-$(uuidgen | tr 'A-Z' 'a-z')}"

# Size the root partition from the actual rootfs plus headroom, so the image
# is neither truncated nor needlessly huge to download.
if [ "$ROOT_MB" = "auto" ]; then
  USED_MB=$(du -sm "$ROOTFS" | cut -f1)
  ROOT_MB=$(( USED_MB * 13 / 10 + 1024 ))
  echo "==> rootfs ${USED_MB}M -> root partition ${ROOT_MB}M"
fi

echo "==> Building ESP (${ESP_MB}M)"
ESP=/tmp/esp.img
dd if=/dev/zero of="$ESP" bs=1M count="$ESP_MB" status=none
mkfs.vfat -F32 -n OMARCHYPI "$ESP" >/dev/null

# Kernel naming differs by variant: the generic aarch64 kernel installs
# /boot/Image, while linux-rpi installs /boot/kernel8.img for the Pi firmware.
if [ "$VARIANT" = "vm" ]; then
  KERNEL_IMG=$(ls "$ROOTFS"/boot/Image 2>/dev/null | head -1)
  [ -n "$KERNEL_IMG" ] || { echo "No /boot/Image in $ROOTFS -- is linux-aarch64 installed?" >&2; exit 1; }
else
  KERNEL_IMG=$(ls "$ROOTFS"/boot/kernel*.img 2>/dev/null | head -1)
  [ -n "$KERNEL_IMG" ] || { echo "No /boot/kernel*.img in $ROOTFS -- is linux-rpi installed?" >&2; exit 1; }
  [ -d "$ROOTFS/boot/overlays" ] || echo "WARN: /boot/overlays missing; the V3D overlay will not load"
fi
INITRAMFS=$(ls "$ROOTFS"/boot/initramfs-*.img 2>/dev/null | grep -v fallback | head -1)
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
    echo "options root=PARTUUID=${ROOT_PARTUUID} rw console=ttyAMA0 console=tty0"
  } > /tmp/omarchy.conf
  mcopy -i "$ESP" /tmp/omarchy.conf ::/loader/entries/omarchy.conf
else
  # Raspberry Pi boots its own firmware off the FAT partition; no UEFI, no
  # bootloader. linux-rpi pulls in raspberrypi-bootloader and
  # firmware-raspberrypi, which drop start*.elf, fixup*.dat, the bcm2712
  # device trees and overlays/ into /boot -- the firmware needs all of it, so
  # mirror the whole tree rather than cherry-picking the kernel.
  ( cd "$ROOTFS/boot" && mcopy -i "$ESP" -s -b ./* ::/ )

  # Our config.txt/cmdline.txt override whatever the packages shipped.
  [ -f /config/boot/config.txt ]  && mcopy -i "$ESP" -o /config/boot/config.txt  ::/config.txt
  # cmdline.txt is generated, not copied: it must carry the PARTUUID this build
  # just assigned. The file in config/ holds a PLACEHOLDER precisely so that a
  # device path can never be shipped by accident -- a static root=/dev/mmcblk0p2
  # would boot from SD only, and silently, since SD is what gets tested first.
  if [ -f /config/boot/cmdline.txt ]; then
    sed "s|root=[^ ]*|root=PARTUUID=${ROOT_PARTUUID}|" /config/boot/cmdline.txt > /tmp/cmdline.txt
    mcopy -i "$ESP" -o /tmp/cmdline.txt ::/cmdline.txt
  fi
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
# sfdisk will not accept a named uuid= field mixed into a positional line
# (it rejects the script with "unsupported command"), so set the UUID as a
# second step -- and then read it back. The boot entry above already embeds
# this value; a table without it is an image that cannot find its root.
sfdisk --quiet --part-uuid "$OUT" 2 "$ROOT_PARTUUID"
if ! sfdisk -d "$OUT" | grep -qi "uuid=${ROOT_PARTUUID}"; then
  echo "root PARTUUID ${ROOT_PARTUUID} was not applied to partition 2" >&2
  exit 1
fi
echo "    root PARTUUID: $ROOT_PARTUUID (verified in table)"
dd if="$ESP"  of="$OUT" bs=1M seek="$ESP_START_MB" conv=notrunc status=none
dd if="$ROOT" of="$OUT" bs=1M seek="$(( ESP_START_MB + ESP_MB ))" conv=notrunc status=none

echo "==> Wrote $OUT ($(du -h "$OUT" | cut -f1))"
