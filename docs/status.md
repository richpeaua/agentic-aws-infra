# Build status

Single in-repo source of truth for where the build is.
Update this when a phase completes or the deployed footprint changes.
Detailed phase specs are the GitHub issues (epic: #8).

## Phases

- [x] Phase 1 - Repo and scrub (DESIGN v2, README, LICENSE, AGENTS.md).
- [x] Phase 2 - Foundation: `foundation/state-backend` and `foundation/github-oidc` applied (OIDC provider + read/dev-apply/prod-apply roles).
- [x] Phase 3 - GitHub configuration: `dev` and `production` environments, variables, role-ARN secrets, branch protection. `INFRACOST_API_KEY` set.
- [x] Phase 4 - PR gates + policy (#3): `pr-checks.yml` (policy-tests, discover, static, plan, gate), tflint, Checkov, Conftest + rego unit tests, Infracost. `gate` is the required status check on `main`. Gates are scoped to changed stacks.
- [ ] Phase 5 - Agent review panel + skill rewrite (#4). SKILL.md already reconciled to v2; panel subagents in `.claude/agents/` still to add.
- [x] Phase 6 - Refactor static-site into module + dev/prod roots (#5). Merged #10. Old v1 demo destroyed. First stack validated through the full gate pipeline (surfaced and fixed the read-role + native-lockfile issue via `-lock=false`).
- [x] Phase 7 - Deploy pipeline + end-to-end validation (#6). `deploy.yml` applies dev -> smoke -> production gate (human approval) -> prod -> smoke. Validated: dev and prod static-site both deployed through CI and live (HTTP 200).
- [ ] Phase 8 - QA layer: smoke tests, terraform test, drift (#7).

## Deployed footprint

- `foundation/state-backend` - S3 state bucket + monthly AWS Budget.
- `foundation/github-oidc` - OIDC provider + three IAM roles.
- `stacks/static-site` - `modules/static-site` + `dev`/`prod` roots. Both environments deployed through the pipeline (Phase 7) and live. Buckets `aws-agentic-infra-static-site-{dev,prod}-<account>`.

## Tooling in the repo

- `scripts/` - the command surface: `preflight`, `new-stack`, `check`, `plan`, `scan-secrets`. Local and CI call these.
- `templates/stack/` - canonical stack template used by `scripts/new-stack.sh`.
