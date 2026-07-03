# Build status

Single in-repo source of truth for where the build is.
Update this when a phase completes or the deployed footprint changes.
Detailed phase specs are the GitHub issues (epic: #8).

## Phases

- [x] Phase 1 - Repo and scrub (DESIGN v2, README, LICENSE, AGENTS.md).
- [x] Phase 2 - Foundation: `foundation/state-backend` and `foundation/github-oidc` applied (OIDC provider + read/dev-apply/prod-apply roles).
- [x] Phase 3 - GitHub configuration: `dev` and `production` environments, variables, role-ARN secrets, branch protection. Owner still to set `INFRACOST_API_KEY`.
- [ ] Phase 4 - PR gates + policy (#3): `pr-checks.yml`, tflint, Checkov, Conftest, Infracost.
- [ ] Phase 5 - Agent review panel + skill rewrite (#4). SKILL.md already reconciled to v2; panel subagents in `.claude/agents/` still to add.
- [ ] Phase 6 - Refactor static-site into module + dev/prod roots (#5).
- [ ] Phase 7 - Deploy pipeline + end-to-end validation (#6).
- [ ] Phase 8 - QA layer: smoke tests, terraform test, drift (#7).

## Deployed footprint

- `foundation/state-backend` - S3 state bucket + monthly AWS Budget.
- `foundation/github-oidc` - OIDC provider + three IAM roles.
- `stacks/static-site` - v1 flat layout, one public S3 site, applied from laptop in v1. Pending refactor (Phase 6) and re-provision through the pipeline (Phase 7).

## Tooling in the repo

- `scripts/` - the command surface: `preflight`, `new-stack`, `check`, `plan`, `scan-secrets`. Local and CI call these.
- `templates/stack/` - canonical stack template used by `scripts/new-stack.sh`.
