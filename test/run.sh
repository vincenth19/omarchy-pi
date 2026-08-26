#!/usr/bin/env bash
# omarchy-pi test runner.
#
#   ./test/run.sh            fast tests only (seconds, no Docker)
#   ./test/run.sh container  also run tests needing an aarch64 container
#   ./test/run.sh all        everything, including the VM smoke test
set -uo pipefail
cd "$(dirname "$0")/.."

TIER="${1:-fast}"
total_fail=0

run_dir() {
  local dir=$1 label=$2
  [ -d "$dir" ] || return 0
  echo
  echo "== $label =="
  for t in "$dir"/*.sh; do
    [ -e "$t" ] || continue
    echo "  $(basename "$t" .sh)"
    if ! bash "$t"; then total_fail=$((total_fail+1)); fi
  done
}

run_dir test/fast.d "fast"
[ "$TIER" = container ] || [ "$TIER" = all ] && run_dir test/container.d "container (aarch64)"

if [ "$TIER" = all ]; then
  echo
  echo "== integration (VM boot) =="
  if [ -f work/out/omarchy-pi.img ]; then
    ./scripts/smoke-test.sh || total_fail=$((total_fail+1))
  else
    echo "  skipped: no image at work/out/omarchy-pi.img (run ./scripts/build-all.sh)"
  fi
fi

echo
if (( total_fail )); then
  echo "FAILED: $total_fail test file(s)"
  exit 1
fi
echo "All tests passed."
