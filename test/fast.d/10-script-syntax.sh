#!/usr/bin/env bash
# Every shipped script must parse. A syntax error in build-rootfs.sh once
# corrupted a running build; bash reads scripts incrementally, so a broken
# script can fail halfway through rather than at launch.
source "$(dirname "$0")/../lib.sh"

for f in "$ROOT"/scripts/*.sh "$ROOT"/config/bin/* "$ROOT"/test/run.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null
  assert $? "$(basename "$f") parses" "$(bash -n "$f" 2>&1 | head -2)"
done

for f in "$ROOT"/scripts/*.sh "$ROOT"/config/bin/*; do
  [ -f "$f" ] || continue
  [ -x "$f" ] && ok "$(basename "$f") is executable" || bad "$(basename "$f") is executable" "chmod +x it"
done
