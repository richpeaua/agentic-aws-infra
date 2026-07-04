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
The agent authors Terraform locally, reviews it with a local agent panel, and opens a pull request.
Human involvement is deliberately confined to two touchpoints per change: describing the request (planning), and reviewing and merging the PR. The merge is the single approval - it is both code approval and deploy approval, because the PR already carries the plan, cost, and review-panel findings the human needs to decide. After merge, CI applies dev then prod with no further human click; the gate between them is automated (dev apply and dev smoke must pass before prod runs).
The rule that defines the model: if a resource exists in AWS, it got there through a merged, gated, CI-run apply.

The only exception is foundational infrastructure (see "Local vs CI write boundary").

## Roles

- Human: describes infrastructure in natural language, then reviews and merges PRs. Merge is the single deploy approval; there is no separate environment-gate click.
- Orchestrator agent: the `provision-aws` skill running in Claude Code. It authors the stack, runs the review panel, and opens the PR. It does not apply application stacks.
- Review panel: four read-only Claude Code subagents (Security, Compliance, Cost, Correctness) that critique the draft before the PR.
- CI: GitHub Actions. It runs the gates on PRs and performs applies via short-lived OIDC credentials.

## End-to-end loop

1. The human describes the desired infrastructure.
2. The orchestrator creates or edits a stack as a module plus thin per-environment roots, on a new git branch.
3. The orchestrator runs `terraform fmt`, `validate`, `plan`, and Infracost locally to produce a draft and a cost figure.
4. The orchestrator fans out to the review panel in parallel. Each reviewer is read-only and reports findings.
5. The orchestrator applies fixes for panel findings, then re-plans.
6. The orchestrator pushes the branch and opens a PR with `gh`.
7. CI runs the gate stack on the PR and posts plan, security, compliance, and cost results as a comment.
8. The human reviews and merges the PR. Merge is the single approval - both code and deploy approval.
9. CI applies the change to dev, then runs dev smoke tests.
10. If the dev apply and dev smoke tests pass, CI applies to prod automatically - no human click. The `production` GitHub Environment still restricts the apply to the `main` branch and scopes the prod role, but has no required reviewer. A failed dev apply or dev smoke test blocks the prod apply.
11. CI runs prod smoke tests.

The orchestrator never runs `terraform apply` or `terraform destroy` for an application stack.

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

After the orchestrator drafts a stack, a panel of read-only reviewers critiques it before the PR.
They mirror the CI gates so problems are caught and fixed early (shift-left), while CI remains the authoritative backstop.

- Security agent: reasons like Checkov plus threat modeling. Flags insecure configuration and risky patterns.
- Compliance agent: checks against the Conftest/Rego policies and the tagging and naming standards.
- Cost agent: interprets the Infracost output, flags waste and cheaper alternatives.
- Correctness agent: reviews Terraform quality, state design, and architectural smells that scanners miss.

The reviewers are defined in `.claude/agents/`.
Parallelism belongs in review, not authoring: there is a single author to avoid edit conflicts.

### Precompute once, reason many

The deterministic tools (`terraform plan`, Checkov, Conftest, Infracost, tflint) are run **once** by the orchestrator, which it has already done producing the draft.
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
- GitHub Environments: `dev` (light or no gate) and `production` (no required reviewer; deployment-branch policy restricts it to `main`, and it scopes the prod apply role). The `production` environment is retained for that scoping and branch policy, not for a human gate.
- Promotion: a single PR. On merge, CI applies dev and runs dev smoke tests, then automatically applies prod. The gate between environments is automated - the prod apply depends on the dev apply job, so a failed dev apply or dev smoke test blocks prod. No human approval sits between dev and prod.
- Single human gate: this is a deliberate safety trade. The PR (with its plan, cost, and panel findings) is the informed deploy approval; there is no second pause before prod. It is reversible by re-adding a required reviewer to the `production` environment.

## QA and testing

- Module tests: native `terraform test` in HCL, no Go toolchain. Thin now, grows as modules gain logic.
- Post-apply smoke tests: after each apply, the pipeline verifies the deployed resources actually work (for example, curl a website endpoint, assert outputs resolve, check resource health). Failures fail the deployment and alert.

## Drift detection

A scheduled nightly workflow runs `terraform plan` across all environments.
On detected drift, it opens a GitHub issue and sends an email.
This catches out-of-band changes made outside the pipeline.

## Local vs CI write boundary

- The laptop may apply foundational stacks only: the state backend and the OIDC provider and roles. These have a chicken-and-egg dependency because they are what let CI apply at all.
- The laptop may never apply or destroy application stacks. This is enforced by `.claude/settings.json` and by the `provision-aws` skill.
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
  agents/             # security, compliance, cost, correctness reviewer subagents
  skills/provision-aws/   # orchestrator loop: author -> panel -> PR (no local apply)
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
- Install local tooling: `tflint`, `checkov`, and `conftest` (or `opa`), in addition to `terraform`, `awscli`, and `infracost`.

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
