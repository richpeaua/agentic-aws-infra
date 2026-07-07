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
# Provider/model routing (flags win, then env, then frontmatter, then defaults):
#   --provider / AGENT_PROVIDER_<AGENT> / AGENT_PROVIDER            (default: claude)
#   --model    / AGENT_MODEL_<AGENT> / AGENT_MODEL_<PROVIDER>
#            > frontmatter model_<provider> (raw id) > frontmatter tier (via map)
#            > backend default
#   <AGENT> is the agent name uppercased with '-' replaced by '_' (e.g. SECURITY_REVIEWER).
#
# Model tiers. An agent file's frontmatter may declare a semantic `tier`
# (heavy | standard | light) instead of a raw model id; the tier is resolved
# against the central map below for the resolved provider, so roles express
# intent once and the concrete ids live in a single place. A raw
# `model_claude:` / `model_codex:` in frontmatter is an escape hatch that wins
# over the tier for that provider. Nothing in the environment is required for
# a tier to take effect: a `tier: heavy` role runs on the heavy model by default.
#
# Other env:
#   AGENT_DRY_RUN=1   print the resolved provider/model/command instead of running it.
#
# Read-only by default (reviewers). --writable is reserved for the implementer
# and is constrained here, not left to the child agent's settings.
#
# The implementer additionally gets the provision-aws skill injected into its rubric
# on both providers (neither backend auto-loads it under these launch conditions), and
# on Codex a terraform PATH shim enforces the same apply/destroy denial that
# --disallowedTools gives the Claude implementer. One skill file, one guardrail, both
# providers.
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

# Central tier -> model map, one column per provider. A role declares a semantic
# tier in its frontmatter and this is the single place the concrete ids live.
#   Claude: verified against the installed CLI's model aliases.
#   Codex : ids verified against the installed codex CLI (codex-cli 0.142.5) -
#           `gpt-5.5` is recognized by ~/.codex/config.toml
#           ([tui.model_availability_nux]); `gpt-5.5-pro` and `gpt-5.4-mini`
#           come from the codex-bundled openai-docs model map. See PR/#46.
tier_to_model() {
  # $1 provider, $2 tier -> prints the mapped model id, or nothing if unmapped.
  case "$1:$2" in
    claude:heavy)    printf 'claude-opus-4-8' ;;
    claude:standard) printf 'claude-sonnet-4-6' ;;
    claude:light)    printf 'claude-haiku-4-5' ;;
    codex:heavy)     printf 'gpt-5.5-pro' ;;
    codex:standard)  printf 'gpt-5.5' ;;
    codex:light)     printf 'gpt-5.4-mini' ;;
    *) : ;;
  esac
}

# Read a scalar field from the agent file's YAML frontmatter (the first
# `--- ... ---` block). Prints the trimmed, unquoted value, or nothing.
frontmatter_field() {
  # $1 field name, $2 file
  awk -v key="$1" '
    BEGIN { sep = 0; re = "^[[:space:]]*" key "[[:space:]]*:[[:space:]]*" }
    /^---[[:space:]]*$/ { sep++; if (sep >= 2) exit; next }
    sep == 1 && $0 ~ re {
      v = $0; sub(re, "", v); sub(/[[:space:]]*$/, "", v); gsub(/^"|"$/, "", v)
      print v; exit
    }
  ' "$2"
}

# Resolve model. Order: --model flag > AGENT_MODEL_<AGENT> > AGENT_MODEL_<PROVIDER>
# > frontmatter model_<provider> (raw id) > frontmatter tier (via map) > empty
# (backend default). Env and flag win over frontmatter; within frontmatter the
# raw model_<provider> escape hatch wins over the tier.
if [ -z "$MODEL" ]; then
  PROVIDER_KEY="$(printf '%s' "$PROVIDER" | tr '[:lower:]' '[:upper:]')"
  eval "MODEL=\"\${AGENT_MODEL_${AGENT_KEY}:-\${AGENT_MODEL_${PROVIDER_KEY}:-}}\""
fi
if [ -z "$MODEL" ]; then
  RAW_MODEL="$(frontmatter_field "model_$PROVIDER" "$DEF")"
  if [ -n "$RAW_MODEL" ]; then
    MODEL="$RAW_MODEL"
  else
    TIER="$(frontmatter_field tier "$DEF")"
    if [ -n "$TIER" ]; then
      case "$TIER" in
        heavy|standard|light) MODEL="$(tier_to_model "$PROVIDER" "$TIER")" ;;
        *) warn "agent $NAME: unknown tier '$TIER' (expected heavy|standard|light); using backend default" ;;
      esac
    fi
  fi
fi

