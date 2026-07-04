---
name: provision-aws
description: The implementer's playbook. Author AWS infrastructure as Terraform for one issue and open a pull request for CI to apply. Use whenever you are implementing an infrastructure change (a new stack, a modification, or a destroy), or working an implementer issue. Carries the full procedure, Terraform conventions, command surface, and Definition of Done. Enforces the GitOps loop (author, review panel, PR); never applies application stacks locally.
---

# provision-aws - the implementer's playbook

This skill is the complete procedure for the **implementer** role (see `.claude/agents/implementer.md`).
The orchestrator plans a request, files an issue, and launches a fresh implementer session with `scripts/implement.sh <issue>`.
The implementer follows this skill to build the change and open a PR.
The universal guardrails live in `AGENTS.md`; follow them. The full rationale is in `DESIGN.md`.
The implementation-specific detail (Terraform conventions, command surface, Definition of Done) lives here so it loads only when someone is actually implementing, not in every agent's context.

## Non-negotiable rules

1. If a resource exists in AWS, it got there through a merged, gated, CI-run apply. Never run `terraform apply` or `terraform destroy` for an application stack.
2. Every application change goes through a pull request. You author and open the PR; you do not apply and do not merge on the human's behalf unless asked.
3. The only local-apply exception is foundational stacks under `foundation/` (see below), and only a human applies those.
4. Never commit account IDs, bucket names, role ARNs, or emails. Run `scripts/scan-secrets.sh` before committing.

## Preconditions

Run `scripts/preflight.sh`. If it reports missing credentials or tooling, stop and tell the user which prerequisite is missing (see `README.md`).
Read `docs/status.md` to orient on the current state, and read the issue you are implementing in full.

## The loop

Run the loop autonomously: scaffold, author, check, plan, review panel, and open the PR without pausing for "may I proceed?" checkpoints between steps. The only stops are a genuine ambiguity in the issue (raise it) and the finished PR. One issue is one PR.

1. Understand the issue. Ask clarifying questions only if genuinely blocked; otherwise proceed.
2. Scaffold or edit the stack:
   - New stack: `scripts/new-stack.sh <name>` generates the module and dev/prod roots from the template.
   - Existing stack: edit the module in `modules/<name>/`.
3. Author the resources in `modules/<name>/`, following the Terraform conventions below (base names on `local.name`; append `var.account_id` for globally-unique names; `default_tags` live in the root).
4. Verify locally with the tools CI uses:
   - `scripts/check.sh stacks/<name>/dev` (fmt, validate, tflint, scanners).
   - `scripts/plan.sh stacks/<name>/dev` (init, plan, Infracost). Repeat for `prod`.
5. Run the review panel (below), fix its findings, and re-plan until the plan shows only intended changes and a re-plan is a no-op.
6. `scripts/scan-secrets.sh`, then create a `<type>/<scope>` branch, commit, push, and open a PR with `gh`. Fill in the PR template completely (plan summary, cost, panel findings, Definition of Done). Reference the issue (`Closes #<n>`).
7. Hand off: CI runs the gates; the human reviews and merges. On merge, CI applies dev, runs dev smoke tests, and - if dev apply and smoke pass - automatically applies prod and runs prod smoke tests. There is no second human gate before prod; the merge is the deploy approval.

Do not apply. Do not merge on the user's behalf unless asked.

When launched headlessly, review findings are handled by re-dispatch rather than an interactive conversation.
The orchestrator runs `scripts/implement.sh <issue> --findings <file>` with the prior findings attached, and you fix only that issue's branch.

## Terraform conventions

- Layout: each stack is a module in `modules/<name>/`, consumed by thin roots `stacks/<name>/dev/` and `stacks/<name>/prod/`.
- State: S3 backend, native lockfile (`use_lockfile = true`), one key per root (`stacks/<name>/<env>/terraform.tfstate`). Backend uses partial config; supply `bucket` via `-backend-config=backend.tfbackend`.
- Tagging: provider `default_tags` with `Project`, `Stack`, `Environment`, and `ManagedBy = "terraform"` on every resource. Set `default_tags` in the root, not the module.
- Naming: base every resource name on `<project>-<stack>-<environment>` (exposed as `local.name` in the scaffolded module). For globally-unique names (for example S3 buckets) append the account ID, sourced from `data.aws_caller_identity.current.account_id` in the root and passed to the module as `var.account_id`. Never hardcode the account ID.
- Modules: prefer pinned community modules (`terraform-aws-modules/*`) for complex infrastructure; raw resources for simple things. Always pin module and provider versions.
- Region: default `us-east-1`.
- Terraform version: pinned via `.terraform-version` (currently 1.15.7, minimum 1.10 for the native S3 lockfile).
- Commit `.terraform.lock.hcl`. Include both `linux_amd64` (CI) and `darwin_arm64` (local) hashes: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (or `scripts/lock.sh <root>`).

## Review panel

