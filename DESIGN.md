# DESIGN: Production-Grade Agentic AWS Infrastructure Workflow

This document is the authoritative specification for the workflow.
It is written to be consumed by a Claude Code agent.
Read it fully before authoring, planning, or provisioning anything.

This is version 2 of the design.
Version 1 established a laptop-driven, human-gated, local-apply workflow.
Version 2 matures it into a GitOps pipeline with automated quality, security, and compliance gates, a multi-agent review panel, and dev/prod environments.
Where v2 and v1 conflict, v2 wins.

## North star

The single guiding priority is production rigor: the workflow must be trustworthy, reviewable, auditable, and safe.
Multi-agent orchestration and every tool in the stack exist to serve that rigor, not for novelty.
Prefer quality, simplicity, robustness, and long-term maintainability over speed of iteration.

## Core execution model: GitOps

The privileged action, `terraform apply`, runs in CI, never on a laptop, for all application stacks.
An orchestrator agent (an Agile project manager) turns the request into issues; for each issue an implementer agent authors Terraform locally, reviews it with a local agent panel, and opens a pull request.
Human involvement is deliberately confined to two touchpoints per change: describing the request (planning), and reviewing and merging the PR. The merge is the single approval - it is both code approval and deploy approval, because the PR already carries the plan, cost, and review-panel findings the human needs to decide. After merge, CI applies dev then prod with no further human click; the gate between them is automated (dev apply and dev smoke must pass before prod runs).
The rule that defines the model: if a resource exists in AWS, it got there through a merged, gated, CI-run apply.

The only exception is foundational infrastructure (see "Local vs CI write boundary").

## Roles

- Human: describes infrastructure in natural language, then reviews and merges PRs. Merge is the single deploy approval; there is no separate environment-gate click.
- Orchestrator agent: the Agile project manager (`.claude/agents/orchestrator.md`). It runs intake and planning, decomposes a request into GitHub issues for the implementer, launches the implementer with `scripts/implement.sh`, and manages the specialist agents and the loop to completion. It does not author, plan, or apply Terraform.
- Implementer agent: the builder (`.claude/agents/implementer.md`, driven by the `provision-aws` skill). It takes one issue and implements it - authoring the stack, running the review panel, and opening the PR - as a headless writable session. It does not apply application stacks.
- Review panel: four read-only reviewers (Security, Compliance, Cost, Correctness), defined in `.claude/agents/` and launched as independent, provider-agnostic agents via `scripts/review.sh` to critique the draft before the PR.
- CLIs: the agents run on Claude Code (`claude`) and OpenAI Codex (`codex`), interchangeably per `scripts/agent.sh`, so load spreads across providers.
- CI: GitHub Actions. It runs the gates on PRs and performs applies via short-lived OIDC credentials.

## End-to-end loop

1. The human describes the desired infrastructure to the orchestrator.
2. The orchestrator clarifies scope, plans the work, and files one GitHub issue per independently-shippable unit. The issues are the handoff to the implementer.
3. For each issue the orchestrator launches a separate implementer session with `scripts/implement.sh <issue>`. The implementer creates or edits a stack as a module plus thin per-environment roots on a new branch, and runs `terraform fmt`, `validate`, `plan`, and Infracost locally to produce a draft and a cost figure.
4. The implementer computes the deterministic tool output once and fans out to the review panel in parallel. Each reviewer is read-only, reasons over the provided artifacts, and reports findings.
5. The implementer applies fixes for panel findings, then re-plans. If a headless pass needs follow-up, the orchestrator re-dispatches `scripts/implement.sh <issue> --findings <file>` with the prior findings attached.
6. The implementer pushes the branch and opens a PR with `gh`.
7. CI runs the gate stack on the PR and posts plan, security, compliance, and cost results as a comment.
8. The human reviews and merges the PR. Merge is the single approval - both code and deploy approval.
9. CI applies the change to dev, then runs dev smoke tests.
10. If the dev apply and dev smoke tests pass, CI applies to prod automatically - no human click. The `production` GitHub Environment restricts the apply to `main` and scopes the prod role, but has no required reviewer. A failed dev apply or dev smoke test blocks prod.
11. CI runs prod smoke tests. The orchestrator tracks the issue to done and updates `docs/status.md`.

