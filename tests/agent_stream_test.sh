#!/usr/bin/env bash
# Integration tests for the writable-implementer stream-json path in scripts/agent.sh.
# Shadows `claude` with a fake on PATH that emits a canned stream-json transcript,
# so the launcher's stream wiring is exercised end to end with no real provider,
# no tokens, and no writable agent touching the repo.
# Run: tests/agent_stream_test.sh   (or: bash tests/agent_stream_test.sh)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-stream-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# Point the launcher at an isolated run store and the fake provider.
export AGENTS_RUNS_DIR="$TMP/runs"
export PATH="$TMP/bin:$PATH"

# fake_claude <exit-code> <<'json lines'  -> install a fake `claude` that drains
# stdin, prints the given stream-json lines to stdout, and exits <exit-code>.
fake_claude() {
  local rc="$1"
  { printf '#!/usr/bin/env bash\ncat >/dev/null\n'
    while IFS= read -r line; do printf 'printf "%%s\\n" %q\n' "$line"; done
    printf 'exit %s\n' "$rc"
  } > "$TMP/bin/claude"
  chmod +x "$TMP/bin/claude"
}

run_impl() {
  export AGENT_USAGE_FILE="$TMP/usage.json"
  export AGENT_STREAM_FILE="$TMP/stream.jsonl"
  local rc=0
  printf 'do the thing' | "$REPO/scripts/agent.sh" implementer --writable \
    >"$TMP/stdout.txt" 2>"$TMP/stderr.txt" || rc=$?
  return "$rc"
}

echo "== agent.sh stream-json (writable implementer) =="

# Happy path: session + tool + text + a success result event.
fake_claude 0 <<'JSON'
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}
{"type":"result","subtype":"success","is_error":false,"result":"FINAL-MESSAGE-TEXT","usage":{"input_tokens":100,"cache_read_input_tokens":20,"output_tokens":30}}
JSON
rc=0; run_impl || rc=$?
[ "$rc" -eq 0 ] && pass "happy path exits 0" || fail "happy path (rc=$rc)"
[ "$(tail -1 "$TMP/stdout.txt")" = "FINAL-MESSAGE-TEXT" ] \
  && pass "stdout ends with the final result text" || fail "stdout final text ($(tail -1 "$TMP/stdout.txt"))"
grep -aq 'tool: Edit' "$TMP/stderr.txt" \
  && pass "stderr carries the live progress digest" || fail "stderr digest missing"
[ "$(jq -r .total "$TMP/usage.json")" = 150 ] \
  && pass "usage total parsed from the stream result event" || fail "usage total ($(jq -r .total "$TMP/usage.json"))"
[ -s "$TMP/stream.jsonl" ] && [ "$(wc -l <"$TMP/stream.jsonl")" -ge 4 ] \
  && pass "stream transcript captured to the run store" || fail "stream transcript missing"

# No result event (e.g. a guard killed the run): must not be success.
fake_claude 0 <<'JSON'
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"content":[{"type":"text","text":"stuck"}]}}
JSON
rc=0; run_impl || rc=$?
[ "$rc" -ne 0 ] && pass "no result event -> non-zero (not success)" || fail "no result event (rc=$rc)"
[ "$(jq -r .source "$TMP/usage.json")" = unavailable ] \
  && pass "no result event -> usage unavailable" || fail "no-result usage ($(jq -r .source "$TMP/usage.json"))"

# is_error true at exit 0 (a budget/limit stop): must be treated as failed.
fake_claude 0 <<'JSON'
{"type":"result","subtype":"error_max_budget","is_error":true,"result":"stopped","usage":{"input_tokens":5,"output_tokens":1}}
JSON
rc=0; run_impl || rc=$?
[ "$rc" -ne 0 ] && pass "is_error result -> non-zero" || fail "is_error result (rc=$rc)"

# Provider exits non-zero: rc is preserved through the tee/digest pipe (PIPESTATUS).
fake_claude 7 <<'JSON'
{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":5,"output_tokens":1}}
JSON
rc=0; run_impl || rc=$?
[ "$rc" -eq 7 ] && pass "provider non-zero exit preserved (rc=7)" || fail "provider exit not preserved (rc=$rc)"

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL AGENT STREAM TESTS PASSED"
else
  echo "$fails AGENT STREAM TEST(S) FAILED" >&2
  exit 1
fi
