#!/usr/bin/env bash
# Verify the initramfs drop-in actually does what it claims, by sourcing it the
# way mkinitcpio does. Grepping the file only proves the text is there.
source "$(dirname "$0")/../lib.sh"
command -v docker >/dev/null || { echo "    skipped: docker unavailable"; exit 0; }

result=$(docker run --rm --platform linux/arm64 \
  -v "$ROOT/config/mkinitcpio:/dropin:ro" alarm-work bash -c '
mkdir -p /etc/mkinitcpio.conf.d
# Reproduce Omarchy'"'"'s own drop-in, including the pieces the Pi cannot use.
cat > /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<X
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms block encrypt filesystems fsck btrfs-overlayfs)
X
echo "MODULES+=(thunderbolt)" > /etc/mkinitcpio.conf.d/thunderbolt_module.conf
cp /dropin/zz-omarchy-pi.conf /etc/mkinitcpio.conf.d/
MODULES=(); HOOKS=()
for f in $(ls /etc/mkinitcpio.conf.d/*.conf | sort); do source "$f"; done
echo "HOOKS:${HOOKS[*]}"
echo "MODULES:${MODULES[*]}"
' 2>/dev/null)

hooks=$(echo "$result" | sed -n 's/^HOOKS://p')
mods=$(echo "$result" | sed -n 's/^MODULES://p')

[ -n "$hooks" ] || { bad "drop-in evaluated" "no output from container"; exit 1; }

echo "$hooks" | grep -q btrfs-overlayfs \
  && bad "btrfs-overlayfs removed from HOOKS" "got: $hooks" \
  || ok "btrfs-overlayfs removed from HOOKS"

echo "$mods" | grep -q thunderbolt \
  && bad "thunderbolt removed from MODULES" "got: $mods" \
  || ok "thunderbolt removed from MODULES"

echo "$hooks" | grep -q encrypt \
  && bad "encrypt removed (images are not LUKS)" "got: $hooks" \
  || ok "encrypt removed (images are not LUKS)"

# The drop-in must not damage the hooks that matter.
for keep in base udev filesystems fsck; do
  echo "$hooks" | grep -qw "$keep" \
    && ok "essential hook preserved: $keep" \
    || bad "essential hook preserved: $keep" "got: $hooks"
done
