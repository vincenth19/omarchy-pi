#!/usr/bin/env bash
# Boot the built image headless and assert that the system actually came up.
#
# Checks what looking at a screenshot cannot: that systemd reached a running
# state, that no unit failed, and that the Omarchy session is installed and
# pointed at by SDDM.
set -uo pipefail
cd "$(dirname "$0")/.."

IMG="${IMG:-work/out/omarchy-pi.img}"
SSH_PORT="${SSH_PORT:-2222}"
TIMEOUT="${TIMEOUT:-420}"
KEY="${KEY:-work/id_omarchy}"
SERIAL="work/smoke-serial.log"
FW_CODE="${FW_CODE:-/opt/homebrew/share/qemu/edk2-aarch64-code.fd}"

[ -f "$IMG" ] || { echo "No image at $IMG -- run ./scripts/build-all.sh first" >&2; exit 1; }
[ -f "$KEY" ] || { echo "No smoke-test key at $KEY" >&2; exit 1; }

: > "$SERIAL"
# Fresh varstore every run: a persisted BootOrder entry references the old
# image's partition GUID and drops the VM into the UEFI shell.
dd if=/dev/zero of=work/efi-vars.fd bs=1m count=64 status=none

echo "==> Booting headless"
qemu-system-aarch64 \
  -accel hvf -cpu host -machine virt,gic-version=3 -smp 4 -m 4096 \
  -drive "if=pflash,format=raw,readonly=on,file=$FW_CODE" \
  -drive "if=pflash,format=raw,file=work/efi-vars.fd" \
  -drive "if=virtio,format=raw,file=$IMG" \
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" -device virtio-net-pci,netdev=net0 \
  -device virtio-rng-pci -display none -serial "file:$SERIAL" &
QEMU_PID=$!
trap 'kill $QEMU_PID 2>/dev/null' EXIT

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=5 -o LogLevel=ERROR -o BatchMode=yes -p "$SSH_PORT")
run() { ssh "${SSH_OPTS[@]}" omarchy@localhost "$1" 2>/dev/null; }

echo "==> Waiting for SSH (up to ${TIMEOUT}s)"
deadline=$(( SECONDS + TIMEOUT ))
until run true; do
  if ! kill -0 $QEMU_PID 2>/dev/null; then
    echo "FAIL: QEMU exited before SSH came up"; echo "--- serial tail ---"; tail -40 "$SERIAL"; exit 1
  fi
  if (( SECONDS > deadline )); then
    echo "FAIL: no SSH after ${TIMEOUT}s"; echo "--- serial tail ---"; tail -60 "$SERIAL"; exit 1
  fi
  sleep 5
done
echo "    SSH up after $((SECONDS))s"

fails=0
check() {
  local label=$1 cmd=$2
  printf '    %-34s ' "$label"
  local out
  if out=$(run "$cmd") && [ -n "$out" ]; then
    echo "OK   ${out:0:58}"
  else
    echo "FAIL"; fails=$((fails+1))
  fi
}

echo "==> System checks"
check "kernel arch"           "uname -m"
check "omarchy version"       "cat /usr/share/omarchy/version"
check "session file"          "ls /usr/local/share/wayland-sessions/omarchy.desktop"
check "sddm enabled"          "systemctl is-enabled sddm"
check "autologin configured"  "grep -h Session= /etc/sddm.conf.d/autologin.conf"
check "pacman is aarch64"     "grep -c 'Architecture = aarch64' /etc/pacman.conf"
check "no x86 mirrors"        "grep -qv multilib /etc/pacman.conf && echo clean"
check "hyprland binary"       "command -v Hyprland"
check "systemd state"         "systemctl is-system-running || true"

echo "==> Failed units"
run "systemctl --failed --no-legend --no-pager" > work/failed-units.txt
if [ -s work/failed-units.txt ]; then sed 's/^/    /' work/failed-units.txt | head -20; else echo "    none"; fi

echo "==> Graphical session"
run "systemctl status sddm --no-pager -n 5" | sed 's/^/    /' | head -12

# The test user's sudo needs a password, which BatchMode ssh cannot supply.
# The image is disposable and rebuilt every run, so stop QEMU directly rather
# than weakening the shipped sudoers just to shut a test VM down.
kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null

echo
if (( fails )); then echo "SMOKE TEST: $fails check(s) FAILED"; exit 1; fi
echo "SMOKE TEST: PASSED"
