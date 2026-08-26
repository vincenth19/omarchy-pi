#!/usr/bin/env bash
# Build the aarch64 packages Omarchy needs but doesn't publish for ARM.
#
# Omarchy's own repo (pkgs.omarchy.org) ships x86_64 only, so we rebuild the
# missing packages from omacom-io/omarchy-pkgs PKGBUILDs and assemble them into
# a pacman repo the Pi can install from.
#
# Runs inside an aarch64 Arch Linux ARM container (native on Apple Silicon).
set -uo pipefail

PKGBUILD_DIR="${PKGBUILD_DIR:-/pkgbuilds}"
OUT="${OUT:-/out}"
LOGS="$OUT/logs"
mkdir -p "$OUT" "$LOGS"

PACKAGES=(${PACKAGES:-})
if [ ${#PACKAGES[@]} -eq 0 ]; then
  echo "No PACKAGES specified" >&2; exit 1
fi

# PKGBUILDs that build fine on ARM but only declare x86_64.
patch_arch() {
  sed -i "s/^arch=.*/arch=('x86_64' 'aarch64')/" PKGBUILD
}

ok=(); failed=()
for pkg in "${PACKAGES[@]}"; do
  echo "==> $pkg"
  rm -rf "/tmp/b/$pkg"; mkdir -p /tmp/b
  cp -r "$PKGBUILD_DIR/$pkg" "/tmp/b/$pkg" || { failed+=("$pkg:nosrc"); continue; }
  cd "/tmp/b/$pkg" || continue

  grep -q "aarch64\|'any'" PKGBUILD || patch_arch

  if makepkg -sf --noconfirm --skippgpcheck >"$LOGS/$pkg.log" 2>&1; then
    cp ./*.pkg.tar.* "$OUT/" 2>/dev/null && ok+=("$pkg") || failed+=("$pkg:nopkg")
  else
    failed+=("$pkg:build")
  fi
done

echo
echo "BUILT (${#ok[@]}): ${ok[*]}"
echo "FAILED (${#failed[@]}): ${failed[*]}"
printf '%s\n' "${ok[@]}"     > "$OUT/built.txt"
printf '%s\n' "${failed[@]}" > "$OUT/failed.txt"
