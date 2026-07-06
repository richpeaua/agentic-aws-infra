#!/usr/bin/env bash
# Focused tests for the headless run guards: the portable run_with_timeout helper.
# Self-contained: invokes no real providers. Exercises both the coreutils timeout
# path (when present) and the bash-only fallback (by shadowing `has`).
# Run: tests/run_guards_test.sh   (or: bash tests/run_guards_test.sh)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

# shellcheck source=/dev/null
source "$REPO/scripts/lib.sh"

echo "== run_with_timeout =="

# A fast command finishes and passes its own exit code through.
rc=0; run_with_timeout 5 true || rc=$?
[ "$rc" -eq 0 ] && pass "fast success passes through (rc 0)" || fail "fast success (rc=$rc)"

rc=0; run_with_timeout 5 false || rc=$?
[ "$rc" -ne 0 ] && pass "fast failure passes through (non-zero)" || fail "fast failure (rc=$rc)"

# A non-positive / non-numeric ceiling means "no timeout": run directly.
rc=0; run_with_timeout 0 true || rc=$?
[ "$rc" -eq 0 ] && pass "zero ceiling runs directly" || fail "zero ceiling (rc=$rc)"
rc=0; run_with_timeout "" true || rc=$?
[ "$rc" -eq 0 ] && pass "empty ceiling treated as no timeout" || fail "empty ceiling (rc=$rc)"

# stdin/stdout are inherited, so the helper is pipe-safe.
out="$(printf 'hi' | run_with_timeout 5 cat)"
[ "$out" = "hi" ] && pass "stdin/stdout inherited through the guard" || fail "pipe passthrough (got '$out')"

# A slow command is killed near the deadline and returns non-zero, quickly.
check_timeout_trip() {
  local label="$1" start end elapsed rc=0
  start="$(date +%s)"
  run_with_timeout 1 sleep 30 || rc=$?
  end="$(date +%s)"
  elapsed=$(( end - start ))
  if [ "$rc" -ne 0 ] && [ "$elapsed" -lt 10 ]; then
    pass "$label (rc=$rc, ~${elapsed}s)"
  else
    fail "$label (rc=$rc, elapsed=${elapsed}s)"
  fi
}

# Whatever path this host takes (coreutils timeout/gtimeout, else fallback).
check_timeout_trip "slow command tripped by guard"

# Force the bash-only fallback by shadowing has() so the coreutils binaries look absent.
has() { case "$1" in timeout|gtimeout) return 1 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac; }
check_timeout_trip "portable fallback trips the guard"
unset -f has

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL RUN-GUARD TESTS PASSED"
else
  echo "$fails RUN-GUARD TEST(S) FAILED" >&2
  exit 1
fi
