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
  # Drop any same-named copy from the shared pacman cache. Rebuilt packages
  # keep their version-release, so pacman would happily install a stale cached
  # tarball and silently ignore the rebuild.
  for p in /pkgs/*.pkg.tar.*; do rm -f "/var/cache/pacman/pkg/$(basename "$p")"; done
  ( cd "$LOCAL_REPO" && repo-add -q omarchy-pi.db.tar.gz ./*.pkg.tar.* )
else
  echo "WARN: no prebuilt packages in /pkgs; omarchy-pi repo will be empty"
  ( cd "$LOCAL_REPO" && tar -czf omarchy-pi.db.tar.gz -T /dev/null && ln -sf omarchy-pi.db.tar.gz omarchy-pi.db )
fi

pacman -Syu --noconfirm

echo "==> Installing kernel and base system"
pacman -S --noconfirm --needed \
  base "$KERNEL" linux-firmware systemd sudo openssh networkmanager \
  git base-devel vim e2fsprogs util-linux gptfdisk

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
# Root device differs by variant: virtio disk in QEMU, SD card on the Pi.
if [ "$VARIANT" = "vm" ]; then
  cat > /etc/fstab <<'FSTAB'
/dev/vda2  /      ext4  rw,relatime  0 1
/dev/vda1  /boot  vfat  rw,relatime  0 2
FSTAB
else
  cat > /etc/fstab <<'FSTAB'
/dev/mmcblk0p2  /      ext4  rw,relatime  0 1
/dev/mmcblk0p1  /boot  vfat  rw,relatime  0 2
FSTAB
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
  # OMARCHY_MIRROR=pi is load-bearing: post-install/pacman.sh restores
  # /etc/pacman.conf from default/pacman/pacman-$OMARCHY_MIRROR.conf, and the
  # default 'stable' variant would replace our ARM config with x86 mirrors.
  SYSTEMD_OFFLINE=1 OMARCHY_LOG_TO_STDOUT=1 OMARCHY_MIRROR=pi \
    omarchy-apply-system --install-user "$USERNAME" --first-install 2>&1 \
    | tee /root/omarchy-apply.log | grep -E "Starting:|Failed:|Completed:" || true
  echo "--- steps that failed ---"
  grep "Failed:" /root/omarchy-apply.log || echo "(none)"
else
  echo "WARN: omarchy-apply-system not found; skipping system setup"
fi

echo "==> Staging the bundled Node.js tarball"
# omarchy-provision-user --first-install runs in "iso-chroot" context and
# expects the ISO's bundled Node tarball at /opt/packages. We are not an ISO,
# so stage the aarch64 build ourselves rather than letting first-install fail.
mkdir -p /opt/packages
NODE_VER=$(curl -fsSL https://nodejs.org/dist/index.json \
  | jq -r '[.[] | select(.lts != false)][0].version') || NODE_VER=""
if [ -n "$NODE_VER" ] && [ "$NODE_VER" != "null" ] \
   && curl -fsSL -o "/opt/packages/node-${NODE_VER}-linux-arm64.tar.gz" \
        "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-arm64.tar.gz"; then
  echo "    staged node ${NODE_VER} (arm64)"
else
  echo "WARN: could not stage a Node tarball; mise will fall back to the network"
fi

# Test key for automated smoke tests. Only injected when the caller mounts one;
# release images built without it are password-only.
if [ -f /keys/id_omarchy.pub ]; then
  echo "==> Installing smoke-test SSH key"
  install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.ssh"
  install -m 600 -o "$USERNAME" -g "$USERNAME" /keys/id_omarchy.pub "/home/$USERNAME/.ssh/authorized_keys"
fi

# Be explicit about booting to a desktop. sddm enables itself through an
# Alias=display-manager.service, which is easy to mistake for "not enabled",
# and a default target of multi-user would leave the machine at a console.
echo "==> Installing first-boot filesystem expansion"
# The image ships a root partition just big enough for its contents. Without
# this, a 64 GB card would still present a ~13 GB root and fill up fast --
# building anything sizeable runs out of space. Every Pi distribution grows
# the root filesystem on first boot; ours must too.
cat > /usr/local/bin/omarchy-pi-expand-root <<'EXPANDEOF'
#!/bin/bash
# Grow the root partition and filesystem to fill the device.
#
# Idempotent by design: it decides from the actual on-disk state, not from a
# "have I run before" marker. A marker is wrong here because the image is
# booted during release testing, which would consume the first boot and leave
# every user's card unexpanded. Deciding from state also handles a card being
# imaged onto a larger one later.
set -euo pipefail

root_src=$(findmnt -no SOURCE /)
case "$root_src" in
  /dev/mmcblk*p*|/dev/nvme*p*) disk="${root_src%p*}"; num="${root_src##*p}" ;;
  /dev/sd*|/dev/vd*)           disk="${root_src%%[0-9]*}"; num="${root_src##*[a-z]}" ;;
  *) echo "Unrecognised root device: $root_src" >&2; exit 0 ;;
esac

# Sectors the device has, versus where our partition currently ends.
disk_sectors=$(blockdev --getsz "$disk")
part_start=$(cat "/sys/class/block/$(basename "$root_src")/start")
part_sectors=$(blockdev --getsz "$root_src")
part_end=$(( part_start + part_sectors ))

# GPT keeps a backup header at the end of the device; leave room for it plus
# a little slack, and do not churn for a trivially small gain.
slack=$(( 34 + 2048 ))
if (( disk_sectors - part_end <= slack )); then
  echo "Root partition already fills the device; nothing to do."
  exit 0
fi

echo "Growing $root_src: partition ends at $part_end of $disk_sectors sectors."
sgdisk --move-second-header "$disk" >/dev/null 2>&1 || true
echo ",+" | sfdisk --no-reread --force -N "$num" "$disk"
partx -u "$disk" || true
resize2fs "$root_src"
echo "Root filesystem now $(findmnt -no SIZE /)."
EXPANDEOF
chmod 755 /usr/local/bin/omarchy-pi-expand-root

cat > /etc/systemd/system/omarchy-pi-expand-root.service <<'EXPANDEOF'
[Unit]
Description=Expand the root filesystem to fill the disk
DefaultDependencies=no
After=systemd-remount-fs.service
Before=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/omarchy-pi-expand-root

[Install]
WantedBy=sysinit.target
EXPANDEOF
systemctl enable omarchy-pi-expand-root.service 2>/dev/null || echo "WARN: could not enable root expansion"

echo "==> Setting graphical.target as the default"
systemctl set-default graphical.target 2>/dev/null || ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target

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

echo "==> Installing omarchy-pi-doctor"
install -Dm755 /config/bin/omarchy-pi-doctor /usr/local/bin/omarchy-pi-doctor

echo "==> Installing the omarchy-pi initramfs drop-in"
# Additive: sorts after Omarchy's own drop-ins and adjusts the arrays, so an
# upstream rewrite of their files cannot break us and we never conflict on a
# file we do not own.
install -Dm644 /config/mkinitcpio/zz-omarchy-pi.conf /etc/mkinitcpio.conf.d/zz-omarchy-pi.conf

echo "==> Configuring a generic initramfs"
# mkinitcpio's `autodetect` hook trims modules to the hardware of the machine
# doing the build. We build in a container, so it would drop exactly the
# drivers the target needs -- virtio_blk in the VM, the SD/MMC stack on the Pi
# -- and the kernel would panic with no root device. Generic images must not
# autodetect.
sed -i 's/^HOOKS=(\(.*\)autodetect \(.*\))$/HOOKS=(\1\2)/' /etc/mkinitcpio.conf
if [ "$VARIANT" = "vm" ]; then
  sed -i 's/^MODULES=.*/MODULES=(virtio virtio_pci virtio_blk virtio_net virtio_gpu)/' /etc/mkinitcpio.conf
