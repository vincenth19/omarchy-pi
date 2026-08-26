#!/usr/bin/env bash
# First-boot services must decide from on-disk state, not from a "have I run
# before" marker.
#
# The bug this catches: release testing boots the image before publishing it.
# A marker-based service consumes its own first boot there, so the published
# image ships with the marker already set and the work never happens on a
# user's machine. Root expansion failed exactly this way -- a 64 GB card would
# have stayed at ~13 GB.
source "$(dirname "$0")/../lib.sh"
RF="$ROOT/scripts/build-rootfs.sh"

if grep -qE 'ConditionPathExists=!/var/lib/omarchy-pi/' "$RF"; then
  bad "no first-boot service gates on a run-once marker" \
      "release testing consumes the first boot; gate on actual state instead"
else
  ok "no first-boot service gates on a run-once marker"
fi

# The expansion must compare the partition end against the device size.
assert_grep 'blockdev --getsz' "$RF" "expansion measures the actual device size"
assert_grep 'disk_sectors - part_end' "$RF" "expansion compares partition end to device end"

# GPT's backup header lives at the end of the device; growing without moving it
# leaves the table corrupt.
assert_grep 'move-second-header' "$RF" "GPT backup header is moved before growing"

# gptfdisk provides sgdisk; without it the move silently does nothing.
assert_grep 'gptfdisk' "$RF" "gptfdisk is installed for sgdisk"

# Device-name parsing must handle SD cards and NVMe (p-suffixed) as well as
# virtio/SCSI, or expansion targets the wrong device.
assert_grep 'mmcblk\*p\*' "$RF" "handles SD card device naming"
assert_grep 'nvme\*p\*' "$RF" "handles NVMe device naming"

# The doctor should report expansion from live state too.
DOC="$ROOT/config/bin/omarchy-pi-doctor"
if grep -q 'root-expanded' "$DOC" 2>/dev/null; then
  bad "doctor reports expansion from live state" "it checks the removed marker file"
else
  ok "doctor reports expansion from live state"
fi
