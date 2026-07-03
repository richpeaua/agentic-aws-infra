# AGENTS.md

Operating rules for any agent working in this repository.
This is the authoritative "what to do" reference and is intentionally tool-neutral.
For the "why" and the full architecture, read [`DESIGN.md`](./DESIGN.md).
For the CI configuration contract (secret and variable names), read [`docs/ci.md`](./docs/ci.md).
For the provisioning procedure, read [`.claude/skills/provision-aws/SKILL.md`](./.claude/skills/provision-aws/SKILL.md).

## What this repo is

An agentic AWS infrastructure workflow.
An agent authors Terraform, a review panel critiques it, and a GitOps pipeline applies it through automated quality, security, and compliance gates.
Infrastructure is Terraform, state is in S3, environments are dev and prod in one dedicated account, and the repo is public (so nothing sensitive may be committed).

## The golden rule

If a resource exists in AWS, it got there through a merged, gated, CI-run apply.

- Never run `terraform apply` or `terraform destroy` for an application stack. Application applies happen only in CI.
- The only exception: foundational stacks under `foundation/` are applied locally by a human, because they are what let CI apply anything (chicken-and-egg). An agent prepares these and hands off the apply.

## The change workflow

1. Understand the request.
2. Scaffold or edit the stack. For a new stack run `scripts/new-stack.sh <name>`, which generates the module and dev/prod roots from the template. Existing stacks are edited in place.
3. Author the resources in the module, following the naming and tagging conventions.
4. Verify locally with the same tools CI uses: `scripts/check.sh <root>` then `scripts/plan.sh <root>`. Local green must predict CI green.
5. Run the review panel (security, compliance, cost, correctness), fix its findings, and re-plan until the plan shows only intended changes and a re-plan is a no-op.
6. Run `scripts/scan-secrets.sh`, then create a branch, push, and open a pull request with `gh`. Do not apply.
7. CI runs the gates on the PR (plan, tflint, Checkov, Conftest, Infracost).
8. A human reviews and merges the PR (code approval).
9. CI applies to dev and runs smoke tests, then pauses at the `production` environment gate for deploy approval, then applies to prod.

Principle: the local checks and the CI gates run the same tools with the same configs (via `scripts/`), so a change that passes locally passes in CI.

## Hard rules

- No local `apply` or `destroy` of application stacks. Ever.
- Every application change goes through a pull request. No direct pushes to `main` for infrastructure changes once the pipeline is live.
- Run the review panel before opening a PR.
- Never commit account IDs, bucket names, role ARNs, or emails. See "Secrets and scrubbing".
- Do not weaken a blocking gate or a branch protection rule to make a change pass. Fix the change.

## Terraform conventions

- Layout: each stack is a module in `modules/<name>/`, consumed by thin roots `stacks/<name>/dev/` and `stacks/<name>/prod/`.
- State: S3 backend, native lockfile (`use_lockfile = true`), one key per root (`stacks/<name>/<env>/terraform.tfstate`). Backend uses partial config; supply `bucket` via `-backend-config=backend.tfbackend`.
- Tagging: provider `default_tags` with `Project`, `Stack`, `Environment`, and `ManagedBy = "terraform"` on every resource. Set `default_tags` in the root, not the module.
- Naming: base every resource name on `<project>-<stack>-<environment>` (exposed as `local.name` in the scaffolded module). For globally-unique names (for example S3 buckets) append the account ID, sourced from `data.aws_caller_identity.current.account_id` in the root and passed to the module as `var.account_id`. Never hardcode the account ID.
- Modules: prefer pinned community modules (`terraform-aws-modules/*`) for complex infrastructure; raw resources for simple things. Always pin module and provider versions.
- Region: default `us-east-1`.
- Terraform version: pinned via `.terraform-version` (currently 1.15.7, minimum 1.10 for the native S3 lockfile).
- Commit `.terraform.lock.hcl`. Include both `linux_amd64` (CI) and `darwin_arm64` (local) hashes: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.

## Secrets and scrubbing (public repo)