Neither the orchestrator nor the implementer runs `terraform apply` or `terraform destroy` for an application stack.

## Repository

- Hosting: GitHub, owner `richpeaua`.
- Visibility: public. Therefore every account identifier must be scrubbed from committed files.
- Structure: single monorepo. Stacks, modules, policies, workflows, and agent definitions version together.
- Scrubbing: AWS account ID, state bucket name, role ARNs, and the budget email live in GitHub secrets/variables and a git-ignored local config file, never in committed code.
- Backend parameterization: `backend.tf` uses partial configuration. The `bucket` value is supplied at `init` time via `-backend-config`, from a git-ignored `*.tfbackend` file locally and from CI variables in the pipeline. Non-sensitive backend values (`key`, `region`, `encrypt`, `use_lockfile`) stay in code.
- Fork safety: GitHub does not expose secrets or OIDC to workflows triggered by forked-repo PRs, so an external contributor's PR can never trigger an apply.

## Foundations

### IaC tool

Terraform, pinned via `.terraform-version` (currently 1.15.7, minimum 1.10 for the native S3 lockfile).

### State backend

State lives in a versioned, encrypted S3 bucket.
Locking uses the native S3 lockfile (`use_lockfile = true`). DynamoDB is not used.
Each root has its own state key: `foundation/<name>/terraform.tfstate` and `stacks/<name>/<env>/terraform.tfstate`.

### Authentication

- Local (authoring, plan, foundational apply): AWS IAM Identity Center via `aws sso login`, profile `aws-infra`. Short-lived credentials, no long-lived keys on disk.
- CI (application apply): GitHub OIDC. No stored AWS keys at all.

### Account and blast radius

A single dedicated AWS account is the blast-radius boundary.
The account ID is referenced only via variables and CI configuration, never hardcoded in committed code.
Dev and prod are logically separated within this one account.
Permission sets and CI roles carry `AdministratorAccess`; the account boundary plus the gates and human approvals are the real guards.

### Region and tagging

Default region `us-east-1`.
Every resource is tagged via the provider `default_tags` block with `Project`, `Stack`, `Environment`, and `ManagedBy = "terraform"`.
Resource names include the environment to avoid collisions between dev and prod in the shared account.

## CI identity: GitHub OIDC roles

An OIDC provider and three IAM roles are provisioned as a foundational stack and applied from the laptop.
All role trust policies are pinned to `repo:richpeaua/<repo>` and further scoped by claim:

- Read-only role: assumed by PR plan jobs. Trust condition on `:pull_request`. Read and plan permissions only.
- Dev apply role: `AdministratorAccess`. Trust condition on `:environment:dev`.
- Prod apply role: `AdministratorAccess`. Trust condition on `:environment:production`.

Because the apply roles are assumable only from their GitHub Environments, they cannot be assumed from a PR job or a fork.

## Gate stack and enforcement

Every PR runs the full stack. Enforcement is tiered so that signal stays high.

| Gate | Purpose | Enforcement |
| --- | --- | --- |
| `terraform fmt`, `validate` | Formatting and syntax | Blocks merge |
| `tflint` | AWS-aware linting and provider misconfig | Blocks merge on errors |
| Checkov | Security scanning of the Terraform HCL (CIS and best practice) | Blocks on any finding. Open-source Checkov has no severity metadata, so severity-based gating silently never fires; instead every finding is fixed or explicitly waived inline with a documented `#checkov:skip` reason |
| Conftest / OPA | Custom compliance policy as code, written in Rego (required tags, allowed regions, no public buckets unless explicitly flagged, naming standards) | Blocks merge on any deny |
| Infracost | Monthly cost delta | Advisory only, never blocks |

Blocking gates are configured as required status checks in branch protection.

## Multi-agent review panel

Once a change is drafted on a branch, the review panel runs as four **independent agents** in parallel, launched by `scripts/review.sh`.
They mirror the CI gates so problems are caught and fixed before the PR (shift-left), while CI remains the authoritative backstop.

