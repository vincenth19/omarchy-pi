# Shared assertions for the omarchy-pi test suite.
# Each test file is a standalone script; it exits non-zero if any check fails.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_pass=0; _fail=0

ok()   { printf '    \033[32mok\033[0m   %s\n' "$1"; _pass=$((_pass+1)); }
bad()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; _fail=$((_fail+1)); }

# assert <condition-exit-code> <message> [detail-on-failure]
assert()      { if [ "$1" -eq 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
assert_file() { [ -f "$1" ] && ok "${2:-$1 exists}" || bad "${2:-$1 exists}" "missing: $1"; }

# assert_grep <pattern> <file> <message>   -- pattern MUST be present
assert_grep() {
  if grep -Eq "$1" "$2" 2>/dev/null; then ok "$3"
  else bad "$3" "expected /$1/ in $2"; fi
}
# assert_no_grep <pattern> <file> <message> -- pattern MUST NOT be present
assert_no_grep() {
  if grep -Eq "$1" "$2" 2>/dev/null; then bad "$3" "unexpected /$1/ in $2"
  else ok "$3"; fi
}

# Comment-aware variants. Config files and scripts routinely *mention* the
# thing they must not do -- in a comment explaining why. Matching raw text
# turns those explanations into false failures, so strip comments first.
_active() { grep -vE '^[[:space:]]*#' "$1" 2>/dev/null; }

assert_grep_active() {
  if _active "$2" | grep -Eq "$1"; then ok "$3"
  else bad "$3" "expected /$1/ in the active (non-comment) lines of $2"; fi
}
assert_no_grep_active() {
  if _active "$2" | grep -Eq "$1"; then bad "$3" "unexpected /$1/ in the active lines of $2"
  else ok "$3"; fi
}

finish() { exit $(( _fail > 0 ? 1 : 0 )); }
trap finish EXIT
