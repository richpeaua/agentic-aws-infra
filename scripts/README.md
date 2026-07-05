# scripts/

The command surface shared by local work and CI.
Every script is POSIX-ish Bash, sources `lib.sh`, and is safe to read before running.
CI calls the same scripts, so local runs are shift-left parity, not a separate path.

## Local Terraform helpers

These operate on a single root (a `foundation/<name>` or `stacks/<name>/<env>` directory).
None of them apply application stacks; application applies happen only in CI.

- `preflight.sh` - verify the local environment is ready to work. Read-only; safe anytime.
- `check.sh <root>` - run the same static checks CI runs on a PR: `fmt`, `validate`, `tflint`, and (when configured) Checkov + Conftest.
- `plan.sh <root>` - init against remote state and produce a plan plus an Infracost estimate.
- `lock.sh <root>` - record provider hashes for both CI (linux) and local (macOS) so the committed `.terraform.lock.hcl` works in both places.
- `smoke.sh <root>` - generic post-apply smoke test: if the root exposes a `website_endpoint` output, assert it serves HTTP 200. See [`../tests/README.md`](../tests/README.md).
- `new-stack.sh <name>` - scaffold a new stack (module + dev/prod roots) from `templates/stack/`. See [`../stacks/README.md`](../stacks/README.md).
- `stack-roots.sh [<base-ref>]` - list stack roots as a JSON array for the CI matrix; with a base ref, only roots affected by the diff.
- `scan-secrets.sh` - fail if forbidden identifiers (account IDs, bucket names, role ARNs, emails) appear in staged or tracked content. Run before every commit.

## Agent orchestration

The multi-agent workflow runs specialists as independent headless processes, provider-agnostic across Claude Code and OpenAI Codex.

- `agent.sh <name> [--writable]` - launch one agent definition from `.claude/agents/<name>.md` headlessly on either backend, feeding the markdown body as a portable rubric. `--writable` is reserved for the implementer and grants only the scoped tools needed to author a PR; it denies `terraform apply`/`destroy` and never uses permission-bypass flags.
- `implement.sh <issue> [--findings <file>]` - orchestrator-facing builder entry point. Fetches the issue, applies the writable-provider policy (identifier-bearing runs pinned to Claude unless `IMPLEMENTER_CODEX_OPT_IN=1`), and dispatches the implementer via `agent.sh --writable`.
- `review.sh` - the shift-left review panel. Computes the deterministic tool output once, then hands it to four independent reviewers (security, compliance, cost, correctness) spread across providers. See DESIGN.md "Multi-agent review panel".
- `runs.sh list|show|clean` - viewer for the headless run records under `.agents/runs/`. See [`../docs/observability.md`](../docs/observability.md).

## Shared internals

- `lib.sh` - shared helpers; source it, do not execute. Portable across macOS bash 3.2 and Linux bash 5.
- `lib/telemetry.sh` - run-record and scrubbing helpers (opt-out via `AGENTS_TELEMETRY=0`).
- `lib/implementer.sh` - implementer status classification and finalization helpers.

## See also

- [`../docs/ci.md`](../docs/ci.md) - the CI contract (which scripts each workflow calls, and the secret/variable names).
- [`../docs/observability.md`](../docs/observability.md) - run records and the `runs.sh` viewer.
