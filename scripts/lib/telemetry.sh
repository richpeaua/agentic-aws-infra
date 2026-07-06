#!/usr/bin/env bash
# Shared telemetry helpers for the headless agent launchers.
# Source this file AFTER scripts/lib.sh (it relies on REPO_ROOT and the log helpers).
#
# Design goals:
#   - Durable local run records under .agents/runs/ (git-ignored; may hold sensitive context).
#   - Never block the underlying agent workflow: every side effect is best-effort.
#     Route side-effecting calls through `tel` so a failure becomes a warning, not an exit.
#   - Keep anything sent to GitHub scrubbed and bounded (this repo is public).
#
# Metadata schema (metadata.json), written once at init and rewritten at finalize:
#   run_id, kind, agent, provider, model, issue, parent, status,
#   start_time, start_epoch, end_time, duration_seconds, exit_code,
#   branch, pr_url, token_usage {input,output,total,source}
#
# Public functions:
#   telemetry_enabled                       -> 0 if telemetry is on (AGENTS_TELEMETRY != 0)
#   telemetry_runs_dir                      -> prints .agents/runs path
#   telemetry_new_run_id <kind>             -> prints a fresh run id
#   telemetry_run_dir <run-id>              -> prints that run's directory path
#   telemetry_init_run <dir> <kind> <agent> <provider> <model> <issue> <parent>
#   telemetry_finalize_run <dir> <status> <exit> <branch> <pr_url> <usage-file>
#   telemetry_usage_from_claude_json <file> -> prints normalized usage JSON
#   telemetry_claude_stream_result <file>   -> prints the final result event (stream-json)
#   telemetry_usage_from_claude_stream <file> -> prints normalized usage JSON (stream-json)
#   telemetry_usage_from_codex <file>       -> prints normalized usage JSON
#   telemetry_usage_unavailable             -> prints the unavailable usage JSON
#   telemetry_scrub                         -> filter stdin, redacting identifiers
#   tel <fn> [args...]                      -> run a telemetry fn, swallow failure as a warning

: "${REPO_ROOT:?telemetry.sh requires scripts/lib.sh to be sourced first}"

# tel: invoke a telemetry function so its failure never aborts the caller.
# Because the callee runs on the left of `||`, bash disables `set -e` inside it,
# so an unguarded failing command warns instead of killing the workflow.
tel() {
  "$@" || warn "telemetry: '$*' failed (non-blocking)"
  return 0
}

# Telemetry is on by default; set AGENTS_TELEMETRY=0 to disable everywhere.
telemetry_enabled() { [ "${AGENTS_TELEMETRY:-1}" != "0" ]; }

# Run store location. Override with AGENTS_RUNS_DIR (used by tests and custom setups).
telemetry_runs_dir() { printf '%s' "${AGENTS_RUNS_DIR:-$REPO_ROOT/.agents/runs}"; }

telemetry_run_dir() { printf '%s/%s' "$(telemetry_runs_dir)" "$1"; }

# telemetry_new_run_id <kind> -> UTC timestamp + kind + short random, filesystem-safe.
telemetry_new_run_id() {
  local kind="${1:-run}" ts rand
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  rand="$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
  printf '%s-%s-%s' "$ts" "$kind" "$rand"
}

_telemetry_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
_telemetry_epoch() { date -u +%s; }

# Normalized "no usage" record.
telemetry_usage_unavailable() {
  printf '{"input":null,"output":null,"total":null,"source":"unavailable"}'
}

