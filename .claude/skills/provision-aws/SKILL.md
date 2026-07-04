---
name: provision-aws
description: Author AWS infrastructure as Terraform and open a pull request for CI to apply. Use whenever the user wants to create, change, or destroy AWS cloud resources or add a stack. Enforces the GitOps loop (author, review panel, PR); never applies application stacks locally.
---

# provision-aws

The procedure for provisioning AWS infrastructure in this repository.
The operating rules live in `AGENTS.md`; follow them. The full rationale is in `DESIGN.md`.
This skill is the step-by-step procedure that implements the workflow in `AGENTS.md`.

## Non-negotiable rules

1. If a resource exists in AWS, it got there through a merged, gated, CI-run apply. Never run `terraform apply` or `terraform destroy` for an application stack.
2. Every application change goes through a pull request. The agent authors and opens PRs; it does not apply.
3. The only local-apply exception is foundational stacks under `foundation/` (see below), and only a human applies those.
4. Never commit account IDs, bucket names, role ARNs, or emails. Run `scripts/scan-secrets.sh` before committing.

## Preconditions

Run `scripts/preflight.sh`. If it reports missing credentials or tooling, stop and tell the user which prerequisite is missing (see `README.md`).
Read `docs/status.md` to orient on the current state.

## The loop

Run the loop autonomously: scaffold, author, check, plan, review panel, and open the PR without pausing for "may I proceed?" checkpoints between steps. There are exactly two human touchpoints per change: the request (planning) and PR review/merge. The only agent-initiated stops are a genuine planning ambiguity (step 1) and the finished PR (step 6). After merge, CI deploys dev then prod with no further human click, so the PR is the deploy approval - open it in that finished, mergeable state.

1. Understand the request. Ask clarifying questions only if genuinely blocked.
2. Scaffold or edit the stack:
   - New stack: `scripts/new-stack.sh <name>` generates the module and dev/prod roots from the template.
   - Existing stack: edit the module in `modules/<name>/`.
3. Author the resources in `modules/<name>/`. Follow the naming and tagging conventions in `AGENTS.md` (base names on `local.name`; append `var.account_id` for globally-unique names; `default_tags` live in the root).
4. Verify locally with the tools CI uses:
   - `scripts/check.sh stacks/<name>/dev` (fmt, validate, tflint, scanners).
   - `scripts/plan.sh stacks/<name>/dev` (init, plan, Infracost). Repeat for `prod`.
5. Run the review panel (below), fix its findings, and re-plan until the plan shows only intended changes and a re-plan is a no-op.
6. `scripts/scan-secrets.sh`, then create a `<type>/<scope>` branch, commit, push, and open a PR with `gh`. Fill in the PR template completely (plan summary, cost, panel findings, Definition of Done).
7. Hand off: CI runs the gates; the human reviews and merges. On merge, CI applies dev, runs dev smoke tests, and - if dev apply and smoke pass - automatically applies prod and runs prod smoke tests. There is no second human gate before prod; the merge is the deploy approval.

Do not apply. Do not merge on the user's behalf unless asked.

## Review panel

