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
# Element counts and emptiness matter: ${arr[@]/pattern} substitutes an EMPTY
# STRING rather than removing the element, and empty entries are invisible in
# "${arr[*]}" while still making mkinitcpio fail with "Hook '' cannot be found".
echo "HOOKCOUNT:${#HOOKS[@]}"
empty=0
for h in "${HOOKS[@]}"; do [ -z "$h" ] && empty=$((empty+1)); done
for m in "${MODULES[@]}"; do [ -z "$m" ] && empty=$((empty+1)); done
echo "EMPTY:$empty"
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

# The real trap: removal by substitution leaves empty array elements, which
# print as nothing but make mkinitcpio fail. This shipped once.
empty=$(echo "$result" | sed -n 's/^EMPTY://p')
[ "${empty:-1}" = "0" ] \
  && ok "no empty elements left in HOOKS/MODULES" \
  || bad "no empty elements left in HOOKS/MODULES" \
         "$empty empty entries -- use a rebuild loop, not \${arr[@]/pattern}"

# Count the hooks rather than trusting the joined string.
count=$(echo "$result" | sed -n 's/^HOOKCOUNT://p')
[ "${count:-0}" -ge 8 ] \
  && ok "hook list still has $count entries" \
  || bad "hook list still has $count entries" "the drop-in removed too much"

# The drop-in must not damage the hooks that matter.
for keep in base udev filesystems fsck; do
  echo "$hooks" | grep -qw "$keep" \
    && ok "essential hook preserved: $keep" \
    || bad "essential hook preserved: $keep" "got: $hooks"
done
