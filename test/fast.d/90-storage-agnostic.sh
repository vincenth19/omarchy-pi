#!/usr/bin/env bash
# The image must boot from whatever medium it lands on. A Pi 5 can boot from an
# SD card (/dev/mmcblk0p2), an NVMe SSD on the PCIe slot (/dev/nvme0n1p2) or
# USB (/dev/sda2), and the VM image uses virtio (/dev/vda2). Hardcoding any of
# those means the image only boots off the medium it was built for -- which is
# invisible in testing if you only ever test one.
source "$(dirname "$0")/../lib.sh"
RF="$ROOT/scripts/build-rootfs.sh"
BI="$ROOT/scripts/build-image.sh"
CL="$ROOT/config/boot/cmdline.txt"

# fstab must mount by label, never by device node.
assert_grep 'LABEL=omarchy-root' "$RF" "fstab mounts root by label"
assert_grep 'LABEL=OMARCHYPI' "$RF" "fstab mounts /boot by label"
if grep -E '^/dev/(mmcblk|vd|sd|nvme)' "$RF" >/dev/null 2>&1; then
  bad "fstab names no device nodes" "a hardcoded device only boots one medium"
else
  ok "fstab names no device nodes"
fi

# The labels fstab relies on must actually be set when the filesystems are made.
assert_grep 'mke2fs .*-L omarchy-root' "$BI" "ext4 root is labelled omarchy-root"
assert_grep 'mkfs\.vfat .*-n OMARCHYPI' "$BI" "ESP is labelled OMARCHYPI"

# Root is found by PARTUUID: the kernel resolves it itself, before any
# initramfs runs, so it works even if the initramfs cannot.
assert_grep 'ROOT_PARTUUID=' "$BI" "a root PARTUUID is assigned at build time"
assert_grep 'sfdisk --quiet --part-uuid "\$OUT" 2 "\$ROOT_PARTUUID"' "$BI" "the PARTUUID is set on partition 2"
# The build must read the table back. The first version of this feature put
# uuid= inline in the sfdisk script, sfdisk rejected the whole script, and the
# grep-only test above still passed -- the image shipped unpartitioned.
assert_grep 'sfdisk -d "\$OUT" \| grep -qi "uuid=\$\{ROOT_PARTUUID\}"' "$BI" "the build verifies the PARTUUID landed in the table"
assert_grep 'root=PARTUUID=' "$BI" "the boot entry references root by PARTUUID"

# cmdline.txt is a template; the build rewrites root= into it.
assert_no_grep_active 'root=/dev/' "$CL" "cmdline.txt has no hardcoded root device"

# NVMe insurance: nvme is built into linux-rpi today, but a modular rebuild
# would silently lose NVMe boot if the initramfs never names it.
assert_grep 'WANT_MODULES="mmc_block.*sdhci_brcmstb.*nvme' "$RF" "Pi initramfs names the SD (Pi 5 = sdhci_brcmstb) and NVMe stacks"
# The first Pi build named sdhci_pci, which linux-rpi does not ship in any
# form -- mkinitcpio errored and the image was flagged incomplete. The list
# must be validated against the kernel, not trusted.
assert_grep 'modules\.builtin' "$RF" "Pi initramfs module list is validated against the installed kernel"
assert_no_grep_active 'sdhci_pci' "$RF" "no module the Pi kernel lacks is named"

# The Pi variant must ship the whole of /boot: the firmware needs the BCM2712
# device trees (including the D0 stepping) and overlays/, not just a kernel.
assert_grep 'mcopy -i "\$ESP" -s -b \./\*' "$BI" "Pi variant mirrors the whole /boot tree"
