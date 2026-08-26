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

# Policy: this port rebuilds ONLY packages Omarchy itself publishes, which it
# publishes for x86_64 only. Without them there is no Omarchy on ARM at all.
#
# It deliberately does NOT rebuild third-party software that lacks an aarch64
# build. Those builds need local patches (a pinned toolchain, dependencies
# disabled, upstream bugs worked around) that nobody wants to carry across
# releases. If something has no aarch64 package, it is unsupported and said to
# be unsupported -- see docs/APP-TESTING.md.
#
# Every name below must exist in omacom-io/omarchy-pkgs. Anything else is
# out of scope and fails here rather than quietly becoming a maintenance
# burden.
for pkg in "${PACKAGES[@]}"; do
  if [ ! -d "$PKGBUILD_DIR/$pkg" ]; then
    cat >&2 <<POLICY
Refusing to build '$pkg': no PKGBUILD in omarchy-pkgs.

This port only rebuilds Omarchy's own packages for aarch64. Third-party
software without an aarch64 build is out of scope -- document it as
unsupported instead of maintaining a custom build.
POLICY
    exit 1
  fi
done

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

  # JOBS=1 serialises compilation. Some Rust packages (herdr) get OOM-killed
  # while linking under Docker Desktop's default 4 GB; fewer parallel rustc
  # processes is the difference between building and being killed.
  if [ -n "${JOBS:-}" ]; then
    export MAKEFLAGS="-j${JOBS}" CARGO_BUILD_JOBS="$JOBS"
  fi

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
