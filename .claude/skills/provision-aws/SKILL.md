---
name: provision-aws
description: Author, plan, review, and apply AWS infrastructure as Terraform from this repository. Use whenever the user wants to create, change, or destroy AWS cloud resources, add a new stack, or provision infrastructure. Enforces the plan-review-apply loop with human approval gating apply and destroy.
---

# provision-aws

Provision AWS infrastructure as Terraform following the plan-review-apply loop.
The authoritative design lives in `DESIGN.md` at the repository root; read it if you need the full rationale.
The operating rules live in `AGENTS.md`; follow them.
This skill is the operational procedure.

## Non-negotiable rules

1. Never run `terraform apply` or `terraform destroy` without explicit human approval in the current conversation.
   Approval for one change never carries over to another change.
2. Always run `terraform plan` and Infracost first, and present both the plan diff and the monthly cost delta before asking for approval.
3. Every stack lives in its own directory under `stacks/<name>/` with its own S3 state key.
4. Every resource is tagged via the provider `default_tags` block.
5. Prefer pinned community modules (`terraform-aws-modules/*`) for complex infrastructure; use raw resources for simple things.
6. Default region is `us-east-1` unless the user says otherwise.

## Preconditions to check before doing anything

Run these read-only checks. If any fail, stop and tell the user which prerequisite is missing (see `README.md`).

- `aws sts get-caller-identity` succeeds and points at the dedicated account. If it fails, the user needs to run `aws sso login`.
- `terraform version` reports 1.10 or later (required for the native S3 lockfile).
- `infracost --version` works. Infracost v2 requires `infracost auth login` and membership in an org on dashboard.infracost.io. A `scan` that fails with "User has no associated organization" means the org step is missing.
- The state bucket exists. If it does not, the bootstrap has not run yet: go to "Bootstrap" below first.

## The plan-review-apply loop

Follow this for every change.

1. Understand the request. Ask clarifying questions only if genuinely blocked.
2. Decide the stack. New workload means a new `stacks/<name>/` directory. Existing workload means edit that stack.
3. Author the Terraform:
   - Provider block with region and `default_tags` (`Project`, `Stack`, `ManagedBy = "terraform"`, `Environment`).
   - S3 backend block with a unique `key` of `stacks/<name>/terraform.tfstate` and `use_lockfile = true`.
   - Pinned community modules for complex pieces, raw resources for simple ones.
4. `cd stacks/<name>` and run `terraform init`, `terraform fmt`, `terraform validate`.
5. Run `terraform plan -out=tfplan`.
6. Run `infracost scan . --llm` in the stack directory and capture the monthly cost figure plus any FinOps/tagging policy findings. Notes on Infracost v2:
   - `scan` takes the path positionally (`infracost scan .`), not `--path`. There is no `--terraform-var` flag; pass required variables via `TF_VAR_<name>` environment variables.
   - `--llm` gives compact, token-efficient output suited to this workflow.
   - It renamed `breakdown` to `scan` and requires the user to belong to an org on dashboard.infracost.io.
7. Present to the user: a concise summary of what will be created/changed/destroyed, the plan diff highlights, and the monthly cost delta. Then stop and ask for approval.
8. On explicit approval only: run `terraform apply tfplan`.
9. Report the outputs (`terraform output`).

## Destroying

- Destroy is per-stack: `cd stacks/<name>` then `terraform plan -destroy` to preview, present it, and only after explicit approval run `terraform destroy`.
- Never destroy the bootstrap stack casually; it holds the state bucket and budget for everything else.

## Bootstrap (step zero, run once)

The state bucket must exist before any stack can use the S3 backend. The bootstrap solves this chicken-and-egg with local state, then migrates.

1. `cd bootstrap`.
2. Ensure the S3 backend block in `backend.tf` is commented out (it is by default).
3. Fill in `terraform.tfvars` from `terraform.tfvars.example` (unique bucket name, budget limit, alert email).
4. `terraform init`, then run the plan-review-apply loop above to create the state bucket and AWS Budget.
5. After apply, uncomment the backend block in `bootstrap/backend.tf`, then run `terraform init -migrate-state` and confirm the move to S3.

## First real stack

The first target is `stacks/static-site/`, a static S3 website. Use it to validate the whole loop end to end before provisioning anything expensive.

## Conventions reference

- Directory per stack: `stacks/<name>/`.
- Shared reusable modules: `modules/`.
- State keys: `bootstrap/terraform.tfstate` for bootstrap, `stacks/<name>/terraform.tfstate` for stacks.
- Always pin module and provider versions.
- Never commit `terraform.tfvars`, `*.tfstate`, `tfplan`, or `.terraform/` (see `.gitignore`).
