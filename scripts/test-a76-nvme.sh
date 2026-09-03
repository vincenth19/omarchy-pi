#!/usr/bin/env bash
# Full userspace test on the Pi 5's CPU core: the VM image (UEFI/systemd-boot)
# booted on virt with -cpu cortex-a76 (TCG), root on an emulated NVMe found by
# PARTUUID. Proves: NVMe boot path, and that nothing we ship uses instructions
# the A76 lacks (would surface as SIGILL). Not modelled: BCM2712, RP1, V3D.
set -uo pipefail
cd "$(dirname "$0")/.."
IMG=work/out/omarchy-vm.img; X=work/pi-boot; LOG=$X/vm-a76-serial.log; ERR=$X/vm-a76-qemu.err
PORT=2223; TIMEOUT="${TIMEOUT:-2700}"
[ -f "$IMG" ] || { echo "no $IMG"; exit 1; }
dd if=/dev/zero of=$X/a76-vars.fd bs=1m count=64 status=none; : > "$LOG"
qemu-system-aarch64 -M virt,gic-version=3 -cpu cortex-a76 -smp 4 -m 4G \
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=$X/a76-vars.fd \
  -drive "file=$IMG,if=none,id=nvm,format=raw,snapshot=on,file.locking=off" -device nvme,drive=nvm,serial=omarchypi \
  -netdev user,id=n0,hostfwd=tcp::$PORT-:22 -device virtio-net-pci,netdev=n0 -device virtio-rng-pci \
  -display none -serial "file:$LOG" -monitor none 2>"$ERR" &
QP=$!; trap 'kill $QP 2>/dev/null' EXIT
sleep 4; kill -0 $QP 2>/dev/null || { echo "QEMU failed to start:"; cat "$ERR"; exit 1; }
SSH=(ssh -i work/id_omarchy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR -o BatchMode=yes -p $PORT omarchy@localhost)
echo "==> Waiting for SSH on the A76 (TCG is slow; up to ${TIMEOUT}s)"; t0=$SECONDS; result=TIMEOUT
while (( SECONDS - t0 < TIMEOUT )); do
  "${SSH[@]}" true 2>/dev/null && { result=SSH_UP; break; }
  grep -aqE "Kernel panic|Unable to mount root" "$LOG" && { result=PANIC; break; }
  kill -0 $QP 2>/dev/null || { result=QEMU_EXITED; break; }
  sleep 15
done
echo "==> $result after $((SECONDS-t0))s"
if [ "$result" = SSH_UP ]; then
  R() { "${SSH[@]}" "$1" 2>/dev/null; }
  echo "--- cpu / root / state ---"
  R 'echo "cpu part: $(grep -m1 "CPU part" /proc/cpuinfo)"; echo "root: $(findmnt -no SOURCE /)"; echo "state: $(systemctl is-system-running)"; systemctl --failed --no-legend --no-pager | sed "s/^/failed: /"'
  echo "--- SIGILL sweep: run each shipped binary once ---"
  R 'for b in Hyprland quickshell foot chromium nvim btop lazygit lazydocker fzf rg eza bat zoxide starship jq gum yay mise omacalc omawrite aether cliamp ttfx tensaku localsend; do out=$(timeout 20 "$b" --version 2>&1 | head -1); rc=$?; printf "  %-10s rc=%-3s %s\n" "$b" "$rc" "${out:0:60}"; done'
  echo "--- illegal-instruction faults anywhere? ---"
  R 'sudo -n dmesg 2>/dev/null | grep -ciE "illegal instruction|SIGILL|undefined instruction" || journalctl -b --no-pager 2>/dev/null | grep -ciE "illegal instruction|SIGILL"'
  echo "--- desktop ---"
  R 'systemctl status sddm --no-pager -n 2 | sed -n 1,3p; ps -eo comm | grep -cE "^(Hyprland|quickshell)$"'
  echo "--- doctor ---"; R 'omarchy-pi-doctor 2>&1 | tail -3'
fi
echo "--- serial milestones ---"
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -aE "nvme0n1|EXT4-fs \(nvme|Welcome to|login:|panic|Illegal" | head -6
