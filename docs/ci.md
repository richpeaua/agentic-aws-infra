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

## Pipeline anatomy

Three workflows live in `.github/workflows/`.
This maps their jobs and `needs:` dependencies so a failing check can be diagnosed without reading the YAML.
For what each gate *tool* checks, see DESIGN "[Gate stack and enforcement](../DESIGN.md#gate-stack-and-enforcement)"; this section is the job graph, not the tool list.

### `pr-checks.yml` (runs on every pull request)

| Job | Needs | What it does | Blocks merge? |
| --- | --- | --- | --- |
| `policy-tests` | - | Rego unit tests for the compliance policies (`conftest verify`). No AWS; always runs. | Yes, via `gate` |
| `discover` | - | Lists the stack roots the PR changed, so gates run only on changed roots. | Feeds `static`/`plan` |
| `static` | `discover` | Per changed root: `fmt -check`, `validate`, `tflint`. No AWS. Skipped when no root changed. | Yes, via `gate` |
| `plan` | `discover` | Per changed root: `terraform plan` (read role), then Checkov (security), Conftest (compliance), Infracost (advisory). Skipped on fork PRs (no OIDC) and when no root changed. | Yes, via `gate` |
| `module-tests` | - | Native `terraform test` for modules that ship tests. Mocked providers, offline. | Yes, via `gate` |
| `module-docs` | - | `scripts/gen-docs.sh --check`: fails if any module's `terraform-docs` interface table is out of date. No AWS. | Yes, via `gate` |
| `gate` | `policy-tests`, `module-tests`, `static`, `plan`, `module-docs` | Aggregator. `if: always()`; fails if any of those five ended in `failure`/`cancelled`, passes if they succeeded *or were skipped*. | This is the single required status check. |

`gate` is the only required status check on `main`, so branch protection needs just one context even though the matrix jobs and fork-skips make the others come and go.
Because `gate` treats *skipped* as pass, a PR that changes no stack root (docs-only) or comes from a fork still passes it.
Infracost is advisory: it runs inside `plan` but never fails the job.

### `deploy.yml` (runs on push to `main` touching `stacks/**` or `modules/**`, or manual dispatch)

| Job | Needs | What it does |
| --- | --- | --- |
| `discover` | - | Plans each candidate root with `-detailed-exitcode` (read role) and emits the dev and prod roots that have a *real* diff, so no-op or comment-only changes do not apply. |
| `apply-dev` | `discover` | For each changed dev root (`environment: dev`, dev-apply role): `terraform apply`, then `scripts/smoke.sh`. Runs only if a dev root changed. |
| `apply-prod` | `discover`, `apply-dev` | For each changed prod root (`environment: production`, prod-apply role): `terraform apply`, then smoke. Runs only if a prod root changed. |

The dev-to-prod gate is automatic and lives in `needs: apply-dev`: a failed dev apply or dev smoke test (both are steps of `apply-dev`) leaves `apply-dev` un-succeeded, so `apply-prod` never runs.
A prod-only change (no dev diff) still deploys - `apply-dev` is *skipped*, not failed.
Deploys are serialized (`concurrency: deploy`, no cancel), and there is no human approval between dev and prod; the PR merge is the single deploy approval.

### `drift.yml` (scheduled daily at 09:17 UTC, or manual dispatch)

| Job | Needs | What it does |
| --- | --- | --- |
| `discover` | - | Lists all stack roots. |
| `drift` | `discover` | Plans each root against real state (read role, `-detailed-exitcode`). A non-empty diff (exit 2) is out-of-band drift: it files or comments a `drift`-labelled GitHub issue (which emails the owner) and fails the job, so the scheduled run goes red. A plan error also fails the job. |

## Branch protection on `main`

- Pull request required before merging.
- No force pushes, no deletions, linear history required.
- Required status checks: `gate` (the aggregating job in `pr-checks.yml`) is required before a pull request can merge to `main`.
- `enforce_admins` is off, so repository administrators are not forced through these rules; the no-direct-push-to-`main` rule is enforced by policy (`AGENTS.md`), not by branch-protection admin enforcement.
