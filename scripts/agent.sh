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
# Read-only by default (reviewers). --writable widens the sandbox for a builder agent
# (Claude: adds Edit/Write/Bash; Codex: workspace-write). It never enables an apply;
# the no-local-apply rule is enforced by the agent's own instructions and settings.json.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

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

run_claude() {
  local tools="Read Grep Glob"
  [ "$WRITABLE" -eq 1 ] && tools="Read Grep Glob Edit Write Bash"
  # Rubric as an appended system prompt; the piped stdin is the task/context.
  set -- claude -p --append-system-prompt "$RUBRIC" --allowedTools "$tools"
  [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"
  if [ "${AGENT_DRY_RUN:-0}" = "1" ]; then
    printf 'DRY-RUN provider=claude model=%s writable=%s tools=[%s]\n' "${MODEL:-default}" "$WRITABLE" "$tools"
    printf 'CMD: %s\n' "$*"
    return 0
  fi
  printf '%s' "$CONTEXT" | "$@"
}

run_codex() {
  local sandbox="read-only"
  [ "$WRITABLE" -eq 1 ] && sandbox="workspace-write"
  local last; last="$(mktemp)"
  # Rubric + task combined as the instruction; final message captured cleanly via -o.
  local prompt; prompt="$RUBRIC

---

$CONTEXT"
  set -- codex exec --sandbox "$sandbox" --skip-git-repo-check -C "$REPO_ROOT" -o "$last" -
  [ -n "$MODEL" ] && set -- codex exec --sandbox "$sandbox" --skip-git-repo-check -C "$REPO_ROOT" --model "$MODEL" -o "$last" -
  if [ "${AGENT_DRY_RUN:-0}" = "1" ]; then
    printf 'DRY-RUN provider=codex model=%s writable=%s sandbox=%s\n' "${MODEL:-default}" "$WRITABLE" "$sandbox"
    printf 'CMD: %s\n' "$*"
    rm -f "$last"
    return 0
  fi
  # Codex streams events to stdout; send those to stderr and emit only the final message.
  printf '%s' "$prompt" | "$@" 1>&2
  cat "$last"
  rm -f "$last"
}

log "agent $NAME -> provider=$PROVIDER model=${MODEL:-default} writable=$WRITABLE"
case "$PROVIDER" in
  claude) run_claude ;;
  codex)  run_codex ;;
esac
