# stacks/

Application stacks: the infrastructure CI applies.
An agent never runs `terraform apply`/`destroy` here - if a resource exists in AWS, it got there through a merged, gated, CI-run apply.

**Reference stack:** `stacks/static-site` is the canonical, known-good implementation to mirror when authoring a new stack.
The scaffolder (`scripts/new-stack.sh`) produces the skeleton; `static-site` shows the complete shape - module plus thin `dev`/`prod` roots, tagging, naming, backend wiring, and a deliberate public-access waiver - so copy its structure rather than inventing one.

## Layout: shared module + thin per-environment roots

Each stack is a reusable module in `modules/<name>/`, consumed by two thin roots:

```
modules/<name>/            # the actual resources, environment-agnostic
stacks/<name>/dev/         # thin root: module + dev.tfvars + backend key
stacks/<name>/prod/        # thin root: module + prod.tfvars + backend key
```

Each root has its own backend state key (`stacks/<name>/<env>/terraform.tfstate`) and its own `<env>.tfvars`.
Dev and prod live in the same account, separated by this directory-per-environment structure.
Promotion is a single PR: on merge, CI applies dev, runs dev smoke tests, then automatically applies prod (see DESIGN.md "Environments").

## Conventions

- **Tagging**: every resource is tagged via the provider `default_tags` block with `Project`, `Stack`, `Environment`, and `ManagedBy = "terraform"`. The compliance gate enforces these (see [`../policy/README.md`](../policy/README.md)).
- **Environment in name**: resource names include the environment (e.g. `-dev-`, `-prod-`) so dev and prod never collide in the shared account.
- **Default region**: `us-east-1`.
- **Backend**: partial configuration; the state `bucket` is git-ignored and supplied at init time from a `*.tfbackend` file (locally) or CI variables.

## Scaffolding a new stack

```sh
scripts/new-stack.sh <name>     # name = lowercase letters, digits, dashes
```

This generates `modules/<name>/` plus `stacks/<name>/{dev,prod}/` from `templates/stack/`, so every stack is structurally identical.
Then author the module, run `scripts/check.sh` and `scripts/plan.sh` on each root, run the review panel, and open a PR.
The full procedure lives in the `provision-aws` skill.