# The portable rubric: the agent file body with YAML frontmatter stripped.
RUBRIC="$(awk 'BEGIN{sep=0} /^---[[:space:]]*$/{sep++; next} sep>=2{print}' "$DEF")"
[ -n "$RUBRIC" ] || die "agent definition $NAME.md has no body after its frontmatter"

CONTEXT="$(cat)"
[ -n "$CONTEXT" ] || warn "agent $NAME received empty stdin context"

# The implementer's playbook is the provision-aws skill. Neither launcher path can
# rely on runtime skill auto-discovery - Codex has no skills mechanism, and the Claude
# headless tool allowlist below deliberately excludes the Skill tool - so inject the
# canonical skill body into the rubric for both providers. One source of truth:
# .claude/skills/provision-aws/SKILL.md (Codex is fed the same file, not a copy).
if [ "$NAME" = "implementer" ]; then
  SKILL_FILE="$REPO_ROOT/.claude/skills/provision-aws/SKILL.md"
  if [ -f "$SKILL_FILE" ]; then
    SKILL_BODY="$(awk 'BEGIN{sep=0} /^---[[:space:]]*$/{sep++; next} sep>=2{print}' "$SKILL_FILE")"
    [ -n "$SKILL_BODY" ] || warn "provision-aws SKILL.md has no body after its frontmatter"
    RUBRIC="$RUBRIC

---

# provision-aws skill (the implementer's playbook)

$SKILL_BODY"
  else
    warn "provision-aws skill not found at .claude/skills/provision-aws/SKILL.md"
  fi
fi

# The four review-panel reviewers share one output contract. As with the skill
# above, neither backend auto-loads it, so inline the single source of truth into
# every reviewer's rubric. This guarantees a reviewer on either provider emits the
# `VERDICT:` line that scripts/review.sh parses, instead of relying on it to open a
# linked file. One source: .claude/agents/reviewer-output-contract.md.
case "$NAME" in
  *-reviewer)
    CONTRACT_FILE="$REPO_ROOT/.claude/agents/reviewer-output-contract.md"
    if [ -f "$CONTRACT_FILE" ]; then
      RUBRIC="$RUBRIC

---

$(cat "$CONTRACT_FILE")"
    else
      warn "reviewer output contract not found at .claude/agents/reviewer-output-contract.md"
    fi
    ;;
esac

if [ "$WRITABLE" -eq 1 ] && [ "$NAME" != "implementer" ]; then
  die "--writable is reserved for the implementer; reviewers and other specialists stay read-only"
fi

# Headless writable-implementer guards (backstop ceilings, not normal-run limits).
# A stuck or looping implementer session must fail cheaply rather than run away, so
# the writable path gets a provider-native budget cap and a wall-clock timeout. Both
# are configurable via environment with safe defaults and apply only to the writable
# implementer (reviewers are read-only reasoning and are left unguarded). A tripped
# guard exits non-zero, so finalization records the run as failed, never success.
#   IMPLEMENTER_MAX_BUDGET_USD    Claude --max-budget-usd cap for --print (default 5.00)
#   IMPLEMENTER_TIMEOUT_SECONDS   wall-clock ceiling around dispatch (default 1800; 0 = off)
IMPLEMENTER_MAX_BUDGET_USD="${IMPLEMENTER_MAX_BUDGET_USD:-5.00}"
IMPLEMENTER_TIMEOUT_SECONDS="${IMPLEMENTER_TIMEOUT_SECONDS:-1800}"

# Compact, low-noise progress digest for the writable implementer's stream-json
# events. One line per tool call plus session-start and result markers; content
# text is summarized by length, not dumped. This is rendered to stderr for live
# progress and lands in the git-ignored run store, never in a GitHub comment.
# `fromjson?` skips any non-JSON line so a stray warning cannot break the digest.
CLAUDE_STREAM_DIGEST='
  fromjson?
  | if (.type == "system" and .subtype == "init") then "  · session start"
    elif .type == "assistant" then
      ( .message.content[]?
        | if .type == "tool_use" then "  · tool: \(.name)"
          elif .type == "text" then "  · text (\((.text // "" | length)) chars)"
          else empty end )
    elif .type == "result" then "  · result: \(.subtype // "done") (turns: \(.num_turns // "?"))"
    else empty end'

