#!/usr/bin/env bash
# Policy guards. These encode decisions that are easy to erode one commit at a
# time: only rebuild Omarchy's own packages, never edit upstream's files when a
# drop-in will do, and never ship a bootloader stack the Pi cannot use.
source "$(dirname "$0")/../lib.sh"

# --- no third-party rebuilds ---------------------------------------------
LIST="$ROOT/packages/aarch64-rebuild.txt"
PKGS="${PKGS:-$ROOT/../omarchy-pkgs/pkgbuilds}"
assert_file "$LIST"

if [ -d "$PKGS" ]; then
  missing=""
  while read -r p; do
    [ -z "$p" ] && continue
    [ -d "$PKGS/$p" ] || missing="$missing $p"
  done < "$LIST"
  if [ -z "$missing" ]; then
    ok "every rebuilt package comes from omarchy-pkgs"
  else
    bad "every rebuilt package comes from omarchy-pkgs" \
        "not in omarchy-pkgs:$missing -- third-party rebuilds are out of scope"
  fi
else
  echo "    skipped: no omarchy-pkgs checkout"
fi

# build-pkgs.sh must refuse anything without an upstream PKGBUILD.
assert_grep 'Refusing to build' "$ROOT/scripts/build-pkgs.sh" \
  "build-pkgs.sh enforces the no-third-party-rebuild policy"

# We only carry a patched PKGBUILD for Omarchy's own package.
for d in "$ROOT"/pkgbuilds/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  case "$n" in
    omarchy|omarchy-settings|omarchy-keyring) ok "local PKGBUILD '$n' is an Omarchy package" ;;
    *) bad "local PKGBUILD '$n' is an Omarchy package" \
           "third-party PKGBUILDs are out of scope -- document as unsupported instead" ;;
  esac
done

# --- the Pi cannot use the Limine/btrfs stack ----------------------------
PB="$ROOT/pkgbuilds/omarchy/PKGBUILD"
if [ -f "$PB" ]; then
  deps=$(sed -n '/^depends=(/,/^)/p' "$PB")
  for bad_dep in limine limine-mkinitcpio-hook limine-snapper-sync snapper; do
    if echo "$deps" | grep -Eq "^\s*'$bad_dep'"; then
      bad "omarchy PKGBUILD does not depend on $bad_dep" "the Pi boots from its own firmware"
    else
      ok "omarchy PKGBUILD does not depend on $bad_dep"
    fi
  done
fi

# --- the initramfs drop-in is additive -----------------------------------
DROPIN="$ROOT/config/mkinitcpio/zz-omarchy-pi.conf"
assert_file "$DROPIN"
case "$(basename "$DROPIN")" in
  zz-*) ok "drop-in sorts after Omarchy's own drop-ins" ;;
  *)    bad "drop-in sorts after Omarchy's own drop-ins" "name it zz-* or it loads too early" ;;
esac
assert_grep 'btrfs-overlayfs' "$DROPIN" "drop-in handles btrfs-overlayfs"

# ${arr[@]/pattern} substitutes an empty string instead of removing the
# element; mkinitcpio then fails with "Hook '"'"''"'"' cannot be found". Removal must
# rebuild the array.
if grep -Eq '\$\{(HOOKS|MODULES)\[@\]/' "$DROPIN"; then
  bad "drop-in removes entries by rebuilding the array" \
      "\${arr[@]/pattern} leaves empty elements that break mkinitcpio"
else
  ok "drop-in removes entries by rebuilding the array"
fi