else
  sed -i 's/^MODULES=.*/MODULES=(mmc_block sdhci sdhci_pci sdhci_iproc bcm2835_dma)/' /etc/mkinitcpio.conf
fi
grep -E '^(HOOKS|MODULES)=' /etc/mkinitcpio.conf

echo "==> Generating initramfs"
# Keep the full log: mkinitcpio's summary line only says "errors were
# encountered", and truncating the output hides which hook or module caused it.
if mkinitcpio -P > /tmp/mkinitcpio.log 2>&1; then
  echo "    initramfs built cleanly"
else
  echo "WARN: mkinitcpio reported problems:"
  grep -aE '^==> (ERROR|WARNING)|error:' /tmp/mkinitcpio.log | head -20 | sed 's/^/      /'
fi

# Omarchy's firewall is "allow nothing in, everything out" (install/config/
# firewall.sh). That is the right default for a laptop and it is why the first
# smoke test could not reach port 22. VM images open SSH because the automated
# tests drive them over it; Pi release images keep Omarchy's closed default,
# since shipping a public image with SSH open on a known password would be
# indefensible. Override with ALLOW_SSH=1 when building a headless Pi.
ALLOW_SSH="${ALLOW_SSH:-$([ "$VARIANT" = vm ] && echo 1 || echo 0)}"
if [ "$ALLOW_SSH" = "1" ]; then
  echo "==> Scheduling the SSH firewall rule"
  # ufw cannot run here: it drives iptables, which needs NET_ADMIN, and the
  # build container has no such capability. Defer it to boot. `ufw allow` is
  # idempotent, so this needs no run-once marker -- and a marker would be
  # consumed by release testing before users ever see the image.
  cat > /etc/systemd/system/omarchy-pi-allow-ssh.service <<'UFWEOF'
[Unit]
Description=Allow SSH through the firewall (omarchy-pi)
After=ufw.service
Requires=ufw.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ufw allow ssh

[Install]
WantedBy=multi-user.target
UFWEOF
  systemctl enable omarchy-pi-allow-ssh.service 2>/dev/null || echo "WARN: could not enable ssh firewall unit"
else
  echo "==> Leaving SSH closed (Omarchy default); build with ALLOW_SSH=1 to open it"
fi

echo "==> Verifying pacman config survived post-install"
if grep -q "multilib\|stable-mirror.omarchy.org" /etc/pacman.conf; then
  echo "    post-install restored the x86 config; reapplying the Pi variant"
  cp /config/pacman/pacman-pi.conf /etc/pacman.conf
  cp /config/pacman/mirrorlist-pi  /etc/pacman.d/mirrorlist
fi

echo "==> Restoring pacman sandbox"
sed -i '/^DisableSandbox$/d' /etc/pacman.conf

echo "==> Done. Kernel: $KERNEL, variant: $VARIANT"
