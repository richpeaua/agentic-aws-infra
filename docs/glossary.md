# Glossary

The repository's load-bearing terms, each with one authoritative home.
This is a lookup, not a second design doc: definitions are short and point to where the term is defined and used in full.
When a definition and its source ever disagree, the source wins - fix the glossary.

## Repository structure

- **module** - The environment-agnostic Terraform that defines a stack's actual resources, living in `modules/<name>/` and reused by that stack's roots. Create one when the same resources are needed by more than one stack; keep single-use infrastructure inline. See [`modules/README.md`](../modules/README.md).
- **root** - A per-environment Terraform working directory that Terraform actually inits, plans, and applies. Each root has its own backend state key (`stacks/<name>/<env>/terraform.tfstate`) and its own `<env>.tfvars`. See [`stacks/README.md`](../stacks/README.md).
- **thin root** - A root that holds almost no resources of its own: it just instantiates the shared module and supplies the environment's `.tfvars` and backend key (`stacks/<name>/{dev,prod}/`). "Thin" is the whole point - the resources live in the module, the roots only differ by environment. See [`stacks/README.md`](../stacks/README.md).
- **stack** - A unit of deployable infrastructure: one reusable module in `modules/<name>/` plus its thin `dev` and `prod` roots under `stacks/<name>/`. See [`stacks/README.md`](../stacks/README.md).
- **application stack** - Any stack under `stacks/` - the infrastructure CI applies. An agent never runs `terraform apply`/`destroy` on one; if a resource exists in AWS, it got there through a merged, gated, CI-run apply. See [`stacks/README.md`](../stacks/README.md) and the golden rule in [`../AGENTS.md`](../AGENTS.md).
- **foundational stack** - The stacks under `foundation/` (the S3 state backend and the OIDC provider and roles) that are what let CI apply anything else, so they are applied locally by a human. They are the sole exception to the no-local-apply rule (a chicken-and-egg carve-out). See [`foundation/README.md`](../foundation/README.md) and DESIGN "[Local vs CI write boundary](../DESIGN.md#local-vs-ci-write-boundary)".

## Roles and agents

- **orchestrator** - The Agile project-manager agent: it runs intake and planning, decomposes a request into GitHub issues, launches the implementer, and manages the loop to done. It does not author, plan, or apply Terraform. See [`.claude/agents/orchestrator.md`](../.claude/agents/orchestrator.md) and DESIGN "[Roles](../DESIGN.md#roles)".
- **implementer** - The builder agent: it takes one issue and implements it end to end - authoring the stack, running the review panel, opening the PR - as a headless writable session. It never applies application stacks. See [`.claude/agents/implementer.md`](../.claude/agents/implementer.md) and DESIGN "[Roles](../DESIGN.md#roles)".
- **the panel** / **reviewer** - The multi-agent review panel: four read-only reviewers (security, compliance, cost, correctness) launched as independent, provider-agnostic agents by `scripts/review.sh` to critique a draft before the PR. A reviewer reasons over supplied artifacts and never edits files. See DESIGN "[Multi-agent review panel](../DESIGN.md#multi-agent-review-panel)".

## Workflow and gates

- **the loop** - The end-to-end flow from a natural-language request to deployed infrastructure: plan, file issues, implement, review panel, PR, human merge, CI apply to dev then prod. See DESIGN "[End-to-end loop](../DESIGN.md#end-to-end-loop)".
- **gate** - A quality/security/compliance/cost check that runs on every PR (`terraform fmt`/`validate`, tflint, Checkov, Conftest/OPA, Infracost). A gate is never weakened to make a change pass; the change is fixed. See DESIGN "[Gate stack and enforcement](../DESIGN.md#gate-stack-and-enforcement)".
- **blocking vs advisory gate** - A blocking gate is a required status check that prevents merge on failure (fmt/validate, tflint, Checkov, Conftest); an advisory gate reports but never blocks (Infracost cost delta). See DESIGN "[Gate stack and enforcement](../DESIGN.md#gate-stack-and-enforcement)".
- **shift-left** - Catching a problem at the cheapest place to fix it: running the review panel locally, before the PR, so issues are found before CI. CI remains the authoritative backstop. See DESIGN "[Gates are the floor, not the ceiling](../DESIGN.md#gates-are-the-floor-not-the-ceiling)".
- **risk-gating** - Scaling the review panel to the change: a trivial or low-risk change gets a single light review pass, while substantial changes (IAM, networking, data stores, public exposure, any replace/destroy) get the full four-agent fan-out. The explicit heuristic lives in the `provision-aws` skill. See DESIGN "[Risk-gating](../DESIGN.md#risk-gating)".
- **precompute-once** - The panel's cost design: the deterministic tools (`terraform plan`, Checkov, Conftest, Infracost, tflint) run once, and their output plus the diff is handed to every reviewer, so the reasoning-only reviewers never re-run tools or re-read the whole repo. See DESIGN "[Precompute once, reason many](../DESIGN.md#precompute-once-reason-many)".
- **write boundary** - The rule for what may be applied where: the laptop may apply foundational stacks only, never application stacks, which are applied exclusively in CI. Enforced by `.claude/settings.json`, the writable implementer launcher, and the `provision-aws` skill. See DESIGN "[Local vs CI write boundary](../DESIGN.md#local-vs-ci-write-boundary)".

## Observability

- **run record** - The durable, git-ignored local record of a headless run (implementer, panel, or single specialist): its metadata, prompt, output, and - for a panel - the shared artifacts and each reviewer's context. It is local-first because it can hold prompts, plan output, and identifiers this public repo forbids committing. See [`observability.md`](./observability.md) and DESIGN "[Run observability](../DESIGN.md#run-observability)".
