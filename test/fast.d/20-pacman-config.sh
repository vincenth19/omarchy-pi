#!/usr/bin/env bash
# The Pi pacman configuration is load-bearing: every one of these was a real
# failure during the port.
source "$(dirname "$0")/../lib.sh"
CONF="$ROOT/config/pacman/pacman-pi.conf"
MIRROR="$ROOT/config/pacman/mirrorlist-pi"

assert_file "$CONF"
assert_file "$MIRROR"

assert_grep '^Architecture *= *aarch64' "$CONF" "architecture pinned to aarch64"

# Without SigLevel = ... DatabaseOptional, every sync 404s on core.db.sig,
# because Arch Linux ARM does not publish database signatures.
assert_grep '^SigLevel *=.*DatabaseOptional' "$CONF" "DatabaseOptional set (ALARM ships no .db.sig)"

# multilib is x86-only and has no ARM counterpart; its presence breaks sync.
assert_no_grep '^\[multilib\]' "$CONF" "no [multilib] section"

# omarchy and omarchy-settings are arch=any. If an upstream x86_64 repo were
# configured, pacman could satisfy them from there and replace our builds.
assert_no_grep_active 'pkgs\.omarchy\.org|stable-mirror\.omarchy\.org' "$CONF" \
  "no upstream x86_64 Omarchy repo configured"

# Our repo must be the only Omarchy-ish repo, and must exist.
assert_grep '^\[omarchy-pi\]' "$CONF" "our [omarchy-pi] repo is present"
if grep -qE '^\[omarchy\]' "$CONF"; then
  bad "upstream [omarchy] repo section absent" "it would satisfy arch=any packages from x86 builds"
else
  ok "upstream [omarchy] repo section absent"
fi

assert_grep '^\[alarm\]' "$CONF" "Arch Linux ARM [alarm] repo present"
assert_grep 'mirror\.archlinuxarm\.org' "$MIRROR" "mirrorlist points at Arch Linux ARM"

# DisableSandbox belongs in [options]; appended at the end it lands in the last
# repo section, where pacman ignores it and warns on every invocation.
if grep -q '^DisableSandbox' "$CONF"; then
  bad "DisableSandbox not shipped in the image config" "it is a build-time container workaround only"
else
  ok "DisableSandbox not shipped in the image config"
fi