CLAUDE_IMPLEMENTER_TOOLS="Read Grep Glob Edit Write Bash(git status:*) Bash(git diff:*) Bash(git add:*) Bash(git commit:*) Bash(git push:*) Bash(git switch:*) Bash(git branch:*) Bash(git rev-parse:*) Bash(git log:*) Bash(git show:*) Bash(git fetch:*) Bash(git merge-base:*) Bash(git ls-files:*) Bash(git grep:*) Bash(gh auth status:*) Bash(gh issue view:*) Bash(gh issue comment:*) Bash(gh pr create:*) Bash(gh pr view:*) Bash(gh pr edit:*) Bash(gh pr status:*) Bash(gh pr checks:*) Bash(terraform init:*) Bash(terraform validate:*) Bash(terraform fmt:*) Bash(terraform plan:*) Bash(terraform show:*) Bash(terraform output:*) Bash(terraform providers:*) Bash(terraform version:*) Bash(tflint:*) Bash(checkov:*) Bash(conftest:*) Bash(infracost:*) Bash(shellcheck:*) Bash(bash -n:*) Bash(bash tests/*.sh:*) Bash(tests/*.sh:*) Bash(scripts/preflight.sh:*) Bash(scripts/new-stack.sh:*) Bash(scripts/check.sh:*) Bash(scripts/plan.sh:*) Bash(scripts/lock.sh:*) Bash(scripts/scan-secrets.sh:*) Bash(scripts/review.sh:*) Bash(scripts/smoke.sh:*) Bash(scripts/runs.sh:*)"
CLAUDE_IMPLEMENTER_DENY="Bash(terraform apply:*) Bash(terraform destroy:*)"

run_claude() {
  local tools="Read Grep Glob"
  local deny=()
  # Backstop guards apply to the writable implementer only; reviewers stay unguarded.
  local timeout_secs=0
  if [ "$WRITABLE" -eq 1 ]; then
    tools="$CLAUDE_IMPLEMENTER_TOOLS"
    deny=(--disallowedTools "$CLAUDE_IMPLEMENTER_DENY")
    timeout_secs="$IMPLEMENTER_TIMEOUT_SECONDS"
  fi
  # Rubric as an appended system prompt; the piped stdin is the task/context.
  set -- claude -p --append-system-prompt "$RUBRIC" --allowedTools "$tools"
  [ "${#deny[@]}" -gt 0 ] && set -- "$@" "${deny[@]}"
  # Provider-native budget cap (writable implementer only; --print sessions).
  [ "$WRITABLE" -eq 1 ] && [ -n "$IMPLEMENTER_MAX_BUDGET_USD" ] \
    && set -- "$@" --max-budget-usd "$IMPLEMENTER_MAX_BUDGET_USD"
  [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"
  if [ "${AGENT_DRY_RUN:-0}" = "1" ]; then
    printf 'DRY-RUN provider=claude model=%s writable=%s tools=[%s]\n' "${MODEL:-default}" "$WRITABLE" "$tools"
    [ "${#deny[@]}" -gt 0 ] && printf 'DENY: %s\n' "$CLAUDE_IMPLEMENTER_DENY"
    [ "$WRITABLE" -eq 1 ] && printf 'GUARDS: budget=$%s timeout=%ss\n' "$IMPLEMENTER_MAX_BUDGET_USD" "$timeout_secs"
    [ -n "${AGENT_USAGE_FILE:-}" ] && [ "$WRITABLE" -eq 1 ] && printf 'OUTPUT: stream-json (live digest to stderr; transcript to run store)\n'
    printf 'CMD: %s\n' "$*"
    return 0
  fi
  if [ -n "${AGENT_USAGE_FILE:-}" ] && [ "$WRITABLE" -eq 1 ]; then
    # Writable implementer: stream so long runs show live progress instead of a
    # single end-of-run dump. The full JSONL transcript is tee'd to a file (the
    # run store when AGENT_STREAM_FILE is set, else a temp), a compact digest is
    # rendered to stderr live, and stdout still yields only the final result text.
    # Nothing streamed is ever posted to GitHub; the transcript is local-only.
    local stream_file rm_stream=0 resultf rc=0
    if [ -n "${AGENT_STREAM_FILE:-}" ]; then stream_file="$AGENT_STREAM_FILE"; else stream_file="$(mktemp)"; rm_stream=1; fi
    set +e
    printf '%s' "$CONTEXT" \
      | run_with_timeout "$timeout_secs" "$@" --output-format stream-json --verbose \
      | tee "$stream_file" \
      | jq -Rr --unbuffered "$CLAUDE_STREAM_DIGEST" >&2 2>/dev/null
    rc=${PIPESTATUS[1]}
    set -e
    resultf="$(mktemp)"
    telemetry_claude_stream_result "$stream_file" > "$resultf" 2>/dev/null || true
    if [ "$rc" -eq 0 ] && [ -s "$resultf" ]; then
      jq -r '.result // ""' "$resultf"
      telemetry_usage_from_claude_json "$resultf" >"$AGENT_USAGE_FILE" 2>/dev/null || true
      # Truthfulness: a budget/limit stop can emit a result event flagged is_error.
      # Treat that as a failure so the run is never recorded as success.
      if [ "$(jq -r '.is_error // false' "$resultf" 2>/dev/null)" = "true" ]; then
        warn "claude reported is_error (subtype: $(jq -r '.subtype // "unknown"' "$resultf" 2>/dev/null)); treating run as failed"
        rc=1
      fi
    else
      # No result event (guard trip, crash, or unparseable stream): not a success.
      telemetry_usage_unavailable >"$AGENT_USAGE_FILE" 2>/dev/null || true
      [ "$rc" -eq 0 ] && rc=1
    fi
    rm -f "$resultf"
    [ "$rm_stream" -eq 1 ] && rm -f "$stream_file"
    return "$rc"
  fi
  if [ -n "${AGENT_USAGE_FILE:-}" ]; then
    # Reviewer (read-only) path: buffered structured output, contract unchanged.
    # `.result` is the same final message text a plain run prints.
    local raw rc=0
    raw="$(mktemp)"
    printf '%s' "$CONTEXT" | run_with_timeout "$timeout_secs" "$@" --output-format json >"$raw" || rc=$?
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
  printf '%s' "$CONTEXT" | run_with_timeout "$timeout_secs" "$@"
}

run_codex() {
  local sandbox="read-only"
  # Wall-clock guard for the writable implementer only (Codex exposes no budget flag).
  local timeout_secs=0
  if [ "$WRITABLE" -eq 1 ]; then
    [ "${IMPLEMENTER_CODEX_OPT_IN:-0}" = "1" ] || die "writable Codex implementer runs are disabled unless IMPLEMENTER_CODEX_OPT_IN=1"
    sandbox="workspace-write"
    timeout_secs="$IMPLEMENTER_TIMEOUT_SECONDS"
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
    [ "$WRITABLE" -eq 1 ] && printf 'GUARDS: timeout=%ss (no provider budget flag on codex)\n' "$timeout_secs"
    [ "$WRITABLE" -eq 1 ] && [ "$NAME" = "implementer" ] && printf 'GUARDRAIL: terraform apply/destroy blocked via PATH shim\n'
    printf 'CMD: %s\n' "$*"
    rm -f "$last"
    return 0
  fi
  # Parity guardrail: the Claude writable implementer is denied terraform apply/destroy
  # via --disallowedTools. `codex exec` has no per-command denylist, so enforce the same
  # rule with a terraform shim earlier on PATH that refuses apply/destroy and passes every
  # other invocation through to the real binary. This keeps the "never apply/destroy an
  # application stack" guardrail explicit on both providers rather than implicit.
  if [ "$WRITABLE" -eq 1 ] && [ "$NAME" = "implementer" ]; then
    local real_tf shim_dir
    real_tf="$(command -v terraform || true)"
    if [ -n "$real_tf" ]; then
      shim_dir="$(mktemp -d)"
      cat > "$shim_dir/terraform" <<SHIM
#!/usr/bin/env bash
# Guardrail shim (scripts/agent.sh): block apply/destroy, pass everything else through.
for arg in "\$@"; do
  case "\$arg" in
    -*) continue ;;
    apply|destroy) echo "guardrail: 'terraform \$arg' is blocked for the implementer (application applies are CI-only)" >&2; exit 3 ;;
    *) break ;;
  esac
