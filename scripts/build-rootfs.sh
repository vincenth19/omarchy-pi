#!/usr/bin/env bash
# Build an Omarchy-on-aarch64 root filesystem.
#
# Runs INSIDE an Arch Linux ARM aarch64 container; the caller docker-exports the
# result and turns it into a disk image (see build-image.sh).
#
#   VARIANT=vm  -> generic linux-aarch64 kernel, UEFI boot (QEMU/UTM testing)
#   VARIANT=pi  -> linux-rpi kernel, Pi firmware boot (real hardware)
set -euo pipefail

VARIANT="${VARIANT:-vm}"
OMARCHY_REF="${OMARCHY_REF:-pi5}"
OMARCHY_REPO="${OMARCHY_REPO:-https://github.com/vincenth19/omarchy.git}"
USERNAME="${USERNAME:-omarchy}"
USERPASS="${USERPASS:-omarchy}"
LOCAL_REPO="${LOCAL_REPO:-/var/cache/omarchy-pi/repo}"

case "$VARIANT" in
  vm) KERNEL=linux-aarch64 ;;
  pi) KERNEL=linux-rpi ;;
  *)  echo "Unknown VARIANT: $VARIANT" >&2; exit 1 ;;
esac

echo "==> Configuring pacman (aarch64 / $VARIANT)"
cp /config/pacman/pacman-pi.conf /etc/pacman.conf
cp /config/pacman/mirrorlist-pi  /etc/pacman.d/mirrorlist

# Docker blocks pacman's Landlock sandbox. Disable it for the build only --
# it must land in [options], not appended after the last repo section --
# and strip it again before the rootfs ships.
sed -i '0,/^\[options\]/s//[options]\nDisableSandbox/' /etc/pacman.conf

