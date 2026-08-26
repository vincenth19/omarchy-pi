#!/usr/bin/env bash
# The pi5 patch series is the port's main liability: every patch is a future
# merge conflict. These checks keep it small, on a stable base, and confined to
# the files we accepted responsibility for.
source "$(dirname "$0")/../lib.sh"

OMARCHY="${OMARCHY:-$ROOT/../omarchy}"
if [ ! -d "$OMARCHY/.git" ]; then
  echo "    skipped: no omarchy checkout at $OMARCHY"
  exit 0
fi
cd "$OMARCHY"

BASE=$(git tag --sort=-v:refname 2>/dev/null | grep -vE '\-?(alpha|beta|rc)[0-9]*$' | head -1)
assert $? "a stable upstream tag is resolvable"

git merge-base --is-ancestor "$BASE" pi5 2>/dev/null
assert $? "pi5 is based on the latest stable tag ($BASE)" \
  "run ./scripts/sync-upstream.sh"

# We never track upstream's development branch.
if git merge-base --is-ancestor upstream/master pi5 2>/dev/null; then
  bad "pi5 does not include upstream/master" "the port must follow stable tags only"
else
  ok "pi5 does not include upstream/master"
fi

# A silently growing series is a silently growing maintenance burden.
MAX_PATCHES="${MAX_PATCHES:-6}"
COUNT=$(git rev-list --count "$BASE..pi5" 2>/dev/null || echo 99)
if [ "$COUNT" -le "$MAX_PATCHES" ]; then
  ok "patch series is $COUNT commit(s), at or under the $MAX_PATCHES budget"
else
  bad "patch series is $COUNT commit(s), over the $MAX_PATCHES budget" \
      "prefer an additive drop-in over patching upstream files"
fi

# Files the adapter design says we must NOT patch, because an additive
# drop-in covers them and editing them guarantees rebase conflicts.
FORBIDDEN='^etc/mkinitcpio\.conf\.d/'
if git diff --name-only "$BASE..pi5" | grep -Eq "$FORBIDDEN"; then
  bad "no patches to upstream mkinitcpio drop-ins" \
      "use config/mkinitcpio/zz-omarchy-pi.conf instead"
else
  ok "no patches to upstream mkinitcpio drop-ins"
fi

# Every patched file should still exist upstream; if one vanished, the patch is
# silently doing nothing.
while read -r f; do
  [ -z "$f" ] && continue
  if git cat-file -e "pi5:$f" 2>/dev/null; then ok "patched file still present: $f"
  else bad "patched file still present: $f" "upstream removed it; drop the patch"; fi
done < <(git diff --name-only "$BASE..pi5")