done
exec "$real_tf" "\$@"
SHIM
      chmod +x "$shim_dir/terraform"
      export PATH="$shim_dir:$PATH"
      trap 'rm -rf "$shim_dir"' RETURN
    else
      warn "terraform not found on PATH; skipping Codex apply/destroy guardrail shim"
    fi
  fi
  # Codex streams events to stdout; send those to stderr and emit only the final message.
  if [ -n "${AGENT_USAGE_FILE:-}" ]; then
    # Tee the event stream so we can best-effort parse a token count from it.
    # pipefail preserves codex's exit status (a failed run still aborts here).
    local stream; stream="$(mktemp)"
    printf '%s' "$prompt" | run_with_timeout "$timeout_secs" "$@" 2>&1 | tee "$stream" >&2
    telemetry_usage_from_codex "$stream" >"$AGENT_USAGE_FILE" 2>/dev/null || true
    rm -f "$stream"
  else
    printf '%s' "$prompt" | run_with_timeout "$timeout_secs" "$@" 1>&2
  fi
  cat "$last"
  rm -f "$last"
}

log "agent $NAME -> provider=$PROVIDER model=${MODEL:-default} writable=$WRITABLE"
case "$PROVIDER" in
  claude) run_claude ;;
  codex)  run_codex ;;
esac
