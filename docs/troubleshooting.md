# Troubleshooting

Known failure modes and how to handle them, so agents do not rediscover them differently each time.

## Terraform state and backend

### `terraform init` wants to create the state bucket / shows empty state after moving a stack

The backend `key` defines which state object a root is attached to.
If you move or rename a root, keep the `key` unchanged, or Terraform attaches to a fresh empty state and plans to recreate everything.
To intentionally re-key, use `terraform init -migrate-state`.

### `init` fails with a backend configuration error

Backends use partial configuration. You must pass the bucket:
`terraform init -backend-config=backend.tfbackend`.
The `backend.tfbackend` file is git-ignored; copy it from `backend.tfbackend.example` and set the bucket.

### Backend config changed, init refuses

Use `terraform init -reconfigure -backend-config=backend.tfbackend` when the backend block changed but the state location did not.

## Provider lock file

### CI fails on `terraform init` with a checksum/platform error

The lock file was generated on macOS only.
Record hashes for both platforms and commit the result:
`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.

## Infracost

### `User has no associated organization`

Infracost v2 requires an organization. Create one at dashboard.infracost.io, then re-run.

### `unknown flag: --path` or `breakdown is deprecated`

Infracost v2 renamed `breakdown` to `scan` and takes the path positionally: `infracost scan . --llm`.
There is no `--terraform-var`; pass required variables via `TF_VAR_<name>`.

## GitHub OIDC and CI

### `Not authorized to perform sts:AssumeRoleWithWebIdentity`

The role trust policy `sub` did not match the workflow's token.
Check the role in `foundation/github-oidc`: read role expects `repo:<org>/<repo>:pull_request`; apply roles expect `repo:<org>/<repo>:environment:<env>`.
The job must target the matching GitHub Environment and set `permissions: id-token: write`.

### PR plan fails with `AccessDenied ... s3:PutObject ... terraform.tfstate.tflock`

The S3 native lockfile (`use_lockfile = true`) writes a `.tflock` object to acquire the lock, which needs `s3:PutObject`. The CI read-only role has only `ReadOnlyAccess`, so it cannot write the lock. Run PR plans with `-lock=false`: a plan is a read-only simulation and does not need the state lock. Apply jobs (which use the apply role) still lock normally.

### Fork PRs cannot plan against AWS

By design: GitHub does not give secrets or OIDC to fork-triggered workflows.
Run the static checks (fmt, validate, tflint, Checkov on HCL) on fork PRs and skip the AWS-dependent steps.

## Shell

### A heredoc or inline script errors under zsh

The interactive shell is zsh and can mangle inline Python/JSON.
Write the script to a file and run it, or use a bash script under `scripts/`.

### Ignore the `zoxide` warning

The `zoxide: detected a possible configuration issue` line is shell-init noise and is not an error.
