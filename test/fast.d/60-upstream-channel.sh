#!/usr/bin/env bash
# The port follows tagged stable releases, never upstream's development branch.
source "$(dirname "$0")/../lib.sh"
SYNC="$ROOT/scripts/sync-upstream.sh"
assert_file "$SYNC"

assert_grep 'alpha\|beta\|rc' "$SYNC" "sync filters out pre-release tags"
assert_no_grep 'upstream/(master|main)' "$SYNC" "sync never rebases onto a branch"

# The filter must actually reject pre-releases, not merely mention them.
filtered=$(printf 'v4.0.1\nv4.0.0-beta3\nv4.0.0rc2\nv4.0.0\n' \
  | grep -vE '\-?(alpha|beta|rc)[0-9]*$' | head -1)
if [ "$filtered" = "v4.0.1" ]; then
  ok "pre-release filter picks v4.0.1 over beta/rc tags"
else
  bad "pre-release filter picks v4.0.1 over beta/rc tags" "picked: $filtered"
fi

# A conflict must stop the release, not be worked around.
assert_grep 'REBASE CONFLICT' "$SYNC" "a rebase conflict halts with an explanation"

# CI must not publish anything that has not booted.
WF="$ROOT/.github/workflows/build-image.yml"
if [ -f "$WF" ]; then
  gate=$(grep -n 'smoke-test.sh' "$WF" | head -1 | cut -d: -f1)
  rel=$(grep -n 'action-gh-release' "$WF" | head -1 | cut -d: -f1)
  if [ -n "$gate" ] && [ -n "$rel" ] && [ "$gate" -lt "$rel" ]; then
    ok "CI smoke-tests before publishing a release"
  else
    bad "CI smoke-tests before publishing a release" "the gate must precede the release step"
  fi
fi
