# CI configuration contract

This documents the GitHub configuration the workflows depend on.
Values live in GitHub, never in the repo.
Workflows must reference these exact names.

## Environments

- `dev`: light gate, no required reviewer. Deployments restricted to protected branches (`main`).
- `production`: requires a reviewer (the repo owner) before the apply job proceeds. Deployments restricted to protected branches (`main`).

## Repository variables (non-secret)

- `AWS_REGION`: default AWS region, `us-east-1`.
- `AWS_ACCOUNT_ID`: the dedicated account ID.
- `STATE_BUCKET`: the Terraform state bucket name (used for `-backend-config`).
- `TF_VERSION`: Terraform version, matches `.terraform-version`.

## Secrets

- `READ_ROLE_ARN` (repository): OIDC read-only role assumed by PR plan jobs.
- `DEV_APPLY_ROLE_ARN` (environment `dev`): OIDC dev apply role. Readable only by jobs targeting the `dev` environment.
- `PROD_APPLY_ROLE_ARN` (environment `production`): OIDC prod apply role. Readable only by jobs targeting the `production` environment.
- `INFRACOST_API_KEY` (repository): Infracost API key. Set by the repo owner.

## OIDC roles

Provisioned by `foundation/github-oidc`. Trust subjects:

- read role: `repo:richpeaua/agentic-aws-infra:pull_request`.
- dev apply role: `repo:richpeaua/agentic-aws-infra:environment:dev`.
- prod apply role: `repo:richpeaua/agentic-aws-infra:environment:production`.

Workflows that assume a role need `permissions: id-token: write` and use `aws-actions/configure-aws-credentials` with the appropriate role ARN.

## Branch protection on `main`

- Pull request required before merging.
- No force pushes, no deletions, linear history required.
- Required status checks: added in Phase 4 once the PR checks workflow has run once.
- `enforce_admins` is currently off to allow direct pushes during the phased build; tighten when the pipeline is complete.