- Security agent: reasons like Checkov plus threat modeling. Flags insecure configuration and risky patterns.
- Compliance agent: checks against the Conftest/Rego policies and the tagging and naming standards.
- Cost agent: interprets the Infracost output, flags waste and cheaper alternatives.
- Correctness agent: reviews Terraform quality, state design, and architectural smells that scanners miss.

The reviewers are defined in `.claude/agents/`.
Parallelism belongs in review, not authoring: there is a single author (the implementer) to avoid edit conflicts.

### Independent, provider-agnostic agents

The reviewers run as independent processes, not in-session subagents. `scripts/agent.sh` launches any agent definition headlessly on either backend - Claude Code (`claude -p`) or OpenAI Codex (`codex exec`) - by feeding the agent's markdown body as a portable rubric. One definition, either provider.
`scripts/review.sh` uses this to spread the four reviewers across providers (round-robin over Claude and Codex by default, per-agent overridable), so a review draws on more than one token budget and the panel is not bottlenecked on a single account.
The orchestrator manages these specialists as part of its loop: it launches the panel at the point a change is ready to review, and it can launch a single reviewer for a light pass. Because the specialists are independent processes rather than nested subagents, there is no subagent-nesting limit to work around.

The implementer is launched separately through `scripts/implement.sh`, which calls `scripts/agent.sh implementer --writable`.
Writable mode is reserved for the implementer and is constrained at the launcher.
For Claude, the launcher grants only scoped tools and command patterns needed to author a PR: file editing, `git`, `gh`, read-only Terraform commands (`init`, `validate`, `fmt`, `plan`, `show`, `output`, `providers`, `version`), scanners, and repository scripts.
It explicitly denies `terraform apply` and `terraform destroy`.
It never uses dangerous permission bypass flags.

Writable Codex implementer runs are opt-in only.
Terraform plans and local tool output can contain account IDs, bucket names, role ARNs, and emails, which this public repo forbids committing.
By default, identifier-bearing implementer runs are pinned to Claude; Codex can be used only when the operator sets `IMPLEMENTER_CODEX_OPT_IN=1` after deciding the run's data boundary is acceptable.

### Precompute once, reason many

The deterministic tools (`terraform plan`, Checkov, Conftest, Infracost, tflint) are run **once** by `scripts/review.sh`, reusing what the implementer already produced for the draft.
Their output plus the change diff is captured and passed into each reviewer's prompt.
The reviewers are therefore **reasoning-only** (`tools: Read, Grep, Glob`): they reason over the artifacts they are handed and use `Read`/`Grep` only for specific extra context, never re-running the tools or re-reading the whole repo.
This is a deliberate cost design: a naive panel has each of four agents independently re-read the same files and re-run the same tools, roughly quadrupling tokens and tool-uses for identical evidence. Computing shared artifacts once and having specialists reason over them removes that redundancy without losing coverage - each reviewer is given the same information it would have gathered.

### Risk-gating

The panel is scaled to the change. A trivial or low-risk change (a tag tweak, a docs-only or output-only change, a plan with no create/replace/destroy) gets a single light review pass rather than the full four-agent fan-out.
The full panel runs for substantial changes: new or changed IAM, networking, data stores, public exposure, any resource replacement or destroy, or a new resource type or stack.
Security review is never gated away from a change that touches IAM, networking, or public access; when in doubt, the full panel runs.
The explicit heuristic lives in the `provision-aws` skill.

## Environments

Dev and prod coexist in the one account and are separated logically.

- Mechanism: directory-per-environment with a shared module. Each stack is a reusable module in `modules/<name>/`. Thin roots at `stacks/<name>/dev/` and `stacks/<name>/prod/` consume the module, each with its own backend key and `<env>.tfvars`.
- GitHub Environments: `dev` (light or no gate) and `production` (no required reviewer; a deployment-branch policy restricts it to `main`, and it scopes the prod apply role). The `production` environment is retained for that scoping and branch policy, not for a human gate.
- Promotion: a single PR. On merge, CI applies dev and runs dev smoke tests, then automatically applies prod. The gate between environments is automated - the prod apply depends on the dev apply job, so a failed dev apply or dev smoke test blocks prod. No human approval sits between dev and prod; the PR merge is the single deploy approval, and it is reversible by re-adding a required reviewer to the `production` environment.

## QA and testing

