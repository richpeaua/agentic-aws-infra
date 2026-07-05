#!/usr/bin/env bash
# Focused tests for implementer run status classification.
# Feeds synthetic rc / PR URL / final-message combinations to the pure decision
# function and asserts truthful success/failed/incomplete classification.
# Run: tests/implementer_status_test.sh   (or: bash tests/implementer_status_test.sh)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
# expect <label> <expected-status> <rc> <pr_url> <final_message>
expect() {
  local label="$1" want="$2" got
  got="$(implementer_run_status "$3" "$4" "$5")"
  if [ "$got" = "$want" ]; then pass "$label"; else fail "$label (want=$want got=$got)"; fi
}

# shellcheck source=/dev/null
source "$REPO/scripts/lib/implementer.sh"

echo "== implementer_run_status =="

PR="https://github.com/o/r/pull/1"

# Non-zero exit is always failed, regardless of PR or message.
expect "non-zero exit -> failed"                 failed     1 "$PR" "done"
expect "non-zero exit with no PR -> failed"       failed     2 ""    ""

# Exit 0 but missing completion evidence -> incomplete.
expect "exit 0, no PR -> incomplete"             incomplete 0 ""    "did some work"
expect "exit 0, PR but empty message -> incomplete"    incomplete 0 "$PR" ""
expect "exit 0, PR but whitespace-only message -> incomplete" incomplete 0 "$PR" $'  \n\t '
expect "exit 0, no PR and empty message -> incomplete" incomplete 0 ""    ""

# Exit 0 with a PR and a meaningful message -> success.
expect "exit 0, PR and message -> success"       success    0 "$PR" "Opened PR."

if [ "$fails" -gt 0 ]; then
  printf '\n%s test(s) failed\n' "$fails" >&2
  exit 1
fi
printf '\nall implementer status tests passed\n'
