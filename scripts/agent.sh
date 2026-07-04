#!/usr/bin/env bash
# Launch a specialist agent, provider-agnostic.
#
# Runs an agent definition from `.claude/agents/<name>.md` headlessly on one of the
# configured backends (Claude Code or OpenAI Codex), so specialists run as independent
# processes and load can be spread across providers to maximize token utilization.
#
# The markdown body of the agent file (everything after the YAML frontmatter) is the
# portable rubric: it becomes the system prompt on Claude and the instruction preamble
# on Codex. One definition, either provider.
#
# Usage:
#   scripts/agent.sh <agent-name> [--provider claude|codex] [--model M] [--writable]
#   The task/context is read from stdin. The agent's final message is printed to stdout;
#   all diagnostics go to stderr, so stdout stays parseable.
#
#   printf '%s' "$context" | scripts/agent.sh security-reviewer --provider codex
#
# Provider/model routing (flags win, then env, then defaults):
#   --provider / AGENT_PROVIDER_<AGENT> / AGENT_PROVIDER            (default: claude)
#   --model    / AGENT_MODEL_<AGENT> / AGENT_MODEL_<PROVIDER>       (default: backend default)
#   <AGENT> is the agent name uppercased with '-' replaced by '_' (e.g. SECURITY_REVIEWER).
#
# Other env:
#   AGENT_DRY_RUN=1   print the resolved provider/model/command instead of running it.
#
# Read-only by default (reviewers). --writable is reserved for the implementer
# and is constrained here, not left to the child agent's settings.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$REPO_ROOT/scripts/lib/telemetry.sh"

# Optional telemetry hook (off by default, so agent.sh stays usable standalone):
# when a caller exports AGENT_USAGE_FILE, best-effort provider token usage is parsed
# from structured output and written there as normalized JSON. stdout is unchanged.
NAME="${1:?usage: scripts/agent.sh <agent-name> [--provider claude|codex] [--model M] [--writable]}"
shift || true

PROVIDER=""
MODEL=""
WRITABLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER="${2:?--provider needs a value}"; shift 2 ;;
    --model)    MODEL="${2:?--model needs a value}"; shift 2 ;;
    --writable) WRITABLE=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

DEF="$REPO_ROOT/.claude/agents/$NAME.md"
[ -f "$DEF" ] || die "no agent definition at .claude/agents/$NAME.md"

# Env key for this agent: SECURITY_REVIEWER, etc.
AGENT_KEY="$(printf '%s' "$NAME" | tr '[:lower:]-' '[:upper:]_')"

# Resolve provider: flag > per-agent env > global env > default.
if [ -z "$PROVIDER" ]; then
  eval "PROVIDER=\"\${AGENT_PROVIDER_${AGENT_KEY}:-\${AGENT_PROVIDER:-claude}}\""
fi
case "$PROVIDER" in
  claude|codex) ;;
  *) die "unsupported provider '$PROVIDER' (expected claude or codex)" ;;
esac
has "$PROVIDER" || die "provider CLI '$PROVIDER' is not installed"

# Resolve model: flag > per-agent env > per-provider env > empty (backend default).
if [ -z "$MODEL" ]; then
  PROVIDER_KEY="$(printf '%s' "$PROVIDER" | tr '[:lower:]' '[:upper:]')"
  eval "MODEL=\"\${AGENT_MODEL_${AGENT_KEY}:-\${AGENT_MODEL_${PROVIDER_KEY}:-}}\""
fi

# The portable rubric: the agent file body with YAML frontmatter stripped.
RUBRIC="$(awk 'BEGIN{sep=0} /^---[[:space:]]*$/{sep++; next} sep>=2{print}' "$DEF")"
[ -n "$RUBRIC" ] || die "agent definition $NAME.md has no body after its frontmatter"

CONTEXT="$(cat)"
[ -n "$CONTEXT" ] || warn "agent $NAME received empty stdin context"

if [ "$WRITABLE" -eq 1 ] && [ "$NAME" != "implementer" ]; then
  die "--writable is reserved for the implementer; reviewers and other specialists stay read-only"
fi

