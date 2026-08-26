#!/usr/bin/env bash
# Rebase the pi5 patch series onto the latest upstream STABLE release.
#
# We track tagged stable releases only, never upstream's master branch --
# master is the development line, and a Pi image is not the place to find out
# what broke there today.
#
# A conflict here is the intended failure mode: it stops the port, on this
# machine, before anything is published.
set -euo pipefail

OMARCHY="${OMARCHY:-$(cd "$(dirname "$0")/../../omarchy" && pwd)}"
BRANCH="${BRANCH:-pi5}"

cd "$OMARCHY"

echo "==> Fetching upstream tags"
git remote get-url upstream >/dev/null 2>&1 || \
  git remote add upstream https://github.com/basecamp/omarchy.git
git fetch --quiet upstream --tags

# Stable only: exclude anything carrying a pre-release suffix. Omarchy's
# versioning attaches these (4.0.0rc1, v4.0.0-beta3), and pacman's vercmp
# orders them before the final release.
LATEST=$(git tag --sort=-v:refname | grep -vE '\-?(alpha|beta|rc)[0-9]*$' | head -1)
[ -n "$LATEST" ] || { echo "No stable tag found" >&2; exit 1; }

CURRENT_BASE=$(git merge-base "$BRANCH" "$LATEST" 2>/dev/null || true)
echo "    latest stable upstream: $LATEST"

if git merge-base --is-ancestor "$LATEST" "$BRANCH" 2>/dev/null; then
  echo "    $BRANCH already contains $LATEST -- nothing to do"
  echo
  echo "Patch series ($(git rev-list --count "$LATEST..$BRANCH") commits):"
  git log --oneline "$LATEST..$BRANCH"
  exit 0
fi

PATCHES=$(git rev-list --count "${CURRENT_BASE:-$LATEST}..$BRANCH")
echo "==> Rebasing $PATCHES patch(es) onto $LATEST"

if ! git rebase "$LATEST" "$BRANCH"; then
  cat >&2 <<EOF

==> REBASE CONFLICT -- this is the guard working.

Upstream changed something the port patches. Resolve it here, before any
package is built or published:

  git status                  # see what conflicts
  git rebase --continue       # after fixing
  git rebase --abort          # to back out

If upstream fixed the underlying problem themselves, drop our patch entirely
rather than carrying it forward:

  git rebase --skip

EOF
  exit 1
fi

echo
echo "==> Rebased onto $LATEST. Patch series is now:"
git log --oneline "$LATEST..$BRANCH"

REMAINING=$(git rev-list --count "$LATEST..$BRANCH")
if (( REMAINING < PATCHES )); then
  echo
  echo "    $(( PATCHES - REMAINING )) patch(es) became empty -- upstream fixed them."
  echo "    That is good news; the series just got smaller."
fi

cat <<EOF

Next: rebuild and verify before publishing anything.
  ./scripts/build-all.sh && ./scripts/smoke-test.sh
EOF
