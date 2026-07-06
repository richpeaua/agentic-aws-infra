#!/usr/bin/env bash
# Focused test for scripts/runs.sh help vs usage-error behavior.
# Explicit -h/--help prints usage to stdout and exits 0; errors go to stderr non-zero.
# Self-contained: uses a temp run store (AGENTS_RUNS_DIR), invokes no real providers.
# Run: tests/runs_help_test.sh   (or: bash tests/runs_help_test.sh)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1 [$2]"; fi; }

# Run runs.sh capturing rc without tripping set -e; leaves stdout in $OUT, stderr in $ERR.
run_runs() {
  RC=0
  OUT="$(bash "$REPO/scripts/runs.sh" "$@" 2>"$TMP/err")" || RC=$?
  ERR="$(cat "$TMP/err")"
}

# Isolated store so the test never touches a real .agents/runs/.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/runs-help-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export AGENTS_RUNS_DIR="$TMP/runs"

echo "== runs.sh --help / -h (stdout, exit 0) =="

run_runs --help
check "--help exits 0" '[ "$RC" -eq 0 ]'
check "--help prints a recognizable usage line to stdout" \
  'printf "%s" "$OUT" | grep -q "scripts/runs.sh list"'
check "--help writes nothing to stderr" '[ -z "$ERR" ]'

run_runs -h
check "-h exits 0" '[ "$RC" -eq 0 ]'
check "-h prints usage to stdout" 'printf "%s" "$OUT" | grep -q "scripts/runs.sh list"'

echo "== runs.sh error paths (stderr, non-zero) =="

run_runs bogus
check "unknown command exits non-zero" '[ "$RC" -ne 0 ]'

run_runs
check "no subcommand exits non-zero" '[ "$RC" -ne 0 ]'
check "no subcommand prints nothing to stdout" '[ -z "$OUT" ]'
check "no subcommand prints usage to stderr" \
  'printf "%s" "$ERR" | grep -q "scripts/runs.sh list"'

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL RUNS HELP TESTS PASSED"
else
  echo "$fails RUNS HELP TEST(S) FAILED" >&2
  exit 1
fi