Before opening the PR, run the review panel so problems are caught and fixed early (shift-left).
The panel runs as **four independent agents**, one per dimension, launched by `scripts/review.sh`. The reviewers are **reasoning-only**: the script computes the deterministic tool output **once** and hands each reviewer only its relevant slice, so the specialists reason over shared evidence instead of each re-running the tools. Reviewers are provider-agnostic and spread across backends (Claude and Codex) to make the most of available tokens.

### Run it

```
scripts/review.sh stacks/<name>/dev
```

`scripts/review.sh` gathers the artifacts once (change diff, `terraform plan` JSON, Checkov, Conftest, tflint, Infracost - plan is best-effort when credentials are absent), then launches the `security`, `compliance`, `cost`, and `correctness` reviewers in parallel via `scripts/agent.sh`, each fed only its relevant artifacts. It prints every reviewer's findings plus a verdict summary and exits non-zero if any reviewer returns `CHANGES NEEDED` (blocker/high). Run it for each changed root.

Provider spreading and models are configurable (the default spreads the four across `claude` and `codex`):

- `scripts/review.sh <root> --providers "claude codex"` - set the round-robin pool.
- `AGENT_PROVIDER_<AGENT>=claude|codex`, `AGENT_MODEL_<AGENT>=<model>` - per-agent overrides (for example `AGENT_PROVIDER_SECURITY_REVIEWER=claude`).
- `AGENT_DRY_RUN=1` or `scripts/review.sh <root> --dry-run` - print the resolved commands without invoking any agent.

### Gate by risk

Scale the panel to the change:

- **Substantial change** - run the full `scripts/review.sh` panel. This is anything that creates, changes, or removes IAM or access; touches networking or public exposure; adds or changes a data store or encryption; shows any `must be replaced`/destroy in the plan; or introduces a new resource type or stack. When in doubt, run the full panel, and never skip **security** on an IAM/networking/public-access change.
- **Trivial change** - a tag tweak, a docs/output-only change, or a plan with no create/replace/destroy. Run a single light pass instead of the full four, for example one reviewer over the diff: `git diff main...HEAD | scripts/agent.sh correctness-reviewer`.

### Resolve

1. Fix every `blocker` and `high` finding; address or consciously accept `medium`/`low`/`nit`.
2. Re-plan and confirm the plan still shows only intended changes, then re-run the panel if a fix materially changed risk.
3. Summarize each reviewer's outcome in the PR body's "Review panel findings" section.

If a backend or agent CLI is unavailable, `scripts/review.sh` degrades gracefully and notes the missing artifacts; do not skip a dimension - run the missing reviewer against the same rubric by other means.

## Definition of Done

A change is done when every box in the pull request template checklist is satisfied. In short:

- Module + dev/prod roots, matching the scaffolder shape.
- `scripts/check.sh` and `scripts/plan.sh` pass; a re-plan is a no-op.
- Infracost delta captured; review-panel findings resolved or justified.
- `scripts/scan-secrets.sh` clean; no account IDs, buckets, ARNs, or emails committed.
- `default_tags` present, environment in resource names, provider and module versions pinned.
- No local apply of an application stack; the PR is opened for CI to apply.

## Foundational stacks (laptop-applied exception)

Stacks under `foundation/` (state backend, GitHub OIDC roles) are the chicken-and-egg exception: they are what let CI apply everything else, so a human applies them locally.
For these: author, `scripts/check.sh`, `scripts/plan.sh`, present the plan and cost, and hand off the `terraform apply` to the human. You still do not apply.

## Command surface

Prefer these scripts over ad hoc commands, so every run and CI do the same thing.

- `scripts/preflight.sh` - verify creds and tooling.
- `scripts/new-stack.sh <name>` - scaffold a stack (module + dev/prod roots).
- `scripts/check.sh <root>` - fmt, validate, tflint, and the scanners CI runs.
- `scripts/plan.sh <root>` - init against remote state, plan, and estimate cost.
- `scripts/lock.sh <root>` - record provider hashes for linux (CI) and macOS (local).
- `scripts/scan-secrets.sh` - fail if forbidden identifiers are staged or tracked.
- `scripts/implement.sh <issue>` - launch this implementer headlessly for one issue with the constrained writable tool surface.
- `scripts/review.sh <root>` - run the review panel as four independent agents (precompute once, spread across providers).
- `scripts/agent.sh <name>` - launch one specialist agent (`.claude/agents/<name>.md`) headlessly on Claude or Codex; context on stdin.

Writable implementer provider policy:

- Claude is the default for credentialed implementer runs.
- Codex writable runs require `IMPLEMENTER_CODEX_OPT_IN=1`, because local plan and scanner output can expose account IDs, bucket names, role ARNs, and emails to OpenAI.
- Never use dangerous sandbox or permission bypass flags.

Authenticate first: `aws sso login --profile aws-infra` then `export AWS_PROFILE=aws-infra`.

## Destroying

Destroys go through the pipeline too: open a PR that removes the stack (or the resources), let the gates run, and let CI apply the destroy.
Never destroy an application stack from the laptop. Never destroy `foundation/` casually; it holds the state and roles for everything.
