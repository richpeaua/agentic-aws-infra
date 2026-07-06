# Headless run observability

*Audience: inspecting or debugging headless agent runs - what is recorded and how to view it.*

Lightweight, local-first observability for the headless multi-agent workflow
(`scripts/implement.sh`, `scripts/review.sh`, `scripts/agent.sh`).
It gives durable run records, a viewer, and scrubbed GitHub issue/PR comments, without
sending sensitive local artifacts to a public repo.

## What gets recorded

Every telemetry-enabled run creates a directory under `.agents/runs/<run-id>/`:

- `metadata.json` - run id, kind, agent, provider, model, issue, parent, status,
  start/end time, duration, exit code, branch, PR URL, and token usage.
- `prompt.txt` - the prompt/context handed to the agent.
- `stdout.txt`, `stderr.txt` - the agent's captured output streams. For the writable
  implementer, `stdout.txt` holds the final message and `stderr.txt` carries the live
  progress digest (one line per tool call, plus session-start and result markers).
- `stream.jsonl` - writable Claude implementer only: the full `stream-json` event
  transcript, written incrementally so a long run can be tailed live
  (`tail -f .agents/runs/<id>/stream.jsonl`). Local-only; never posted to GitHub.
- `usage.json` - normalized provider token usage (implementer runs).
- `artifacts/` - review panel only: the shared tool output (diff, plan, checkov,
  conftest, tflint, infracost) plus each reviewer's context/output.

Run kinds:

- `implementer` - one `scripts/implement.sh <issue>` dispatch.
- `review` - a `scripts/review.sh <root>` panel (the parent run).
- `review-child` - one reviewer (`security`/`compliance`/`cost`/`correctness`),
  linked to its parent via `parent` and `<parent-id>-<reviewer>` id.

The store is **git-ignored and may contain sensitive context** (prompts, plan output,
identifiers). Never commit it. See `.agents/README.md`.

## Token usage

Usage is best-effort and never estimated. When the provider's structured output exposes
it, `token_usage` is populated with a `source` of `claude` (or `codex`): reviewers use
Claude Code `--output-format json`, and the writable implementer parses it from the final
result event of the `stream-json` transcript. When it is not available, `token_usage` is
`{input:null, output:null, total:null, source:"unavailable"}`.

## GitHub comments

Implementer runs post two small, scrubbed, bounded comments to the linked issue: one at
start and one at completion/failure. The review panel can post a single summary comment
(`--issue N` and/or `--pr N`) - never four separate reviewer comments. Comments carry only
metadata and verdicts; raw prompts, stdout/stderr, plans, and identifiers are redacted and
stay local.

## Operator workflow

Inspect active and completed runs with `scripts/runs.sh`:

```sh
scripts/runs.sh list                 # active + recent parent runs (implementer + review)
scripts/runs.sh list --children      # also list review-panel reviewer child runs
scripts/runs.sh list --json          # machine-readable (all selected runs)
scripts/runs.sh show <run-id>        # metadata + artifact paths (+ child runs for a panel)
scripts/runs.sh clean --older-than 30d          # prune run dirs older than 30 days
scripts/runs.sh clean --older-than 30d --dry-run # preview what would be removed
```

`list` shows parent runs by default; add `--children` to include reviewers.
While a run is in flight its `status` is `running` and `duration` shows `-`.

## Configuration

- `AGENTS_TELEMETRY=0` disables telemetry entirely; launchers behave exactly as before.
- `AGENTS_RUNS_DIR=<path>` overrides the run store location (default `.agents/runs/`).
- `scripts/agent.sh` stays usable standalone: it records usage only when a caller exports
  `AGENT_USAGE_FILE`. `scripts/implement.sh` and `scripts/review.sh` set this for you.
- `IMPLEMENTER_MAX_BUDGET_USD` (default 5.00) and `IMPLEMENTER_TIMEOUT_SECONDS` (default 1800;
  0 disables) cap a headless writable-implementer session; a tripped ceiling ends the run
  non-zero, so finalization records it as `failed`, never `success`. See
  [`.claude/agents/implementer.md`](../.claude/agents/implementer.md) ("Headless run guards")
  for the full guard set (allowlist scope, budget/time ceiling, truthful finalization).

Telemetry is strictly additive: a telemetry write or a GitHub comment failure is a
non-blocking warning and never fails the underlying agent run.
