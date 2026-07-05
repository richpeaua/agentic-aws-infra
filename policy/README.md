# policy/

Policy as code for the PR gates.
These mirror two of the CI blocking gates (see [`../docs/ci.md`](../docs/ci.md)) and are also what the compliance and security review agents reason against before a PR.

## Conftest / OPA (`conftest/`)

Custom "our rules" compliance policy, written in Rego, run against a plan JSON:

```sh
terraform show -json tfplan > plan.json
conftest test plan.json --policy policy/conftest
```

- `terraform.rego` - the rules. Currently:
  - **Required tags** (`deny`): every taggable resource being created or updated must carry `Project`, `Stack`, `Environment`, and `ManagedBy` (supplied via provider `default_tags`, so they appear in `tags_all`).
  - **Environment in name** (`deny`): S3 bucket names must contain `-dev-` or `-prod-` to avoid dev/prod collisions in the shared account.
  - **Public access** (`warn`): opening a bucket's public access is surfaced for explicit confirmation in review, not blocked - public buckets are allowed only when intentional.
- `terraform_test.rego` - unit tests for the rules. Add a test alongside every new rule; run with `conftest verify --policy policy/conftest`.

Any `deny` blocks merge. `warn` is advisory.

## Checkov (`checkov/`)

Security scanning of the Terraform HCL (CIS and best practice). Config in `.checkov.yaml`.

The gate **blocks on any failed check**. Open-source Checkov attaches no severity metadata, so severity-based gating (soft-fail + hard-fail-on HIGH/CRITICAL) silently never fires. The rule instead: every finding is either fixed or explicitly waived. Two kinds of waiver:

- **Resource-specific intentional exceptions** (e.g. an intentionally public bucket) are waived inline in the Terraform with a reason: `#checkov:skip=CKV_AWS_ID:reason`. Checkov scans the HCL directory (not a plan JSON) precisely so these inline waivers are honored.
- **Repo-wide relaxations** (checks outside this personal/demo repo's security bar) are listed under `skip-check:` in `.checkov.yaml`, each with a justification.

Do not add a blanket skip to make a change pass; fix the change or waive the specific finding with a documented reason.

See also: the [troubleshooting entry](../docs/troubleshooting.md#checkov-gate-does-not-block-a-clearly-bad-resource) for why severity-based gating is avoided, and the [review-panel learning](../learnings/multi-agent-review-panel.md#the-moment-it-paid-off) that surfaced the trap.

## Adding a policy

1. Add the rule to `terraform.rego` (Conftest) or a targeted `#checkov:skip` / justified `skip-check` entry (Checkov).
2. Add or update the matching test in `terraform_test.rego`.
3. Run `scripts/check.sh <root>` locally to confirm parity with the CI gate before opening a PR.
