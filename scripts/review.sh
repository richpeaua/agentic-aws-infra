#!/usr/bin/env bash
# Run the shift-left review panel as four independent agents.
#
# This is the "compute once, reason many" step (see DESIGN.md "Multi-agent review panel"):
# the deterministic tool output is produced ONCE here, then handed to each reviewer so the
# specialists reason over shared evidence instead of each re-running the tools. Each reviewer
# runs as an independent process via scripts/agent.sh, and the panel is spread across providers
# (Claude and Codex) to maximize token utilization.
#
# Usage:
#   scripts/review.sh <root-dir> [--providers "claude codex"] [--base REF] [--dry-run]
#     e.g. scripts/review.sh stacks/static-site/dev
#
# Exit status: 0 if every blocking reviewer passed; 3 if any returned CHANGES NEEDED
# (blocker/high). Cost is advisory and never fails the panel.
#
# Provider spreading: reviewers are assigned round-robin from --providers (default
# "claude codex"). Per-agent overrides still apply via scripts/agent.sh env vars
# (e.g. AGENT_PROVIDER_SECURITY_REVIEWER=claude).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ROOT="${1:?usage: scripts/review.sh <root-dir> [--providers \"claude codex\"] [--base REF] [--dry-run]}"
shift || true

PROVIDERS_STR="claude codex"
BASE="${REVIEW_BASE:-origin/main}"
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --providers) PROVIDERS_STR="${2:?--providers needs a value}"; shift 2 ;;
    --base)      BASE="${2:?--base needs a value}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
# shellcheck disable=SC2206
PROVIDERS=($PROVIDERS_STR)
[ "${#PROVIDERS[@]}" -ge 1 ] || die "no providers given"

ROOT_ABS="$REPO_ROOT/$ROOT"
[ -d "$ROOT_ABS" ] || die "no such root: $ROOT"

ART="$(mktemp -d "${TMPDIR:-/tmp}/review.XXXXXX")"
trap 'rm -rf "$ART"' EXIT

# capture <artifact-name> <cmd...> : run cmd, tee stdout+stderr into $ART/<name>.txt.
# Never aborts the panel; a failed tool just yields a note the reviewers can see.
capture() {
  local name="$1"; shift
  local out="$ART/$name.txt"
  if "$@" >"$out" 2>&1; then
    ok "artifact: $name"
  else
    printf '(tool did not complete; output above may be partial)\n' >>"$out"
    warn "artifact: $name (non-zero exit; captured partial output)"
  fi
}

log "gathering shared artifacts for $ROOT (once)"

# Change diff, relative to the base ref when available.
if git -C "$REPO_ROOT" rev-parse --verify "$BASE" >/dev/null 2>&1; then
  git -C "$REPO_ROOT" diff "$BASE" -- . >"$ART/diff.txt" 2>/dev/null || true
  ok "artifact: diff (vs $BASE)"
else
  warn "base ref '$BASE' not found; using working-tree diff"
  git -C "$REPO_ROOT" diff >"$ART/diff.txt" 2>/dev/null || true
fi

# tflint (correctness) and checkov (security).
if has tflint && [ -f "$REPO_ROOT/.tflint.hcl" ]; then
  capture tflint sh -c "cd '$ROOT_ABS' && tflint --config '$REPO_ROOT/.tflint.hcl'"
else
  printf '(tflint or .tflint.hcl unavailable)\n' >"$ART/tflint.txt"
fi
if has checkov && [ -f "$REPO_ROOT/policy/checkov/.checkov.yaml" ]; then
  capture checkov checkov -d "$ROOT_ABS" --config-file "$REPO_ROOT/policy/checkov/.checkov.yaml" --compact
else
  printf '(checkov or its config unavailable)\n' >"$ART/checkov.txt"
fi

