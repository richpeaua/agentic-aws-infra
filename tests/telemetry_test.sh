#!/usr/bin/env bash
# Focused tests for the agent-observability telemetry helper and scripts/runs.sh.
# Self-contained: uses a temp run store (AGENTS_RUNS_DIR), invokes no real providers.
# Run: tests/telemetry_test.sh   (or: bash tests/telemetry_test.sh)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1 [$2]"; fi; }

# Isolated store for the whole run.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/runs-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export AGENTS_RUNS_DIR="$TMP/runs"

# shellcheck source=/dev/null
source "$REPO/scripts/lib.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/lib/telemetry.sh"

echo "== telemetry helper =="

rid="$(telemetry_new_run_id implementer)"
check "run id has kind + timestamp shape" \
  '[[ "$rid" =~ ^[0-9]{8}T[0-9]{6}Z-implementer-[0-9a-f]+$ ]]'

dir="$(telemetry_run_dir "$rid")"
telemetry_init_run "$dir" implementer implementer claude default 29 ""
check "init writes running metadata" '[ "$(jq -r .status "$dir/metadata.json")" = running ]'
check "init records issue" '[ "$(jq -r .issue "$dir/metadata.json")" = 29 ]'
check "init token usage starts unavailable" \
  '[ "$(jq -r .token_usage.source "$dir/metadata.json")" = unavailable ]'

# A claude JSON usage sample -> normalized usage.
echo '{"result":"hi","usage":{"input_tokens":10,"cache_read_input_tokens":5,"output_tokens":7}}' > "$TMP/claude.json"
telemetry_usage_from_claude_json "$TMP/claude.json" > "$TMP/usage.json"
check "claude usage input sums base+cache" '[ "$(jq -r .input "$TMP/usage.json")" = 15 ]'
check "claude usage output parsed" '[ "$(jq -r .output "$TMP/usage.json")" = 7 ]'
check "claude usage total = in+out" '[ "$(jq -r .total "$TMP/usage.json")" = 22 ]'
check "claude usage source tagged" '[ "$(jq -r .source "$TMP/usage.json")" = claude ]'

# Missing usage shape -> unavailable.
echo '{"result":"hi"}' > "$TMP/nousage.json"
check "missing usage -> unavailable" \
  '[ "$(telemetry_usage_from_claude_json "$TMP/nousage.json" | jq -r .source)" = unavailable ]'

# Finalize with a usage file -> status/exit/duration/token usage populated.
telemetry_finalize_run "$dir" success 0 feat/x https://example.com/pr/1 "$TMP/usage.json"
check "finalize sets success" '[ "$(jq -r .status "$dir/metadata.json")" = success ]'
check "finalize sets exit code" '[ "$(jq -r .exit_code "$dir/metadata.json")" = 0 ]'
check "finalize records branch" '[ "$(jq -r .branch "$dir/metadata.json")" = feat/x ]'
check "finalize records pr url" '[ "$(jq -r .pr_url "$dir/metadata.json")" = https://example.com/pr/1 ]'
check "finalize duration is numeric" '[ "$(jq -r ".duration_seconds|type" "$dir/metadata.json")" = number ]'
check "finalize merges token usage" '[ "$(jq -r .token_usage.total "$dir/metadata.json")" = 22 ]'

# A failed run still records exit + status.
fdir="$(telemetry_run_dir "$(telemetry_new_run_id implementer)")"
telemetry_init_run "$fdir" implementer implementer claude default 29 ""
telemetry_finalize_run "$fdir" failed 1 "" "" ""
check "failed run records status" '[ "$(jq -r .status "$fdir/metadata.json")" = failed ]'
check "failed run records exit 1" '[ "$(jq -r .exit_code "$fdir/metadata.json")" = 1 ]'
check "failed run usage unavailable" '[ "$(jq -r .token_usage.source "$fdir/metadata.json")" = unavailable ]'

# Scrubbing. Assemble fake identifiers at runtime so this tracked file holds no
# literal 12-digit account id, ARN, or real-looking email (scan-secrets would flag them).
echo "== scrub =="
acct="$(printf '%s%s' 12345678 9012)"          # -> a 12-digit id, but not literal in source
arn="arn:aws:iam::${acct}:role/x"
email="me@example.com"                          # example.com is a permitted placeholder
scrubbed="$(printf 'acct %s %s %s' "$acct" "$arn" "$email" | telemetry_scrub)"
check "scrub redacts account id" '! printf "%s" "$scrubbed" | grep -q "$acct"'
check "scrub redacts email"      '! printf "%s" "$scrubbed" | grep -q "$email"'
check "scrub keeps placeholder text" 'printf "%s" "$scrubbed" | grep -q redacted'

# runs.sh over the isolated store, plus a review parent/child pair.
echo "== runs.sh =="
pdir="$(telemetry_run_dir "$(telemetry_new_run_id review)")"
telemetry_init_run "$pdir" review review-panel multi "" "" ""
telemetry_finalize_run "$pdir" passed 0 "" "" ""
pid="$(basename "$pdir")"
cdir="$pdir-security-reviewer"
telemetry_init_run "$cdir" review-child security-reviewer claude default "" "$pid"
telemetry_finalize_run "$cdir" success 0 "" "" ""

runs() { bash "$REPO/scripts/runs.sh" "$@"; }

check "list hides review children by default" \
  '! runs list | grep -q security-reviewer'
check "list --children shows reviewer child" \
  'runs list --children | grep -q security-reviewer'
check "list --json is valid json array" \
  'runs list --json | jq -e "type == \"array\"" >/dev/null'
check "show prints metadata + artifact paths" \
  'runs show "$rid" | grep -q metadata.json'
check "show lists child runs for a review parent" \
  'runs show "$pid" | grep -q security-reviewer'

# clean: age one run into the past, keep a fresh one.
echo "== runs.sh clean =="
old="$(telemetry_run_dir "$(telemetry_new_run_id implementer)")"
telemetry_init_run "$old" implementer implementer claude default 1 ""
telemetry_finalize_run "$old" success 0 "" "" ""
oldid="$(basename "$old")"
# Rewrite start_epoch to ~60 days ago.
past=$(( $(date -u +%s) - 60*86400 ))
tmpm="$(mktemp)"; jq --argjson e "$past" '.start_epoch=$e' "$old/metadata.json" > "$tmpm" && mv "$tmpm" "$old/metadata.json"

runs clean --older-than 30d >/dev/null
check "clean removes an old run" '[ ! -d "$old" ]'
check "clean keeps a recent run" '[ -d "$pdir" ]'

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL TELEMETRY TESTS PASSED"
else
  echo "$fails TELEMETRY TEST(S) FAILED" >&2
  exit 1
fi