CLAUDE_IMPLEMENTER_TOOLS="Read Grep Glob Edit Write Bash(git status:*) Bash(git diff:*) Bash(git add:*) Bash(git commit:*) Bash(git push:*) Bash(git switch:*) Bash(git branch:*) Bash(git rev-parse:*) Bash(git log:*) Bash(git show:*) Bash(git fetch:*) Bash(git merge-base:*) Bash(git ls-files:*) Bash(git grep:*) Bash(gh auth status:*) Bash(gh issue view:*) Bash(gh issue comment:*) Bash(gh pr create:*) Bash(gh pr view:*) Bash(gh pr edit:*) Bash(gh pr status:*) Bash(gh pr checks:*) Bash(terraform init:*) Bash(terraform validate:*) Bash(terraform fmt:*) Bash(terraform plan:*) Bash(terraform show:*) Bash(terraform output:*) Bash(terraform providers:*) Bash(terraform version:*) Bash(tflint:*) Bash(checkov:*) Bash(conftest:*) Bash(infracost:*) Bash(shellcheck:*) Bash(bash -n:*) Bash(scripts/preflight.sh:*) Bash(scripts/new-stack.sh:*) Bash(scripts/check.sh:*) Bash(scripts/plan.sh:*) Bash(scripts/lock.sh:*) Bash(scripts/scan-secrets.sh:*) Bash(scripts/review.sh:*) Bash(scripts/smoke.sh:*)"
CLAUDE_IMPLEMENTER_DENY="Bash(terraform apply:*) Bash(terraform destroy:*)"

run_claude() {
  local tools="Read Grep Glob"
  local deny=()
  if [ "$WRITABLE" -eq 1 ]; then
    tools="$CLAUDE_IMPLEMENTER_TOOLS"
    deny=(--disallowedTools "$CLAUDE_IMPLEMENTER_DENY")
  fi
  # Rubric as an appended system prompt; the piped stdin is the task/context.
  set -- claude -p --append-system-prompt "$RUBRIC" --allowedTools "$tools"
  [ "${#deny[@]}" -gt 0 ] && set -- "$@" "${deny[@]}"
  [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"
  if [ "${AGENT_DRY_RUN:-0}" = "1" ]; then
    printf 'DRY-RUN provider=claude model=%s writable=%s tools=[%s]\n' "${MODEL:-default}" "$WRITABLE" "$tools"
    [ "${#deny[@]}" -gt 0 ] && printf 'DENY: %s\n' "$CLAUDE_IMPLEMENTER_DENY"
    printf 'CMD: %s\n' "$*"
    return 0
  fi
  if [ -n "${AGENT_USAGE_FILE:-}" ]; then
    # Structured output lets us record token usage. `.result` is the same final
    # message text a plain run prints, so downstream stdout parsing is unchanged.
    local raw rc=0
    raw="$(mktemp)"
    printf '%s' "$CONTEXT" | "$@" --output-format json >"$raw" || rc=$?
    if [ "$rc" -eq 0 ] && jq -e . >/dev/null 2>&1 <"$raw"; then
      jq -r '.result // ""' "$raw"
      telemetry_usage_from_claude_json "$raw" >"$AGENT_USAGE_FILE" 2>/dev/null || true
    else
      cat "$raw"
      telemetry_usage_unavailable >"$AGENT_USAGE_FILE" 2>/dev/null || true
    fi
    rm -f "$raw"
    return "$rc"
  fi
  printf '%s' "$CONTEXT" | "$@"
}

run_codex() {
  local sandbox="read-only"
  if [ "$WRITABLE" -eq 1 ]; then
    [ "${IMPLEMENTER_CODEX_OPT_IN:-0}" = "1" ] || die "writable Codex implementer runs are disabled unless IMPLEMENTER_CODEX_OPT_IN=1"
    sandbox="workspace-write"
  fi
  local last; last="$(mktemp)"
  # Rubric + task combined as the instruction; final message captured cleanly via -o.
  local prompt; prompt="$RUBRIC

---

$CONTEXT"
  set -- codex exec --sandbox "$sandbox" --ask-for-approval never --skip-git-repo-check -C "$REPO_ROOT" -o "$last" -
  [ -n "$MODEL" ] && set -- codex exec --sandbox "$sandbox" --ask-for-approval never --skip-git-repo-check -C "$REPO_ROOT" --model "$MODEL" -o "$last" -
  if [ "${AGENT_DRY_RUN:-0}" = "1" ]; then
    printf 'DRY-RUN provider=codex model=%s writable=%s sandbox=%s\n' "${MODEL:-default}" "$WRITABLE" "$sandbox"
    printf 'CMD: %s\n' "$*"
    rm -f "$last"
    return 0
  fi
  # Codex streams events to stdout; send those to stderr and emit only the final message.
  if [ -n "${AGENT_USAGE_FILE:-}" ]; then
    # Tee the event stream so we can best-effort parse a token count from it.
    # pipefail preserves codex's exit status (a failed run still aborts here).
    local stream; stream="$(mktemp)"
    printf '%s' "$prompt" | "$@" 2>&1 | tee "$stream" >&2
    telemetry_usage_from_codex "$stream" >"$AGENT_USAGE_FILE" 2>/dev/null || true
    rm -f "$stream"
  else
    printf '%s' "$prompt" | "$@" 1>&2
  fi
  cat "$last"
  rm -f "$last"
}

log "agent $NAME -> provider=$PROVIDER model=${MODEL:-default} writable=$WRITABLE"
case "$PROVIDER" in
  claude) run_claude ;;
  codex)  run_codex ;;
esac
