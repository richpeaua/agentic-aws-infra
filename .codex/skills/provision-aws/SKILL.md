---
name: provision-aws
description: The implementer's playbook for this repository. Use whenever Codex is implementing one AWS infrastructure issue end to end, including Terraform authoring, local verification, review-panel handling, and opening a pull request. Enforces the GitOps loop and the no-local-apply rule for application stacks.
---

# provision-aws - implementer playbook

Use this skill when acting as the implementer for one issue in this repository.
The universal guardrails live in `AGENTS.md`.
The architecture and rationale live in `DESIGN.md`.
Read `docs/status.md` before work so you know the current build state.

## Non-negotiable Rules

1. Never run `terraform apply` or `terraform destroy` for an application stack.
2. Application infrastructure reaches AWS only through a merged PR and CI-run apply.
3. Foundation stacks under `foundation/` are the only local-apply exception, and a human applies them.
4. Never commit account IDs, bucket names, role ARNs, emails, credentials, or local variable files.
5. Run `scripts/scan-secrets.sh` before committing.
6. Do not weaken gates, branch protection, or policy to make a change pass.

## Preconditions

Run `scripts/preflight.sh`.
If required tooling or credentials are missing, stop and report the missing prerequisite.
Read the GitHub issue in full before editing files.
One issue maps to one branch and one pull request.

## Implementation Loop

1. Understand the issue and acceptance criteria.
2. Ask only for decisions that materially change the build.
3. For a new stack, run `scripts/new-stack.sh <name>`.
4. For an existing stack, edit the module under `modules/<name>/` and thin roots under `stacks/<name>/{dev,prod}/`.
5. Follow the Terraform conventions below.
6. Run `scripts/check.sh stacks/<name>/dev` and `scripts/check.sh stacks/<name>/prod` for changed roots.
7. Run `scripts/plan.sh stacks/<name>/dev` and `scripts/plan.sh stacks/<name>/prod` for changed roots.
8. Run the review panel or perform equivalent inline reviews when no subagent runtime is available.
9. Fix all blocker and high findings.
10. Re-run checks and plans until the result is clean and intended.
11. Run `scripts/scan-secrets.sh`.
12. Create a branch named `<type>/<scope>`, commit, push, and open a PR with `gh`.
13. Fill the PR template completely and reference `Closes #<n>`.

Do not apply.
Do not merge the PR unless the user explicitly asks.

## Terraform Conventions

- Layout: reusable logic in `modules/<name>/`, thin roots in `stacks/<name>/dev/` and `stacks/<name>/prod/`.
- State: S3 backend with one key per root, using partial backend config.
- Backend bucket values live in git-ignored `backend.tfbackend` locally and CI variables in GitHub.
- Tags: root provider `default_tags` sets `Project`, `Stack`, `Environment`, and `ManagedBy = "terraform"`.
- Naming: resource names derive from `<project>-<stack>-<environment>`.
- Globally unique names append `var.account_id`, sourced from `data.aws_caller_identity.current.account_id` in the root.
- Never hardcode account IDs.
- Region: default `us-east-1`.
- Terraform version is pinned by `.terraform-version`.
- Commit `.terraform.lock.hcl`.
- Include provider lock hashes for `linux_amd64` and `darwin_arm64` with `scripts/lock.sh <root>` or equivalent.

## Review Panel

Before opening the PR, review the change across four dimensions.
Use the existing Claude reviewer docs in `.claude/agents/` as the authoritative rubrics until Codex-native reviewer launchers exist.

For substantial changes, cover:

- Security: IAM, secrets, encryption, public exposure, auditability, and blast radius.
- Compliance: tags, naming, region, structure, backend partial config, public bucket intent, and secret hygiene.
- Cost: monthly estimate, cost drivers, waste, cheaper alternatives, and unbounded growth risk.
- Correctness: idempotency, plan sanity, state design, module interface, dependencies, pinned versions, and readability.

Precompute shared evidence once:

- `git diff main...HEAD` or the working diff.
- `terraform show -json tfplan` for each changed root after `scripts/plan.sh`.
- Checkov output.
- Conftest output.
- Infracost output.
- tflint output.

If a subagent runtime is available, pass only the relevant evidence to each reviewer.
If no subagent runtime is available, perform the four reviews inline and report findings in the same severity-first format.

Fix every blocker and high finding.
Address or explicitly justify medium, low, and nit findings.

## Command Surface

Prefer repository scripts over ad hoc commands:

- `scripts/preflight.sh`
- `scripts/new-stack.sh <name>`
- `scripts/check.sh <root>`
- `scripts/plan.sh <root>`
- `scripts/lock.sh <root>`
- `scripts/scan-secrets.sh`

Authentication, when needed:

```sh
aws sso login --profile aws-infra
export AWS_PROFILE=aws-infra
```

## Definition Of Done

A change is done when:

- Module and roots match the repo shape.
- Checks pass for every changed root.
- Plans pass for dev and prod and show only intended changes.
- Review findings are resolved or justified.
- Infracost delta is captured.
- Secret scan is clean.
- No forbidden identifiers are committed.
- The PR is open and complete.
- No local application apply or destroy was run.

## Foundation Exception

For stacks under `foundation/`, author and verify the change, then hand the plan to the human for apply.
Codex does not apply foundation changes either unless the user explicitly directs a human-controlled step and the repo rules allow it.
