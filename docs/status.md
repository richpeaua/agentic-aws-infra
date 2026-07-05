# Build status

Single in-repo source of truth for where the build is.
Keep it current: update this file whenever a phase completes, an issue changes a checkbox state, or the deployed footprint changes. It should never describe completed work as still pending.
Detailed phase specs are the GitHub issues (initial-build epic: #8; v2 handoff-hardening epic: #33; model-routing epic: #45).

## Phases

### Initial build - GitOps pipeline

The end-to-end GitOps pipeline: foundation, gates, deploy, and QA, built and validated live.

- [x] Phase 1 - Repo and scrub (DESIGN v2, README, LICENSE, AGENTS.md).
- [x] Phase 2 - Foundation: `foundation/state-backend` and `foundation/github-oidc` applied (OIDC provider + read/dev-apply/prod-apply roles).
- [x] Phase 3 - GitHub configuration: `dev` and `production` environments, variables, role-ARN secrets, branch protection. `INFRACOST_API_KEY` set.
- [x] Phase 4 - PR gates + policy (#3): `pr-checks.yml` (policy-tests, discover, static, plan, gate), tflint, Checkov, Conftest + rego unit tests, Infracost. `gate` is the required status check on `main`. Gates are scoped to changed stacks.
- [x] Phase 5 - Agent review panel + skill rewrite (#4). SKILL.md reconciled to v2; the four review-panel reviewers (`security`, `compliance`, `cost`, `correctness`) live in `.claude/agents/`.
- [x] Phase 6 - Refactor static-site into module + dev/prod roots (#5). Merged #10. Old v1 demo destroyed. First stack validated through the full gate pipeline (surfaced and fixed the read-role + native-lockfile issue via `-lock=false`).
- [x] Phase 7 - Deploy pipeline + end-to-end validation (#6). `deploy.yml` applies dev -> smoke -> prod -> smoke. The dev->prod gate is automated (a failed dev apply or dev smoke blocks prod); the single human approval is the PR merge (#18). Validated: dev and prod static-site both deployed through CI and live (HTTP 200).
- [x] Phase 8 - QA layer: native `terraform test` for modules (mock provider, in pr-checks), post-apply smoke tests (`scripts/smoke.sh` in deploy), scheduled `drift.yml` (nightly plan, files a drift issue). deploy now only applies roots with a real plan diff (#7).

### v2 - maturing the agentic workflow

With the pipeline live, v2 matures the agent workflow itself: cheaper gates, a cleaner role split, a real headless implementer handoff, run observability, and hardening of that handoff. No change to the deployed AWS footprint.

- [x] v2.1 - Pipeline and review-panel efficiency: PR merge streamlined to the single deploy approval (#21); review panel made cost-efficient via precompute-once shared artifacts, reasoning-only reviewers, and risk-gating (#20).
- [x] v2.2 - Agent architecture: split into orchestrator (PM) and implementer roles with a slimmed, always-loaded `AGENTS.md` (#22); provider-agnostic launcher runs the review panel as independent Claude/Codex processes (#23).
- [x] v2.3 - Headless implementer handoff: branch/PR workflow required of every agent (#25); `scripts/implement.sh` writable implementer launcher (#26) with an expanded coding mandate (#27); Codex/Claude config parity (#40).
- [x] v2.4 - Run observability: durable local run records under `.agents/runs/`, the `scripts/runs.sh` viewer, scrubbed issue/PR comments, and best-effort token usage (#30, #32); documented at the architecture level in DESIGN/README/AGENTS (#43).
- [ ] v2.5 - Handoff hardening and cost controls (epic #33, in progress): widened writable allowlist for repo-owned verification (#34, merged); truthful `success`/`failed`/`incomplete` finalization (#35, merged); runtime/budget guards (#36); live progress and usage visibility (#37); safe GitHub body construction and permission/guard docs (#38).
- [ ] v2.6 - Role-aware model routing and specialist agent expansion (epic #45, planned): pin the right model to each role via semantic tiers declared in agent frontmatter (`heavy`/`standard`/`light`), mapped to a concrete model per provider, honored by both the headless launcher and native subagent paths and enforced against drift (#46, #47, #48); ship a light-tier documentor as the first new specialist (#49); document the routing architecture (#50). Quality-first, cost-capped. No change to the deployed AWS footprint.

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

The agent architecture - the orchestrator/implementer role split, the read-only review panel, and the provider-agnostic headless launchers - is specified in [`DESIGN.md`](../DESIGN.md) ("Roles" and "Multi-agent review panel").
This file tracks build state, not architecture.
