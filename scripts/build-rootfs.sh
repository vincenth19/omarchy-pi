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
grep -q '^DisableSandbox' /etc/pacman.conf || echo 'DisableSandbox' >> /etc/pacman.conf

# Our locally built aarch64 packages, exposed as a pacman repo.
mkdir -p "$LOCAL_REPO"
if compgen -G "/pkgs/*.pkg.tar.*" > /dev/null; then
  cp /pkgs/*.pkg.tar.* "$LOCAL_REPO"/
  ( cd "$LOCAL_REPO" && repo-add -q omarchy-pi.db.tar.gz ./*.pkg.tar.* )
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
  if pacman -Si "$p" >/dev/null 2>&1; then AVAIL+=("$p"); else SKIP+=("$p"); fi
done
echo "    installing ${#AVAIL[@]}, unavailable ${#SKIP[@]}: ${SKIP[*]:-none}"
printf '%s\n' "${SKIP[@]}" > /root/unavailable-packages.txt
pacman -S --noconfirm --needed "${AVAIL[@]}" || echo "WARN: some packages failed"

echo "==> Creating user $USERNAME"
useradd -m -G wheel,video,audio,input,storage -s /bin/bash "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$USERPASS" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

echo "==> Installing Omarchy from $OMARCHY_REPO ($OMARCHY_REF)"
install -d -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.local/share"
git clone --depth 1 -b "$OMARCHY_REF" "$OMARCHY_REPO" "/home/$USERNAME/.local/share/omarchy"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.local"

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

echo "==> Generating initramfs"
mkinitcpio -P 2>&1 | tail -5 || echo "WARN: mkinitcpio issues"

echo "==> Done. Kernel: $KERNEL, variant: $VARIANT"