- Module tests: native `terraform test` in HCL, no Go toolchain. Thin now, grows as modules gain logic.
- Post-apply smoke tests: after each apply, the pipeline verifies the deployed resources actually work (for example, curl a website endpoint, assert outputs resolve, check resource health). Failures fail the deployment and alert.

## Drift detection

A scheduled nightly workflow runs `terraform plan` across all environments.
On detected drift, it opens a GitHub issue and sends an email.
This catches out-of-band changes made outside the pipeline.

## Local vs CI write boundary

- The laptop may apply foundational stacks only: the state backend and the OIDC provider and roles. These have a chicken-and-egg dependency because they are what let CI apply at all.
- The laptop may never apply or destroy application stacks. This is enforced by `.claude/settings.json`, the writable implementer launcher, and by the `provision-aws` skill.
- A documented, deliberately friction-ful break-glass procedure exists for emergencies. It is not an easy button.

## Secrets and configuration management

- Committed code contains no account IDs, bucket names, role ARNs, or emails.
- Local: a git-ignored config holds the state bucket name and other identifiers, plus `*.tfbackend` files for backend init.
- CI: GitHub secrets and variables hold the account ID, role ARNs, state bucket, region, budget email, and the Infracost API key.
- The `.gitignore` excludes `terraform.tfvars`, `*.auto.tfvars`, `*.tfbackend`, `*.tfstate*`, `tfplan`, and `.terraform/`.

## Repository skeleton (target)

```
.github/
  workflows/
    pr-checks.yml     # plan + tflint + checkov + conftest + infracost on PRs
    deploy.yml        # on merge: apply dev -> smoke -> (auto) apply prod -> smoke
    drift.yml         # scheduled drift detection
.claude/
  settings.json       # local apply/destroy blocked for application stacks; plan/scan allowed
  agents/             # orchestrator (PM), implementer, and the four reviewers (independent agents)
  skills/provision-aws/   # the implementer's playbook: author -> panel -> PR (no local apply)
scripts/
  implement.sh        # orchestrator entry point for a constrained writable implementer
foundation/
  state-backend/      # S3 state bucket + AWS Budget (laptop-applied)
  github-oidc/        # OIDC provider + read, dev-apply, prod-apply roles (laptop-applied)
modules/
  static-site/        # reusable module (was the stack)
stacks/
  static-site/
    dev/              # thin root: module + dev.tfvars + backend key
    prod/             # thin root: module + prod.tfvars + backend key
policy/
  conftest/           # Rego compliance policies
  checkov/            # Checkov config and suppressions
tests/                # smoke test scripts
DESIGN.md
README.md
```

## Agent operating rules

The operating rules for agents live in [`AGENTS.md`](./AGENTS.md), the authoritative tool-neutral reference.
`AGENTS.md` is the "what to do"; this document is the "why".
Claude Code auto-loads them via `CLAUDE.md`, which imports `AGENTS.md`.

## Manual prerequisites (human, performed once)

- Create the public GitHub repo and push.
- Apply the `github-oidc` foundation stack from the laptop.
- In GitHub: create the `dev` and `production` Environments (both with a deployment-branch policy restricting deployments to `main`; no required reviewer - merge is the single deploy gate), add the secrets and variables, and enable branch protection with the blocking gates as required status checks.
- Install local tooling: `gh`, `jq`, `tflint`, `checkov`, and `conftest` (or `opa`), in addition to `terraform`, `awscli`, and `infracost`.

## Build phases

The maturation is built and reviewed one phase at a time.

1. Repo and scrub: git init, parameterize the backend, create the GitHub repo, push.
2. Foundation: rename bootstrap to `foundation/state-backend`; add `foundation/github-oidc` (OIDC provider plus three roles); apply from the laptop.
3. GitHub configuration: Environments, secrets and variables, branch protection.
4. Gates and policy: CI workflows, `tflint`, Checkov config, Conftest Rego policies.
5. Agent panel and skill rewrite: define the four reviewers; update `provision-aws` to author, review, and open PRs without local apply.
6. Refactor static-site into a module plus dev and prod roots.
7. End-to-end validation: destroy the current demo static-site and re-provision it through the pipeline.
8. QA layer: post-apply smoke tests and native `terraform test`.