# Our locally built aarch64 packages, exposed as a pacman repo. The database
# has to exist even when empty, or pacman -Sy fails the whole sync.
mkdir -p "$LOCAL_REPO"
if compgen -G "/pkgs/*.pkg.tar.*" > /dev/null; then
  cp /pkgs/*.pkg.tar.* "$LOCAL_REPO"/
  ( cd "$LOCAL_REPO" && repo-add -q omarchy-pi.db.tar.gz ./*.pkg.tar.* )
else
  echo "WARN: no prebuilt packages in /pkgs; omarchy-pi repo will be empty"
  ( cd "$LOCAL_REPO" && tar -czf omarchy-pi.db.tar.gz -T /dev/null && ln -sf omarchy-pi.db.tar.gz omarchy-pi.db )
fi

pacman -Syu --noconfirm

echo "==> Installing kernel and base system"
pacman -S --noconfirm --needed \
  base "$KERNEL" linux-firmware systemd sudo openssh networkmanager \
  git base-devel vim

echo "==> Installing Omarchy packages available for aarch64"
# Packages upstream lists that have no aarch64 build are handled by
# omarchy-pi's patch set; anything still missing is reported, not fatal.
mapfile -t WANT < <(grep -hv '^#' /omarchy/install/omarchy-base.packages | grep -v '^$')
AVAIL=(); SKIP=()
for p in "${WANT[@]}"; do
  # --print resolves `provides` too, so e.g. `nvim` is satisfied by `neovim`.
  # A plain `pacman -Si` lookup misses those and understates availability.
  if pacman -S --print-format '%n' "$p" >/dev/null 2>&1; then AVAIL+=("$p"); else SKIP+=("$p"); fi
done
echo "    installing ${#AVAIL[@]}, unavailable ${#SKIP[@]}: ${SKIP[*]:-none}"
printf '%s\n' "${SKIP[@]}" > /root/unavailable-packages.txt
pacman -S --noconfirm --needed "${AVAIL[@]}" || echo "WARN: some packages failed"

echo "==> Installing the omarchy package"
# Omarchy 4 ships as a pacman package installing to /usr/share/omarchy; it is
# not a git checkout. Ours comes from the local aarch64 repo built by
# build-pkgs.sh (upstream publishes x86_64 only).
if pacman -Si omarchy >/dev/null 2>&1; then
  pacman -S --noconfirm --needed omarchy || echo "WARN: omarchy package failed to install"
else
  echo "WARN: no omarchy package in local repo -- desktop will not be configured"
fi

echo "==> Creating user $USERNAME"
useradd -m -G wheel,video,audio,input,storage -s /bin/bash "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$USERPASS" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

echo "==> System configuration"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "omarchy-pi" > /etc/hostname
cat > /etc/fstab <<'FSTAB'
/dev/vda2  /      ext4  rw,relatime  0 1
/dev/vda1  /boot  vfat  rw,relatime  0 2
FSTAB
if [ "$VARIANT" = "pi" ]; then
  sed -i 's#/dev/vda#/dev/mmcblk0p#g; s#mmcblk0p1  /boot#mmcblk0p1 /boot#' /etc/fstab
fi

# Services. systemctl can't talk to a live systemd inside the container, so
# enable offline by creating the symlinks systemd would.
export SYSTEMD_OFFLINE=1
for svc in NetworkManager sshd; do
  systemctl enable "$svc" 2>/dev/null || echo "WARN: could not enable $svc"
done

if [ "$VARIANT" = "vm" ]; then
  echo "==> Enabling software rendering (VM has no real GPU)"
  # QEMU's virtio-gpu exposes a DRM device but no usable GL acceleration.
  # Without this Hyprland fails to pick a renderer and the session never
  # starts. The Pi variant must NOT get this -- it has a real V3D GPU.
  mkdir -p /etc/environment.d
  cat > /etc/environment.d/90-omarchy-pi-softrender.conf <<'ENVEOF'
LIBGL_ALWAYS_SOFTWARE=1
WLR_RENDERER_ALLOW_SOFTWARE=1
ENVEOF
  # environment.d covers the user session; SDDM and the compositor are started
  # by systemd units that read this too.
  mkdir -p /etc/systemd/system/sddm.service.d
  cat > /etc/systemd/system/sddm.service.d/softrender.conf <<'ENVEOF'
[Service]
Environment=LIBGL_ALWAYS_SOFTWARE=1
Environment=WLR_RENDERER_ALLOW_SOFTWARE=1
ENVEOF
fi

echo "==> Running Omarchy system setup"
# run_logged traps per-script failures instead of aborting, so this completes
# even where x86-specific steps do not apply; the log is what we grade.
if command -v omarchy-apply-system >/dev/null 2>&1; then
  SYSTEMD_OFFLINE=1 OMARCHY_LOG_TO_STDOUT=1 \
    omarchy-apply-system --install-user "$USERNAME" --first-install 2>&1 \
    | tee /root/omarchy-apply.log | grep -E "Starting:|Failed:|Completed:" || true
  echo "--- steps that failed ---"
  grep "Failed:" /root/omarchy-apply.log || echo "(none)"
else
  echo "WARN: omarchy-apply-system not found; skipping system setup"
fi

echo "==> Provisioning the user session"
# Home-directory setup that /etc/skel cannot seed. Must run as the user.
if command -v omarchy-provision-user >/dev/null 2>&1; then
  sudo -u "$USERNAME" -H bash -lc 'omarchy-provision-user --first-install' 2>&1 \
    | tail -5 || echo "WARN: omarchy-provision-user reported errors"
fi

# Autologin. On a real Omarchy install the ISO owns this, since only it knows
# whether the target is encrypted; our images are not, so we write it directly.
# omarchy-settings ships the omarchy.desktop session this points at.
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<AUTOEOF
[Autologin]
User=$USERNAME
Session=omarchy.desktop
AUTOEOF

if [ ! -f /usr/local/share/wayland-sessions/omarchy.desktop ]; then
  echo "WARN: omarchy.desktop session missing -- SDDM will have nothing to launch"
fi

echo "==> Generating initramfs"
mkinitcpio -P 2>&1 | tail -5 || echo "WARN: mkinitcpio issues"

echo "==> Restoring pacman sandbox"
sed -i '/^DisableSandbox$/d' /etc/pacman.conf

echo "==> Done. Kernel: $KERNEL, variant: $VARIANT"
