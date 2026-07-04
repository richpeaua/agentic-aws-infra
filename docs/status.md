# Build status

Single in-repo source of truth for where the build is.
Update this when a phase completes or the deployed footprint changes.
Detailed phase specs are the GitHub issues (epic: #8).

## Phases

- [x] Phase 1 - Repo and scrub (DESIGN v2, README, LICENSE, AGENTS.md).
- [x] Phase 2 - Foundation: `foundation/state-backend` and `foundation/github-oidc` applied (OIDC provider + read/dev-apply/prod-apply roles).
- [x] Phase 3 - GitHub configuration: `dev` and `production` environments, variables, role-ARN secrets, branch protection. `INFRACOST_API_KEY` set.
- [x] Phase 4 - PR gates + policy (#3): `pr-checks.yml` (policy-tests, discover, static, plan, gate), tflint, Checkov, Conftest + rego unit tests, Infracost. `gate` is the required status check on `main`. Gates are scoped to changed stacks.
- [x] Phase 5 - Agent review panel + skill rewrite (#4). SKILL.md already reconciled to v2; panel subagents in `.claude/agents/` still to add.
- [x] Phase 6 - Refactor static-site into module + dev/prod roots (#5). Merged #10. Old v1 demo destroyed. First stack validated through the full gate pipeline (surfaced and fixed the read-role + native-lockfile issue via `-lock=false`).
- [x] Phase 7 - Deploy pipeline + end-to-end validation (#6). `deploy.yml` applies dev -> smoke -> prod -> smoke. The dev->prod gate is automated (a failed dev apply or dev smoke blocks prod); the single human approval is the PR merge (#18). Validated: dev and prod static-site both deployed through CI and live (HTTP 200).
- [x] Phase 8 - QA layer: native `terraform test` for modules (mock provider, in pr-checks), post-apply smoke tests (`scripts/smoke.sh` in deploy), scheduled `drift.yml` (nightly plan, files a drift issue). deploy now only applies roots with a real plan diff (#7).

## Deployed footprint

- `foundation/state-backend` - S3 state bucket + monthly AWS Budget.
- `foundation/github-oidc` - OIDC provider + three IAM roles.
- `stacks/static-site` - `modules/static-site` + `dev`/`prod` roots. Both environments deployed through the pipeline and live. Buckets `aws-agentic-infra-static-site-{dev,prod}-<account>`.
- `stacks/task-queue` - `modules/task-queue` + `dev`/`prod` roots. SQS work queue + dead-letter queue, deployed to both environments through the pipeline. Queues `aws-agentic-infra-task-queue-{dev,prod}` (+ `-dlq`). Added end to end via the loop (scaffolder -> review panel -> PR #17 -> deploy).

## Tooling in the repo

- `scripts/` - the command surface: `preflight`, `new-stack`, `check`, `plan`, `scan-secrets`, plus `agent.sh`, `implement.sh`, and `review.sh` (agent launchers). Local and CI call these.
- `scripts/lib/telemetry.sh` + `scripts/runs.sh` - headless run observability: durable local records under `.agents/runs/` (git-ignored), scrubbed issue/PR comments, best-effort token usage, and a `list`/`show`/`clean` viewer. See `docs/observability.md`.
- `templates/stack/` - canonical stack template used by `scripts/new-stack.sh`.

## Agent architecture

- Two roles, split for lean context. `AGENTS.md` holds only the universal guardrails (always loaded); infrastructure implementation detail lives in the `provision-aws` skill and loads only when building AWS/Terraform work.
- `.claude/agents/orchestrator.md` - Agile PM: checks GitHub issues before new intake, summarizes open work, asks whether to address open issues or continue with the new request, plans, files implementer issues, manages the specialist agents, and drives the loop to done. Defers non-PM and non-workflow-orchestration actions to the implementer.
- `.claude/agents/implementer.md` - builder: takes one issue, owns all scripting and coding tasks, uses Bash or Python only for scripts with Bash preferred, follows the `provision-aws` skill for AWS/Terraform work, verifies locally, runs the review panel when required, and opens a PR. Never applies application stacks.
- `.claude/agents/{security,compliance,cost,correctness}-reviewer.md` - the read-only review panel.
- Agents run as independent processes, provider-agnostic across Claude Code and Codex, launched via `scripts/agent.sh` (one specialist), `scripts/implement.sh` (the writable implementer), and `scripts/review.sh` (the panel, precompute-once + provider-spread). Reviewer definitions double as native subagents if ever launched in-session.
- The orchestrator can now launch the implementer headlessly with `scripts/implement.sh <issue>`. Writable mode is reserved for the implementer, scoped at the launcher, and denies local `terraform apply`/`destroy`. Codex writable implementer runs are opt-in with `IMPLEMENTER_CODEX_OPT_IN=1` because local plan output can cross the identifier data boundary.
