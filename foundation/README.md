# foundation/

The two stacks that let CI apply anything else.
They have a chicken-and-egg dependency on the pipeline - they *are* the pipeline's state backend and its CI identity - so they are the **only** stacks a human applies from the laptop.
An agent prepares them and hands off the apply; an agent never applies them.

## The write boundary

- The laptop may apply foundational stacks **only**. Everything under `stacks/` is applied exclusively in CI.
- This boundary is enforced by `.claude/settings.json`, the writable-implementer launcher (`scripts/implement.sh`), and the `provision-aws` skill.
- A deliberately friction-ful break-glass procedure exists for emergencies; it is not an easy button.

See DESIGN.md "Local vs CI write boundary" for the rationale.

## `state-backend/`

The versioned, encrypted S3 bucket that holds all Terraform state, plus the account AWS Budget.
Locking uses the native S3 lockfile (`use_lockfile = true`); DynamoDB is not used.
Each root has its own state key (`foundation/<name>/...`, `stacks/<name>/<env>/...`).

## `github-oidc/`

The GitHub OIDC provider and three IAM roles that give CI short-lived, keyless AWS access.
All trust policies are pinned to `repo:richpeaua/<repo>` and further scoped by claim:

- **Read-only role** - assumed by PR plan jobs. Trust condition on `:pull_request`. Read + plan only.
- **Dev apply role** - `AdministratorAccess`. Trust condition on `:environment:dev`.
- **Prod apply role** - `AdministratorAccess`. Trust condition on `:environment:production`.

Because the apply roles are assumable only from their GitHub Environments, they cannot be assumed from a PR job or a fork.

## Applying (human, laptop)

```sh
aws sso login --profile aws-infra
export AWS_PROFILE=aws-infra

# The state bucket name is git-ignored; it lives in backend.tfbackend locally.
terraform -chdir=foundation/<name> init -backend-config=backend.tfbackend
terraform -chdir=foundation/<name> apply
```

Identifiers (account ID, bucket name, role ARNs, budget email) are never committed: they live in the git-ignored `terraform.tfvars` and `*.tfbackend` here, and in GitHub secrets/variables in CI.
Backends use partial configuration - the `bucket` value is supplied at init time.