# Parse Claude Code `--output-format json` result into normalized usage.
# Falls back to the unavailable record if the shape is missing.
telemetry_usage_from_claude_json() {
  local file="$1"
  [ -s "$file" ] || { telemetry_usage_unavailable; return 0; }
  jq -c '
    (.usage // {}) as $u
    | ((($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))) as $in
    | (($u.output_tokens // 0)) as $out
    | if ($u | has("input_tokens")) or ($u | has("output_tokens"))
      then {input: $in, output: $out, total: ($in + $out), source: "claude"}
      else {input: null, output: null, total: null, source: "unavailable"}
      end
  ' "$file" 2>/dev/null || telemetry_usage_unavailable
}

# Extract the final result event from a Claude `--output-format stream-json`
# transcript (JSONL). Prints that event as compact JSON, or nothing if absent
# (for example a run killed by a guard before it emitted a result). Tolerates
# non-JSON lines in the stream.
telemetry_claude_stream_result() {
  local file="$1"
  [ -s "$file" ] || return 0
  jq -Rc 'fromjson? | select(.type=="result")' "$file" 2>/dev/null | tail -1
}

# Normalized usage from a Claude stream-json transcript. The final result event
# carries the same `.usage`/`.result` shape as the buffered `--output-format json`
# output, so usage parsing is shared with telemetry_usage_from_claude_json.
telemetry_usage_from_claude_stream() {
  local file="$1" resultf
  resultf="$(mktemp)"
  telemetry_claude_stream_result "$file" > "$resultf"
  telemetry_usage_from_claude_json "$resultf"
  rm -f "$resultf"
}

# Best-effort parse of Codex output for a token count. Codex does not expose a
# stable machine usage field for `exec -o`, so this scans the captured stream for
# a "tokens used" style line and otherwise reports usage as unavailable.
telemetry_usage_from_codex() {
  local file="$1" total
  [ -s "$file" ] || { telemetry_usage_unavailable; return 0; }
  total="$(grep -aoiE 'tokens used[: ]+[0-9,]+' "$file" 2>/dev/null | tail -1 | grep -oE '[0-9,]+' | tr -d ',' || true)"
  if [ -n "$total" ]; then
    printf '{"input":null,"output":null,"total":%s,"source":"codex"}' "$total"
  else
    telemetry_usage_unavailable
  fi
}

# telemetry_init_run <dir> <kind> <agent> <provider> <model> <issue> <parent>
# Creates the run directory and writes the initial (running) metadata.json.
telemetry_init_run() {
  local dir="$1" kind="$2" agent="$3" provider="$4" model="$5" issue="$6" parent="$7"
  mkdir -p "$dir"
  local iso epoch
  iso="$(_telemetry_iso)"
  epoch="$(_telemetry_epoch)"
  jq -n \
    --arg run_id "$(basename "$dir")" \
    --arg kind "$kind" \
    --arg agent "$agent" \
    --arg provider "$provider" \
    --arg model "${model:-default}" \
    --arg issue "$issue" \
    --arg parent "$parent" \
    --arg start_time "$iso" \
    --argjson start_epoch "$epoch" \
    '{
      run_id: $run_id, kind: $kind, agent: $agent, provider: $provider,
      model: $model,
      issue: (if $issue == "" then null else $issue end),
      parent: (if $parent == "" then null else $parent end),
      status: "running",
      start_time: $start_time, start_epoch: $start_epoch,
      end_time: null, duration_seconds: null, exit_code: null,
      branch: null, pr_url: null,
      token_usage: {input: null, output: null, total: null, source: "unavailable"}
    }' > "$dir/metadata.json"
}

# telemetry_finalize_run <dir> <status> <exit> <branch> <pr_url> <usage-file>
# Reads start_epoch back, computes duration, and rewrites the final metadata.json.
telemetry_finalize_run() {
  local dir="$1" status="$2" exit_code="$3" branch="$4" pr_url="$5" usage_file="$6"
  local meta="$dir/metadata.json"
  [ -f "$meta" ] || return 0
  local iso end_epoch start_epoch duration usage
  iso="$(_telemetry_iso)"
  end_epoch="$(_telemetry_epoch)"
  start_epoch="$(jq -r '.start_epoch // empty' "$meta" 2>/dev/null || true)"
  if [ -n "$start_epoch" ]; then duration=$(( end_epoch - start_epoch )); else duration=null; fi
  if [ -n "$usage_file" ] && [ -s "$usage_file" ]; then
    usage="$(cat "$usage_file")"
  else
    usage="$(telemetry_usage_unavailable)"
  fi
  # Validate usage is JSON; fall back if not.
  printf '%s' "$usage" | jq -e . >/dev/null 2>&1 || usage="$(telemetry_usage_unavailable)"
  local tmp; tmp="$(mktemp)"
  jq \
    --arg status "$status" \
    --arg end_time "$iso" \
    --argjson exit_code "${exit_code:-0}" \
    --argjson duration "${duration:-null}" \
    --arg branch "$branch" \
    --arg pr_url "$pr_url" \
    --argjson usage "$usage" \
    '.status = $status
     | .end_time = $end_time
     | .exit_code = $exit_code
     | .duration_seconds = $duration
     | .branch = (if $branch == "" then null else $branch end)
     | .pr_url = (if $pr_url == "" then null else $pr_url end)
     | .token_usage = $usage' \
    "$meta" > "$tmp" && mv "$tmp" "$meta" || { rm -f "$tmp"; return 1; }
}

# telemetry_scrub: read stdin, redact identifiers that must never reach GitHub.
# Mirrors scripts/scan-secrets.sh patterns: account IDs, state buckets, ARNs, emails.
telemetry_scrub() {
  sed -E \
    -e 's/tfstate-[0-9]{12}/tfstate-<redacted>/g' \
    -e 's/arn:aws:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:[^ ]*/<redacted-arn>/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted-email>/g' \
    -e 's/(^|[^0-9])([0-9]{12})([^0-9]|$)/\1<redacted-id>\3/g'
}