Before opening the PR, run the review panel so problems are caught and fixed early (shift-left).
The reviewers are **reasoning-only**: the orchestrator computes the deterministic tool output **once**, and each reviewer reasons over the artifacts it is handed instead of re-gathering context and re-running tools. This is what keeps a panel run from costing 4x the tokens and tool-uses (one author's context, not four).

### Step 1 - compute the shared artifacts once

You have already run `scripts/check.sh` and `scripts/plan.sh` on each changed root (loop step 4). Capture their output once, into files under the scratchpad, so it can be pasted into reviewer prompts:

- The **change diff**: `git diff main...HEAD` (or the staged/working diff before the branch exists).
- The **`terraform plan` JSON** per changed root: `terraform -chdir=<root> show -json tfplan` (from the plan you already ran). This is the primary evidence for replacements and idempotency.
- **Checkov** output for each changed root: `checkov -d <root> --config-file policy/checkov/.checkov.yaml`.
- **Conftest** output: `conftest test <plan.json> --policy policy/conftest`.
- **Infracost** output: `infracost scan <root> --llm` (the monthly estimate and breakdown).
- **tflint** output for each changed root.

`scripts/check.sh` and `scripts/plan.sh` already invoke these tools; the only new work is teeing their output to files. Do not make the reviewers run any of them again.

### Step 2 - gate by risk

Assess the change against the risk heuristic below, then dispatch the matching review.

**Low-risk (single light pass).** Run one review pass (inline, or a single general reviewer) covering all four dimensions briefly, when the change is confined to:

- tag value tweaks, `description`/comment changes, or variable-default changes with no new resources;
- output-only or docs-only changes;
- a plan that shows **no** create/replace/destroy of a resource (only in-place updates to non-security, non-cost attributes).

**Substantial (full four-agent panel).** Run the full panel whenever the change does any of:

- creates, changes, or removes **IAM** (roles, policies, trust, principals) or any resource that grants access;
- touches **networking** (VPC, subnets, security groups, routes, public IPs) or **public exposure** (S3 public access, `0.0.0.0/0`, ACLs/policies);
- adds or changes a **data store** (S3, RDS, DynamoDB, EFS, secrets) or encryption settings;
- shows any **`must be replaced`** or **destroy** in the plan;
- introduces a **new resource type** or a new stack.

When in doubt, run the full panel. Never let risk-gating drop **security** review on a change that touches IAM, networking, or public access.

### Step 3 - dispatch the panel

For a substantial change, dispatch these four read-only subagents (defined in `.claude/agents/`) in parallel. In each prompt, name the changed root(s) and paste the relevant precomputed artifacts:

- `security-reviewer` - insecure configuration and risky patterns (mirrors Checkov). Give it: the diff + plan JSON + Checkov output.
- `compliance-reviewer` - tags, naming, regions, public-bucket intent, structure (mirrors Conftest). Give it: the diff + plan JSON + Conftest output.
- `cost-reviewer` - monthly cost, waste, cheaper alternatives (mirrors Infracost). Give it: the diff + Infracost output.
- `correctness-reviewer` - Terraform quality, idempotency, state design, architecture (mirrors tflint plus judgment). Give it: the diff + plan JSON + tflint output.

Pass enough context that a reviewer never needs to re-run a tool. Under-passing pushes it to ask for reads and erodes the savings. The reviewers still return the structured findings + one-line verdict format.

### Step 4 - resolve

1. Fix every `blocker` and `high` finding; address or consciously accept `medium`/`low`/`nit`.
2. Re-plan and confirm the plan still shows only intended changes. (If a fix materially changes risk, re-run the relevant artifact and reviewer.)
3. Summarize each reviewer's outcome in the PR body's "Review panel findings" section.

If a reviewer cannot run (for example no subagent runtime), perform that review inline against the same rubric in its agent file. Do not skip a dimension.

## Foundational stacks (laptop-applied exception)

Stacks under `foundation/` (state backend, GitHub OIDC roles) are the chicken-and-egg exception: they are what let CI apply everything else, so a human applies them locally.
For these: author, `scripts/check.sh`, `scripts/plan.sh`, present the plan and cost, and hand off the `terraform apply` to the human. The agent still does not apply.

## Command surface

- `scripts/preflight.sh` - verify creds and tooling.
- `scripts/new-stack.sh <name>` - scaffold a stack.
- `scripts/check.sh <root>` - static checks (same as CI).
- `scripts/plan.sh <root>` - plan + cost.
- `scripts/scan-secrets.sh` - pre-commit secret scan.

## Destroying

Destroys go through the pipeline too: open a PR that removes the stack (or the resources), let the gates run, and let CI apply the destroy.
Never destroy an application stack from the laptop. Never destroy `foundation/` casually; it holds the state and roles for everything.
