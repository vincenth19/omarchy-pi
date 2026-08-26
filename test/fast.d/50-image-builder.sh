#!/usr/bin/env bash
# Guards on the build scripts themselves. Each of these was a real failure that
# produced a broken or unbootable image.
source "$(dirname "$0")/../lib.sh"
RF="$ROOT/scripts/build-rootfs.sh"
BI="$ROOT/scripts/build-image.sh"
BA="$ROOT/scripts/build-all.sh"

# mkinitcpio's autodetect trims modules to the BUILD machine's hardware. In a
# container that drops the target's own drivers and the kernel panics with no
# root device. Generic images must never autodetect.
assert_grep 'autodetect' "$RF" "rootfs build strips the autodetect hook"

# Variant-specific drivers must be in the initramfs.
assert_grep 'virtio_blk' "$RF" "VM initramfs includes virtio_blk"
assert_grep 'mmc_block' "$RF" "Pi initramfs includes the SD/MMC stack"

# A rebuilt package keeps its version-release, so pacman will happily install
# the stale cached tarball and ignore the rebuild.
assert_grep 'rm -f "/var/cache/pacman/pkg/' "$RF" "rebuilt packages are evicted from the pacman cache"

# post-install/pacman.sh overwrites /etc/pacman.conf from the stable (x86)
# variant unless OMARCHY_MIRROR selects ours.
assert_grep 'OMARCHY_MIRROR=pi' "$RF" "OMARCHY_MIRROR=pi is passed to apply-system"
assert_grep 'multilib' "$RF" "rootfs build verifies the x86 config was not restored"

# The user must be created after omarchy-settings populates /etc/skel;
# useradd only copies skel at creation time.
skel_line=$(grep -n 'Installing the omarchy package' "$RF" | cut -d: -f1)
user_line=$(grep -n 'Creating user' "$RF" | cut -d: -f1)
if [ -n "$skel_line" ] && [ -n "$user_line" ] && [ "$skel_line" -lt "$user_line" ]; then
  ok "omarchy package is installed before the user is created"
else
  bad "omarchy package is installed before the user is created" \
      "otherwise the home directory misses /etc/skel content"
fi

# The kernel is named differently per variant: Image vs kernel8.img.
assert_grep 'kernel\*\.img' "$BI" "image builder detects the Pi kernel (kernel*.img)"
assert_grep 'boot/Image' "$BI" "image builder detects the VM kernel (Image)"

# A persisted UEFI varstore encodes the old image's partition GUID and drops
# the VM into the UEFI shell.
assert_grep 'dd if=/dev/zero of="\$VARS"' "$ROOT/scripts/run-vm.sh" "run-vm recreates the UEFI varstore each boot"

# bash reads scripts incrementally; editing a bind-mounted script mid-run
# corrupts that run.
assert_grep 'SNAP=' "$BA" "build-all snapshots scripts before mounting them"

# Sizing the root partition from a fixed guess either truncates or bloats.
assert_grep 'ROOT_MB:-auto' "$BI" "root partition is sized from the actual rootfs"

# Without first-boot expansion a 64 GB card still presents a ~13 GB root.
assert_grep 'omarchy-pi-expand-root' "$RF" "first-boot root expansion is installed"

# Release images keep Omarchy's closed-by-default firewall.
assert_grep 'ALLOW_SSH' "$RF" "SSH exposure is explicit and variant-gated"
