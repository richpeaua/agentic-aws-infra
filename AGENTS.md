# AGENTS.md

The universal operating rules for any agent working in this repository.
This file is always loaded (via `CLAUDE.md`), so it is kept small and tool-neutral: only the guardrails that bind *every* role.
Role-specific procedure lives elsewhere and loads only when needed - this is deliberate, to keep each agent's context lean.

- Orchestrator (planning, issues, managing the loop): read [`.claude/agents/orchestrator.md`](./.claude/agents/orchestrator.md).
- Implementer (building a change): read [`.claude/agents/implementer.md`](./.claude/agents/implementer.md) and pull the `provision-aws` skill, which carries the implementation procedure, Terraform conventions, command surface, and Definition of Done.
- The "why" and full architecture: [`DESIGN.md`](./DESIGN.md). The CI contract (secret and variable names): [`docs/ci.md`](./docs/ci.md).

## What this repo is

An agentic AWS infrastructure workflow.
An orchestrator agent turns requests into issues, an implementer authors Terraform, a review panel critiques it, and a GitOps pipeline applies it through automated quality, security, and compliance gates.
Infrastructure is Terraform, state is in S3, environments are dev and prod in one dedicated account, and the repo is public (so nothing sensitive may be committed).

## Agent roles

Which role you play is set by the task, not by a flag. Read your role file for the procedure.

- **Orchestrator (Agile project manager).** Handles requests, assists planning, decomposes work into GitHub issues for the implementer, and manages the loop until the work is merged and deployed. Does not author, plan, or apply Terraform.
- **Implementer (builder).** Takes one issue and implements it end to end: author Terraform, verify locally, run the review panel, open a PR. Runs as a separate session per issue. Never applies application stacks.
- **Review panel.** Four read-only reviewer subagents (security, compliance, cost, correctness) the implementer spawns before opening a PR. Defined in `.claude/agents/`.

## The golden rule

If a resource exists in AWS, it got there through a merged, gated, CI-run apply.

- Never run `terraform apply` or `terraform destroy` for an application stack. Application applies happen only in CI.
- The only exception: foundational stacks under `foundation/` are applied locally by a human, because they are what let CI apply anything (chicken-and-egg). An agent prepares these and hands off the apply.

## Hard rules

These bind every role.

- No local `apply` or `destroy` of application stacks. Ever.
- Every application change goes through a pull request. No direct pushes to `main` for infrastructure changes once the pipeline is live.
- Never commit account IDs, bucket names, role ARNs, or emails. See "Secrets and scrubbing".
- Do not weaken a blocking gate or a branch protection rule to make a change pass. Fix the change.
- The implementer runs the review panel before opening a PR.

## Secrets and scrubbing (public repo)

- Never commit account IDs, bucket names, role ARNs, or emails.
- Backends use partial configuration; the `bucket` value lives in a git-ignored `backend.tfbackend` locally and in CI variables.
- Real variable values live in git-ignored `terraform.tfvars` and `*.tfbackend` locally, and in GitHub secrets and variables in CI.
- Before every commit, run `scripts/scan-secrets.sh` (or scan staged content: `git grep --cached -nE "<account-id>|<bucket-prefix>|:role/|@"`) and confirm it is clean.
- `.gitignore` excludes `terraform.tfvars`, `*.auto.tfvars`, `*.tfbackend`, `*.tfstate*`, `tfplan`, and `.terraform/`.

## Branches and pull requests

- Branch names: `<type>/<scope>`, where type is `feat`, `fix`, `chore`, `ci`, or `docs` (for example `feat/sqs-queue`).
- One logical change per PR, mapping to one issue. Fill in the pull request template completely.
- Never push infrastructure changes directly to `main` once the pipeline is live. Use a PR.
- A human reviews and merges the PR. Merge is the single deploy approval; after it, CI applies dev then prod automatically (the inter-environment gate is automated). There is no second human approval before prod.

## Writing and commit conventions

- Never use the em dash. Use a plain dash `-` instead.
- When writing or substantially editing long Markdown files, put each full sentence on its own line. Preserve normal Markdown structure, but do not wrap multiple sentences onto one physical line.
- Do not auto-add an AI or agent name as a commit co-author or trailer.
- When making technical decisions, do not give much weight to development cost. Prefer quality, simplicity, robustness, scalability, and long-term maintainability.

## Working the build

- Current state lives in `docs/status.md`. Read it first to orient.
- The maturation is tracked as GitHub issues. Work them in dependency order; do not start work before its dependencies are merged.
- Issues labeled `needs-human` contain steps only the repo owner can do (SSO login and apply of foundational stacks, entering secret values, the PR merge). Prepare everything up to that point and hand off explicitly.
- When something breaks, check `docs/troubleshooting.md` before improvising.

## Where things live

- `docs/status.md` - current build state. Read first.
- `DESIGN.md` - authoritative design and rationale.
- `docs/ci.md` - CI configuration contract (environment, variable, and secret names).
- `docs/troubleshooting.md` - known failure modes and fixes.
- `.claude/agents/orchestrator.md` - the orchestrator (PM) role.
- `.claude/agents/implementer.md` - the implementer (builder) role.
- `.claude/agents/` - also the review-panel subagents (security, compliance, cost, correctness reviewers).
- `.claude/skills/provision-aws/SKILL.md` - the implementer's playbook: procedure, Terraform conventions, command surface, Definition of Done.
- `scripts/` - the command surface shared by local work and CI.
- `templates/stack/` - the canonical stack template used by the scaffolder.
- `foundation/` - state backend and GitHub OIDC roles (laptop-applied).
- `modules/` - reusable modules. `stacks/<name>/{dev,prod}/` - per-environment roots.
- `policy/` - Conftest/OPA compliance policies and Checkov config.
- `tests/` - post-apply smoke tests.
- `.github/workflows/` - CI (PR checks, deploy, drift).
