# Agentic AWS Infrastructure Workflow

*Audience: start here - what this repo is and how the end-to-end workflow runs.*

A production-minded workflow where a Claude Code agent authors Terraform, a multi-agent panel reviews it, and a GitOps pipeline applies it through automated quality, security, and compliance gates.

The full specification lives in [`DESIGN.md`](./DESIGN.md).
The agent's operating procedure lives in [`.claude/skills/provision-aws/SKILL.md`](./.claude/skills/provision-aws/SKILL.md).

> Status: complete. The v2 GitOps design is fully built and operational end to end. See "Build status" at the bottom and `docs/status.md`.

## How it works

You describe infrastructure to the orchestrator agent, which files an issue per unit of work.
An implementer agent authors Terraform on a branch (a reusable module plus thin per-environment roots), a four-agent panel reviews it, and a PR opens.
CI runs the gate stack on the PR; you review and merge (the single code-and-deploy approval); CI then applies to dev, smoke-tests, and automatically applies to prod.
The step-by-step loop is in [`DESIGN.md`](./DESIGN.md#end-to-end-loop).

The privileged `terraform apply` runs only in CI, never on a laptop, for application stacks.
If a resource exists in AWS, it got there through a merged, gated, CI-run apply.

## Key properties

- GitOps: pull requests are the unit of change and the audit trail.
- No long-lived cloud credentials: local work uses AWS SSO, CI uses GitHub OIDC.
- Tiered gates: formatting, linting, security scanning, and custom compliance policy as code; cost is advisory.
- Multi-agent review shifts quality left, before the PR; CI remains the authoritative backstop.
- Observable runs: every headless agent run writes a durable local record and a scrubbed issue/PR comment, inspectable with `scripts/runs.sh`; see [`docs/observability.md`](./docs/observability.md).
- Dev and prod environments in a single dedicated account, separated by directory-per-environment plus a shared module.

## Repository layout

```
.github/workflows/   CI: PR checks, deploy pipeline, drift detection
.claude/
  settings.json      local apply/destroy blocked for application stacks
  agents/            orchestrator (PM), implementer, and the four reviewers
  skills/provision-aws/   the implementer's operating procedure
scripts/             command surface (see scripts/README.md)
.agents/runs/        git-ignored durable records of headless agent runs
foundation/          state backend + GitHub OIDC, laptop-applied (see foundation/README.md)
modules/             reusable Terraform modules (see modules/README.md)
stacks/<name>/       per-stack thin roots: dev/ and prod/ (see stacks/README.md)
policy/              Conftest/OPA + Checkov policy as code (see policy/README.md)
tests/               tooling, module, and smoke tests (see tests/README.md)
docs/                status, CI contract, observability, troubleshooting
DESIGN.md            authoritative design specification
```

Each major directory carries a local README with its conventions; the docs above stay high-level and point into them.

## Prerequisites

- A dedicated AWS account with IAM Identity Center (SSO) and an `AdministratorAccess` permission set.
- Local tooling: `terraform` (>= 1.10), `awscli`, `gh`, `jq`, `infracost`, `tflint`, `checkov`, `conftest`, and `terraform-docs` (module interface tables; pin the version in `.github/workflows/pr-checks.yml` `TFDOCS_VERSION`).
- An Infracost account (`infracost auth login`) that belongs to an organization.

## Local setup

```
aws sso login --profile aws-infra
export AWS_PROFILE=aws-infra

# Backend config holds the state bucket name and is git-ignored.
cp backend.tfbackend.example <root>/backend.tfbackend   # then set the bucket
terraform -chdir=<root> init -backend-config=backend.tfbackend
```

## Build status

Complete. All phases are built and the pipeline is operational end to end.
See [`docs/status.md`](./docs/status.md) for the current footprint and remaining maturation work.

## License

MIT. See [`LICENSE`](./LICENSE).
