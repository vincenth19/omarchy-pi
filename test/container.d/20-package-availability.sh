#!/usr/bin/env bash
# Every package Omarchy's base list names must be installable on aarch64 --
# either from Arch Linux ARM or from packages we rebuild. A regression here
# means an image that silently ships without some of the desktop.
source "$(dirname "$0")/../lib.sh"
command -v docker >/dev/null || { echo "    skipped: docker unavailable"; exit 0; }
OMARCHY="${OMARCHY:-$ROOT/../omarchy}"
[ -d "$OMARCHY" ] || { echo "    skipped: no omarchy checkout"; exit 0; }

out=$(docker run --rm --platform linux/arm64 \
  -v "$OMARCHY:/omarchy:ro" -v "$ROOT/packages:/pkglist:ro" alarm-work bash -c '
pacman -Sy >/dev/null 2>&1
missing=""
while read -r p; do
  [ -z "$p" ] && continue
  case "$p" in \#*) continue ;; esac
  # --print resolves provides too, so neovim satisfies nvim.
  pacman -S --print-format "%n" "$p" >/dev/null 2>&1 || {
    grep -qx "$p" /pkglist/aarch64-rebuild.txt 2>/dev/null || missing="$missing $p"
  }
done < <(grep -v "^#" /omarchy/install/omarchy-base.packages | grep -v "^$")
echo "MISSING:$missing"
' 2>/dev/null)

missing=$(echo "$out" | sed -n 's/^MISSING://p' | xargs)
# herdr builds on ARM but needs more RAM than Docker Desktop grants by default.
missing=$(echo " $missing " | sed 's/ herdr / /' | xargs)

if [ -z "$missing" ]; then
  ok "every base package resolves on aarch64 or is rebuilt by us"
else
  bad "every base package resolves on aarch64 or is rebuilt by us" \
      "unresolvable:$missing"
fi

# The four Omarchy-approved terminals, minus the one with no ARM build.
for t in foot kitty alacritty; do
  docker run --rm --platform linux/arm64 alarm-work bash -c \
    "pacman -Sy >/dev/null 2>&1; pacman -Si $t >/dev/null 2>&1" \
    && ok "terminal available on aarch64: $t" \
    || bad "terminal available on aarch64: $t" "no longer packaged"
done