# Plan (init + plan + JSON), best-effort: needs backend + AWS credentials.
if [ -f "$ROOT_ABS/backend.tfbackend" ]; then
  if terraform -chdir="$ROOT_ABS" init -backend-config=backend.tfbackend -input=false >/dev/null 2>&1 \
     && terraform -chdir="$ROOT_ABS" plan -out=tfplan -input=false -lock=false >"$ART/plan.txt" 2>&1; then
    ok "artifact: plan"
    terraform -chdir="$ROOT_ABS" show -json tfplan >"$ART/plan.json" 2>/dev/null || true
    if has conftest && [ -d "$REPO_ROOT/policy/conftest" ] && [ -s "$ART/plan.json" ]; then
      capture conftest conftest test "$ART/plan.json" --policy "$REPO_ROOT/policy/conftest"
    else
      printf '(conftest or plan JSON unavailable)\n' >"$ART/conftest.txt"
    fi
  else
    warn "plan unavailable (no credentials or init/plan failed); reviewers proceed on the diff and static scans"
    printf '(terraform plan unavailable in this environment)\n' >"$ART/plan.txt"
    printf '(plan JSON unavailable)\n' >"$ART/conftest.txt"
  fi
else
  warn "no backend.tfbackend in $ROOT; skipping plan/conftest artifacts"
  printf '(no backend configured; plan not run)\n' >"$ART/plan.txt"
  printf '(plan JSON unavailable)\n' >"$ART/conftest.txt"
fi

# Infracost (cost).
if has infracost; then
  capture infracost infracost scan "$ROOT_ABS" --llm
else
  printf '(infracost not installed)\n' >"$ART/infracost.txt"
fi

# Which artifacts each reviewer is handed (mirrors DESIGN.md).
artifacts_for() {
  case "$1" in
    security-reviewer)    echo "diff plan checkov" ;;
    compliance-reviewer)  echo "diff plan conftest" ;;
    cost-reviewer)        echo "diff infracost" ;;
    correctness-reviewer) echo "diff plan tflint" ;;
  esac
}

REVIEWERS="security-reviewer compliance-reviewer cost-reviewer correctness-reviewer"

# Build each reviewer's context file and launch it as an independent agent, in parallel,
# assigning providers round-robin to spread load.
i=0
for r in $REVIEWERS; do
  prov="${PROVIDERS[$((i % ${#PROVIDERS[@]}))]}"
  echo "$prov" >"$ART/$r.provider"
  {
    printf 'You are reviewing the proposed change to `%s` in this repository.\n' "$ROOT"
    printf 'Below is the change diff and the pre-run tool output for your dimension. Reason over it and\n'
    printf 'return your findings and one-line VERDICT in the format your rubric specifies. Do not re-run tools.\n\n'
    for a in $(artifacts_for "$r"); do
      printf '===== %s =====\n' "$a"
      if [ -s "$ART/$a.txt" ]; then cat "$ART/$a.txt"; else printf '(no %s artifact)\n' "$a"; fi
      printf '\n'
    done
  } >"$ART/$r.ctx"

  agent_args="$r --provider $prov"
  [ "$DRY_RUN" -eq 1 ] && export AGENT_DRY_RUN=1
  log "dispatch: $r -> $prov"
  # shellcheck disable=SC2086
  "$REPO_ROOT/scripts/agent.sh" $agent_args <"$ART/$r.ctx" >"$ART/$r.out" 2>"$ART/$r.err" &
  i=$((i + 1))
done

wait

# Pull the reviewer's verdict line, tolerant of markdown emphasis (e.g. **VERDICT: PASS**)
# and leading prose. Returns the cleaned text after "VERDICT:", or empty if none.
extract_verdict() {
  grep -aioE 'VERDICT:.*' "$1" 2>/dev/null | tail -1 | sed -E 's/[*_`]//g; s/[[:space:]]+$//'
}

# Aggregate.
echo
log "review panel results for $ROOT"
fail=0
for r in $REVIEWERS; do
  prov="$(cat "$ART/$r.provider")"
  echo
  printf '########## %s  (provider: %s) ##########\n' "$r" "$prov"
  if [ -s "$ART/$r.out" ]; then
    cat "$ART/$r.out"
  else
    warn "$r produced no output; see stderr below"
    sed 's/^/    /' "$ART/$r.err" >&2 || true
  fi
  if extract_verdict "$ART/$r.out" | grep -qi 'CHANGES NEEDED'; then
    fail=1
  fi
done

echo
log "verdict summary"
for r in $REVIEWERS; do
  v="$(extract_verdict "$ART/$r.out")"
  printf '  %-22s %s\n' "$r" "${v:-<no verdict returned>}"
done

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry-run: no agents were actually invoked"
  exit 0
fi

if [ "$fail" -eq 1 ]; then
  die "panel found blocker/high findings (CHANGES NEEDED); resolve them before opening the PR"
fi
ok "panel passed (no blocker/high findings)"
