# Agentic AWS Infrastructure Workflow

A production-minded workflow where a Claude Code agent authors Terraform, a multi-agent panel reviews it, and a GitOps pipeline applies it through automated quality, security, and compliance gates.

The full specification lives in [`DESIGN.md`](./DESIGN.md).
The agent's operating procedure lives in [`.claude/skills/provision-aws/SKILL.md`](./.claude/skills/provision-aws/SKILL.md).

> Status: complete. The v2 GitOps design is fully built and operational end to end. See "Build status" at the bottom and `docs/status.md`.

## How it works

1. You describe infrastructure in natural language.
2. The agent authors Terraform on a branch: a reusable module plus thin per-environment roots.
3. The agent runs a local review panel of specialized subagents (security, compliance, cost, correctness), fixes their findings, and opens a pull request.
4. CI runs the gate stack on the PR (plan, tflint, Checkov, Conftest/OPA, Infracost) and posts the results.
5. You review and merge the PR. That is code approval.
6. CI applies to dev and runs smoke tests, then waits at a GitHub Environment gate for your deploy approval before applying to prod.

The privileged `terraform apply` runs only in CI, never on a laptop, for application stacks.
If a resource exists in AWS, it got there through a merged, gated, CI-run apply.

## Key properties

- GitOps: pull requests are the unit of change and the audit trail.
- No long-lived cloud credentials: local work uses AWS SSO, CI uses GitHub OIDC.
- Tiered gates: formatting, linting, security scanning, and custom compliance policy as code; cost is advisory.
- Multi-agent review shifts quality left, before the PR; CI remains the authoritative backstop.
- Dev and prod environments in a single dedicated account, separated by directory-per-environment plus a shared module.

## Repository layout

```
.github/workflows/   CI: PR checks, deploy pipeline, drift detection
.claude/
  settings.json      local apply/destroy blocked for application stacks
  agents/            security, compliance, cost, correctness reviewer subagents
  skills/provision-aws/   the orchestrator's operating procedure
foundation/          state backend + GitHub OIDC provider and roles (laptop-applied)
modules/             reusable Terraform modules
stacks/<name>/       per-stack thin roots: dev/ and prod/
policy/              Conftest/OPA compliance policies and Checkov config
tests/               post-apply smoke tests
DESIGN.md            authoritative design specification
```

## Prerequisites

- A dedicated AWS account with IAM Identity Center (SSO) and an `AdministratorAccess` permission set.
- Local tooling: `terraform` (>= 1.10), `awscli`, `infracost`, `tflint`, `checkov`, and `conftest`.
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

Complete. All eight phases are built and the pipeline is operational end to end (see `docs/status.md` for the current footprint):

1. Repo and scrub - done.
2. Foundation (state backend + OIDC roles) - done.
3. GitHub configuration (environments, secrets, branch protection) - done.
4. Gates and policy (CI workflows, tflint, Checkov, Conftest) - done.
5. Agent review panel and skill rewrite - done.
6. Refactor stacks into module plus dev/prod roots - done.
7. Deploy pipeline and end-to-end validation - done.
8. QA layer (smoke tests, native `terraform test`, drift detection) - done.

## License

MIT. See [`LICENSE`](./LICENSE).
