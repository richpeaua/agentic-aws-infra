# CI configuration contract

This documents the GitHub configuration the workflows depend on.
Values live in GitHub, never in the repo.
Workflows must reference these exact names.

## Environments

- `dev`: light gate, no required reviewer. Deployments restricted to protected branches (`main`).
- `production`: no required reviewer. Deployments restricted to protected branches (`main`). The environment is retained to scope `PROD_APPLY_ROLE_ARN` and enforce the `main`-only branch policy, not to gate on a human click.

The gate between dev and prod is automated, not a human approval: in `deploy.yml` the `apply-prod` job `needs: [discover, apply-dev]`, so a failed dev apply or a failed dev smoke test (a step within `apply-dev`) blocks the prod apply. The single human approval per change is the PR merge.

### Owner action: remove the `production` required reviewer

The single-gate model requires removing the required reviewer from the `production` environment while keeping its `main`-only branch policy. This is an owner-authenticated action (not something CI or an agent does):

```
printf '%s' '{"reviewers":[],"deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}' \
  | gh api --method PUT repos/richpeaua/agentic-aws-infra/environments/production --input -
```

This clears the required-reviewer protection rule and leaves the branch policy intact (deployments stay restricted to `main`). To restore a manual prod pause later, re-add a required reviewer to the `production` environment (via the API or the GitHub UI).

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
- Required status checks: `gate` (the aggregating job in `pr-checks.yml`) is required before a pull request can merge to `main`.
- `enforce_admins` is off, so repository administrators are not forced through these rules; the no-direct-push-to-`main` rule is enforced by policy (`AGENTS.md`), not by branch-protection admin enforcement.
