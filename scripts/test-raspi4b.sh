#!/usr/bin/env bash
# Partial Pi-path boot test on QEMU's raspi4b (BCM2711).
#
# What this proves: the linux-rpi kernel boots, the initramfs finds root by
# PARTUUID on an SD controller, the MMC stack works, the Pi rootfs comes up.
# What it cannot prove: BCM2712, PCIe/NVMe, RP1, V3D, or the real firmware's
# config.txt handling (QEMU loads the kernel directly, bypassing start.elf).
# raspi4b hardwires a Cortex-A72, so this is TCG emulation -- slow.
set -uo pipefail
cd "$(dirname "$0")/.."
IMG=work/out/omarchy-pi.img; X=work/pi-boot; mkdir -p "$X"; SERIAL="$X/serial.log"
TIMEOUT="${TIMEOUT:-900}"

echo "==> Extracting kernel, initramfs, DTB and cmdline from the image's boot partition"
docker run --rm --platform linux/arm64 -v "$PWD/work:/w" alarm-work bash -c '
pacman -S --noconfirm --needed mtools >/dev/null 2>&1
dd if=/w/out/omarchy-pi.img of=/tmp/esp.img bs=1M skip=1 count=512 status=none
for f in kernel8.img initramfs-linux.img bcm2711-rpi-4-b.dtb cmdline.txt; do
  mcopy -o -i /tmp/esp.img ::/$f /w/pi-boot/$f 2>/dev/null && echo "   got $f" || echo "   MISSING $f"
done' || exit 1
for f in kernel8.img initramfs-linux.img bcm2711-rpi-4-b.dtb cmdline.txt; do [ -s "$X/$f" ] || { echo "cannot boot without $f"; exit 1; }; done
# The Pi 4 DTB aliases serial0 to the mini-UART (ttyS0); QEMU wires the first
# -serial to the PL011 (ttyAMA0) and the second to the mini-UART. Capture both,
# and let a retry add earlycon so silence can be told apart from a hang.
APPEND="$(tr -d '\n' < "$X/cmdline.txt" | sed 's/console=serial0,115200/console=ttyAMA0,115200 console=ttyS0,115200/')${EXTRA_APPEND:+ $EXTRA_APPEND}"
echo "   append: $APPEND"

echo "==> Booting raspi4b (TCG, up to ${TIMEOUT}s)"
: > "$SERIAL"
qemu-system-aarch64 -M raspi4b -m 2G -smp 4 \
  -kernel "$X/kernel8.img" -initrd "$X/initramfs-linux.img" -dtb "$X/bcm2711-rpi-4-b.dtb" \
  -append "$APPEND" \
  -drive "file=$IMG,if=sd,format=raw" \
  -display none -serial "file:$SERIAL" -serial "file:$X/serial-miniuart.log" -monitor none &
QP=$!; trap 'kill $QP 2>/dev/null' EXIT
deadline=$((SECONDS+TIMEOUT)); result="TIMEOUT"
while (( SECONDS < deadline )); do
  if cat "$SERIAL" "$X/serial-miniuart.log" 2>/dev/null | grep -aqE "login:"; then result="LOGIN_PROMPT"; break; fi
  if cat "$SERIAL" "$X/serial-miniuart.log" 2>/dev/null | grep -aqE "Kernel panic|VFS: Unable to mount root|end Kernel panic"; then result="PANIC"; break; fi
  kill -0 $QP 2>/dev/null || { result="QEMU_EXITED"; break; }
  sleep 10
done
kill $QP 2>/dev/null; wait $QP 2>/dev/null
echo "==> Result: $result after ${SECONDS}s"
echo "--- milestones ---"
sed 's/\x1b\[[0-9;]*m//g' "$SERIAL" | grep -aE "Booting Linux|Machine model|mmc0|mmcblk0|Reached target|Welcome to|login:|panic|Unable to mount|Cannot open root" | head -20
