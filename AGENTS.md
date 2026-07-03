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
2. Author the change as a reusable module in `modules/<name>/` consumed by thin per-environment roots in `stacks/<name>/{dev,prod}/`.
3. Run `terraform fmt`, `validate`, `plan`, and `infracost scan . --llm` locally to produce a draft and a cost figure.
4. Run the review panel (security, compliance, cost, correctness), then fix its findings and re-plan.
5. Create a branch, push, and open a pull request with `gh`. Do not apply.
6. Let CI run the gates (plan, tflint, Checkov, Conftest, Infracost) on the PR.
7. A human reviews and merges the PR (code approval).
8. CI applies to dev and runs smoke tests, then pauses at the `production` environment gate for deploy approval, then applies to prod.

## Hard rules

- No local `apply` or `destroy` of application stacks. Ever.
- Every application change goes through a pull request. No direct pushes to `main` for infrastructure changes once the pipeline is live.
- Run the review panel before opening a PR.
- Never commit account IDs, bucket names, role ARNs, or emails. See "Secrets and scrubbing".
- Do not weaken a blocking gate or a branch protection rule to make a change pass. Fix the change.

## Terraform conventions

- Layout: each stack is a module in `modules/<name>/`, consumed by thin roots `stacks/<name>/dev/` and `stacks/<name>/prod/`.
- State: S3 backend, native lockfile (`use_lockfile = true`), one key per root (`stacks/<name>/<env>/terraform.tfstate`). Backend uses partial config; supply `bucket` via `-backend-config=backend.tfbackend`.
- Tagging: provider `default_tags` with `Project`, `Stack`, `Environment`, and `ManagedBy = "terraform"` on every resource. Include the environment in resource names to avoid collisions in the shared account.
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

## Local commands

- Authenticate: `aws sso login --profile aws-infra` then `export AWS_PROFILE=aws-infra`.
- Init a root: `terraform -chdir=<root> init -backend-config=backend.tfbackend`.
- Cost: `infracost scan . --llm` (Infracost v2; requires an org on dashboard.infracost.io).

## Writing and commit conventions

- Never use the em dash. Use a plain dash `-` instead.
- When writing or substantially editing long Markdown files, put each full sentence on its own line. Preserve normal Markdown structure, but do not wrap multiple sentences onto one physical line.
- Do not auto-add an AI or agent name as a commit co-author or trailer.
- When making technical decisions, do not give much weight to development cost. Prefer quality, simplicity, robustness, scalability, and long-term maintainability.

## Working the build

- The maturation is tracked as GitHub issues (Phases 2-8, with epic issue #8). Work them in dependency order; do not start a phase before its dependencies are merged.
- Issues labeled `needs-human` contain steps only the repo owner can do (SSO login and apply of foundational stacks, entering secret values, approving the production deploy gate). Prepare everything up to that point and hand off explicitly.

## Where things live

- `DESIGN.md` - authoritative design and rationale.
- `docs/ci.md` - CI configuration contract (environment, variable, and secret names).
- `.claude/skills/provision-aws/SKILL.md` - the provisioning procedure.
- `.claude/agents/` - the review-panel subagents (added in Phase 5).
- `foundation/` - state backend and GitHub OIDC roles (laptop-applied).
- `modules/` - reusable modules. `stacks/<name>/{dev,prod}/` - per-environment roots.
- `policy/` - Conftest/OPA compliance policies and Checkov config (added in Phase 4).
- `tests/` - post-apply smoke tests (added in Phase 8).
- `.github/workflows/` - CI (added in Phases 4, 7, 8).