- Never commit account IDs, bucket names, role ARNs, or emails.
- Backends use partial configuration; the `bucket` value lives in a git-ignored `backend.tfbackend` locally and in CI variables.
- Real variable values live in git-ignored `terraform.tfvars` and `*.tfbackend` locally, and in GitHub secrets and variables in CI.
- Before every commit, scan staged content: `git grep --cached -nE "<account-id>|<bucket-prefix>|:role/|@"` and confirm it is clean.
- `.gitignore` excludes `terraform.tfvars`, `*.auto.tfvars`, `*.tfbackend`, `*.tfstate*`, `tfplan`, and `.terraform/`.

## Command surface

Prefer the scripts in `scripts/` over ad hoc commands, so every run and CI do the same thing.

- `scripts/preflight.sh` - verify credentials and tooling.
- `scripts/new-stack.sh <name>` - scaffold a module + dev/prod roots from the template.
- `scripts/check.sh <root>` - fmt, validate, tflint, and the scanners CI runs.
- `scripts/plan.sh <root>` - init against remote state, plan, and estimate cost.
- `scripts/scan-secrets.sh` - fail if forbidden identifiers are staged or tracked.

Authenticate first: `aws sso login --profile aws-infra` then `export AWS_PROFILE=aws-infra`.

## Definition of Done

A change is done when every box in the pull request template checklist is satisfied. In short:

- Module + dev/prod roots, matching the scaffolder shape.
- `scripts/check.sh` and `scripts/plan.sh` pass; a re-plan is a no-op.
- Infracost delta captured; review-panel findings resolved or justified.
- `scripts/scan-secrets.sh` clean; no account IDs, buckets, ARNs, or emails committed.
- `default_tags` present, environment in resource names, provider and module versions pinned.
- No local apply of an application stack; the PR is opened for CI to apply.

## Branches and pull requests

- Branch names: `<type>/<scope>`, where type is `feat`, `fix`, `chore`, `ci`, or `docs` (for example `feat/sqs-queue`).
- One logical change per PR. Fill in the pull request template completely.
- Never push infrastructure changes directly to `main` once the pipeline is live. Use a PR.

## Writing and commit conventions

- Never use the em dash. Use a plain dash `-` instead.
- When writing or substantially editing long Markdown files, put each full sentence on its own line. Preserve normal Markdown structure, but do not wrap multiple sentences onto one physical line.
- Do not auto-add an AI or agent name as a commit co-author or trailer.
- When making technical decisions, do not give much weight to development cost. Prefer quality, simplicity, robustness, scalability, and long-term maintainability.

## Working the build

- Current state lives in `docs/status.md`. Read it first to orient.
- The maturation is tracked as GitHub issues (Phases 2-8, with epic issue #8). Work them in dependency order; do not start a phase before its dependencies are merged.
- Issues labeled `needs-human` contain steps only the repo owner can do (SSO login and apply of foundational stacks, entering secret values, approving the production deploy gate). Prepare everything up to that point and hand off explicitly.
- When something breaks, check `docs/troubleshooting.md` before improvising.

## Where things live

- `docs/status.md` - current build state. Read first.
- `DESIGN.md` - authoritative design and rationale.
- `docs/ci.md` - CI configuration contract (environment, variable, and secret names).
- `docs/troubleshooting.md` - known failure modes and fixes.
- `scripts/` - the command surface shared by local work and CI.
- `templates/stack/` - the canonical stack template used by the scaffolder.
- `.claude/skills/provision-aws/SKILL.md` - the provisioning procedure.
- `.claude/agents/` - the review-panel subagents (added in Phase 5).
- `foundation/` - state backend and GitHub OIDC roles (laptop-applied).
- `modules/` - reusable modules. `stacks/<name>/{dev,prod}/` - per-environment roots.
- `policy/` - Conftest/OPA compliance policies and Checkov config (added in Phase 4).
- `tests/` - post-apply smoke tests (added in Phase 8).
- `.github/workflows/` - CI (added in Phases 4, 7, 8).
