#!/usr/bin/env bash
# Tests for the frontmatter `tier` -> model resolution in scripts/agent.sh.
# Uses AGENT_DRY_RUN=1 so no provider is ever invoked: the launcher prints the
# resolved model on its DRY-RUN line and we assert on that. `claude` and `codex`
# are shadowed with no-op fakes on PATH only so the launcher's "provider CLI
# installed" precheck passes; they are never executed under a dry run.
# Fixture agent definitions are created under .claude/agents/ with a ztiertest-
# prefix and removed on exit.
# Run: tests/agent_tier_test.sh   (or: bash tests/agent_tier_test.sh)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
AGENT="$REPO/scripts/agent.sh"
AGENTS_DIR="$REPO/.claude/agents"

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-tier-test.XXXXXX")"
mkdir -p "$TMP/bin"
# No-op fakes: the dry-run path returns before executing them.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/codex"
chmod +x "$TMP/bin/claude" "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"

# Track fixtures so the trap removes exactly what we created.
FIXTURES=()
mkfixture() {
  # mkfixture <name> <frontmatter-lines...>
  local name="$1"; shift
  local f="$AGENTS_DIR/$name.md"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
    printf -- '---\n\n'
    printf 'Test agent body.\n'
  } > "$f"
  FIXTURES+=("$f")
}
cleanup() { rm -rf "$TMP"; [ "${#FIXTURES[@]}" -gt 0 ] && rm -f "${FIXTURES[@]}"; }
trap cleanup EXIT

# resolve_model <provider> <agent> [extra agent.sh args...]
# -> prints the model token from the DRY-RUN line (or "MISSING").
resolve_model() {
  local prov="$1" name="$2"; shift 2
  local out
  out="$(printf 'ctx' | AGENT_DRY_RUN=1 "$AGENT" "$name" --provider "$prov" "$@" 2>/dev/null)" || true
  printf '%s' "$out" | grep -o 'model=[^ ]*' | head -1 | cut -d= -f2
}

expect() {
  # expect <label> <actual> <wanted>
  if [ "$2" = "$3" ]; then pass "$1 -> $3"; else fail "$1: got '$2', wanted '$3'"; fi
}

mkfixture ztiertest-heavy    "tier: heavy"
mkfixture ztiertest-standard "tier: standard"
mkfixture ztiertest-light    "tier: light"
mkfixture ztiertest-raw      "tier: light" "model_claude: raw-claude-x" "model_codex: raw-codex-x"
mkfixture ztiertest-rawcl    "tier: light" "model_claude: raw-claude-x"
mkfixture ztiertest-none     "description: no tier here"
mkfixture ztiertest-bad      "tier: bogus"

echo "== agent.sh tier -> model resolution =="

# 1) Tier maps to the right model per provider, with no env set.
expect "heavy/claude"    "$(resolve_model claude ztiertest-heavy)"    claude-opus-4-8
expect "heavy/codex"     "$(resolve_model codex  ztiertest-heavy)"    gpt-5.5-pro
expect "standard/claude" "$(resolve_model claude ztiertest-standard)" claude-sonnet-4-6
expect "standard/codex"  "$(resolve_model codex  ztiertest-standard)" gpt-5.5
expect "light/claude"    "$(resolve_model claude ztiertest-light)"    claude-haiku-4-5
expect "light/codex"     "$(resolve_model codex  ztiertest-light)"    gpt-5.4-mini

# 2) --model flag beats the tier.
expect "flag beats tier" "$(resolve_model claude ztiertest-heavy --model flag-x)" flag-x

# 3) Per-agent env beats the tier (and beats per-provider env).
expect "per-agent env beats tier" \
  "$(AGENT_MODEL_ZTIERTEST_HEAVY=agentenv-x resolve_model claude ztiertest-heavy)" agentenv-x
expect "per-agent env beats per-provider env" \
  "$(AGENT_MODEL_ZTIERTEST_HEAVY=agentenv-x AGENT_MODEL_CLAUDE=provenv-x resolve_model claude ztiertest-heavy)" agentenv-x

# 4) Per-provider env beats the tier.
expect "per-provider env beats tier" \
  "$(AGENT_MODEL_CLAUDE=provenv-x resolve_model claude ztiertest-heavy)" provenv-x

# 5) Raw model_<provider> escape hatch beats the tier for that provider.
expect "raw model_claude beats tier" "$(resolve_model claude ztiertest-raw)" raw-claude-x
expect "raw model_codex beats tier"  "$(resolve_model codex  ztiertest-raw)" raw-codex-x

# 6) Raw is per-provider: a claude-only raw leaves codex on the tier map.
expect "raw claude only: claude uses raw" "$(resolve_model claude ztiertest-rawcl)" raw-claude-x
expect "raw claude only: codex uses tier" "$(resolve_model codex  ztiertest-rawcl)" gpt-5.4-mini

# 7) No tier -> backend default (dry-run prints model=default).
expect "no tier -> default" "$(resolve_model claude ztiertest-none)" default

# 8) Unknown tier -> backend default, with a warning on stderr.
expect "bad tier -> default" "$(resolve_model claude ztiertest-bad)" default
baderr="$(printf 'ctx' | AGENT_DRY_RUN=1 "$AGENT" ztiertest-bad --provider claude 2>&1 >/dev/null)" || true
if printf '%s' "$baderr" | grep -q "unknown tier 'bogus'"; then
  pass "bad tier warns on stderr"
else
  fail "bad tier warning missing (stderr: $baderr)"
fi

# 9) DoD demonstration via a throwaway fixture (no real agent file is mutated;
# assigning `tier:` to the live fleet is #48). `tier: heavy` -> claude-opus-4-8
# and `tier: light` -> claude-haiku-4-5 under Claude with no env set. These are
# the same fixtures asserted above; restated here to name the DoD explicitly.
expect "DoD: heavy fixture -> opus (no env)"  "$(resolve_model claude ztiertest-heavy)" claude-opus-4-8
expect "DoD: light fixture -> haiku (no env)" "$(resolve_model claude ztiertest-light)" claude-haiku-4-5

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL AGENT TIER TESTS PASSED"
else
  echo "$fails AGENT TIER TEST(S) FAILED" >&2
  exit 1
fi
