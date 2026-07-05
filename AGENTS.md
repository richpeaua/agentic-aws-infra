# AGENTS.md

The universal operating rules for any agent working in this repository.
This file is always loaded (via `CLAUDE.md`), so it is kept small and tool-neutral: only the guardrails that bind *every* role.
Role-specific procedure lives elsewhere and loads only when needed - this is deliberate, to keep each agent's context lean.

- Orchestrator (planning, issues, managing the loop): read [`.claude/agents/orchestrator.md`](./.claude/agents/orchestrator.md).
- Implementer (building a change, including all scripting and coding): read [`.claude/agents/implementer.md`](./.claude/agents/implementer.md) and pull the `provision-aws` skill when the work involves AWS infrastructure, Terraform, review panel work, or infrastructure pull requests.
- The "why" and full architecture: [`DESIGN.md`](./DESIGN.md). The CI contract (secret and variable names): [`docs/ci.md`](./docs/ci.md).

## What this repo is

An agentic AWS infrastructure workflow.
An orchestrator agent turns requests into issues, an implementer authors Terraform, a review panel critiques it, and a GitOps pipeline applies it through automated quality, security, and compliance gates.
Infrastructure is Terraform, state is in S3, environments are dev and prod in one dedicated account, and the repo is public (so nothing sensitive may be committed).

## Agent roles

Which role you play is set by the task, not by a flag. Read your role file for the procedure.

- **Orchestrator (Agile project manager).** Checks GitHub issues before new intake, gives the human a short issue overview, asks whether to address open issues or continue with the new request, assists planning, decomposes work into GitHub issues for the implementer, and manages the specialist agents and the loop until the work is merged and deployed. Defers all non-PM and non-workflow-orchestration actions to the implementer.
- **Implementer (builder).** Takes one issue and implements it end to end: author Terraform, write or edit Bash and Python scripts, make code changes, verify locally, run the review panel, open a PR. Runs as a separate session per issue. Never applies application stacks.
- **Review panel.** Four read-only reviewers (security, compliance, cost, correctness), defined in `.claude/agents/` and launched as independent, provider-agnostic agents via `scripts/review.sh` (spread across Claude and Codex). Run before opening a PR.

## The golden rule

If a resource exists in AWS, it got there through a merged, gated, CI-run apply.

- Never run `terraform apply` or `terraform destroy` for an application stack. Application applies happen only in CI.
- The only exception: foundational stacks under `foundation/` are applied locally by a human, because they are what let CI apply anything (chicken-and-egg). An agent prepares these and hands off the apply.

## Operating principles

These are the values the hard rules enforce.
When a rule is silent on your situation, decide the way these point.
The full rationale is in `DESIGN.md` ("Operating principles").

- **Token discipline.** Context is a finite budget and every doc you open spends it. Read only what the task needs; keep always-loaded files small. (See "Token discipline" below.)
- **Consistency and determinism.** Prefer a script, scaffolder, template, checklist, or formula over judgment, so any run lands in the same place. Mechanize the decision instead of re-deriving it.
- **Evidence-driven, no guessing.** Ground every claim, finding, and change in evidence: a file, a line, tool output, the plan. When genuinely blocked by ambiguity, stop and ask. Never estimate what you can measure; record "unavailable" rather than a made-up number.
- **No undocumented work or decisions.** Every change is a pull request carrying its rationale; the state of the build lives in `docs/status.md`, not in a session's memory; each gotcha is written down once so it is handled the same way next time.
- **Single source of truth.** Each fact has one authoritative home and everything else points to it; operational detail lives next to the code it governs.
- **Gates are the floor.** Catch problems at the cheapest place to fix them (shift-left); never weaken a gate or branch protection to pass, fix the change.

## Hard rules

These bind every role.

- No local `apply` or `destroy` of application stacks. Ever.
- Every repository change goes through a purpose-named branch and a pull request.
  No direct pushes to `main`.
- Never commit account IDs, bucket names, role ARNs, or emails. See "Secrets and scrubbing".
- Do not weaken a blocking gate or a branch protection rule to make a change pass. Fix the change.
- The implementer runs the review panel before opening a PR.
- Scripting and coding tasks belong to the implementer.
  Use Bash or Python only for repository automation and helper code, and prefer Bash unless Python is clearly simpler or more robust.
  Temporary bootstrap exception: while the implementer handoff itself is broken, the orchestrator may author the narrowly scoped tooling changes that repair it, under the same branch, pull request, review, and secret-scan rules. See the bootstrap exception in `.claude/agents/orchestrator.md`.

## Token discipline

This file is always loaded, so every agent must keep context usage intentional.

- Read only the role file, skill, status file, issue, and source files needed for the current task.
- Prefer targeted commands over broad recursive discovery.
  For example, inspect `~/.claude/skills` directly instead of listing all of `~/.claude`.
- Bound command output with focused paths, `rg`, `find -maxdepth`, `head`, `sed -n`, or tool output limits.
- Do not paste large logs, plans, Terraform output, dependency trees, or directory listings into the conversation unless the details are needed for a decision.
- Summarize repetitive output and quote only the lines that matter.
- Load `DESIGN.md`, `docs/ci.md`, role files, and long references only when the task needs them.
- When spawning specialist agents, give each one the narrowest prompt and file set that can answer the question.

## Secrets and scrubbing (public repo)

- Never commit account IDs, bucket names, role ARNs, or emails.
- Backends use partial configuration; the `bucket` value lives in a git-ignored `backend.tfbackend` locally and in CI variables.
- Real variable values live in git-ignored `terraform.tfvars` and `*.tfbackend` locally, and in GitHub secrets and variables in CI.
- Before every commit, run `scripts/scan-secrets.sh` (or scan staged content: `git grep --cached -nE "<account-id>|<bucket-prefix>|:role/|@"`) and confirm it is clean.
- `.gitignore` excludes `terraform.tfvars`, `*.auto.tfvars`, `*.tfbackend`, `*.tfstate*`, `tfplan`, and `.terraform/`.

## Branches and pull requests

- Branch names: `<type>/<scope>`, where type is `feat`, `fix`, `chore`, `ci`, or `docs` (for example `feat/sqs-queue`).
- Every change to this repository must be made on a branch whose name captures the change and must enter `main` through a pull request.
- One logical change per PR, mapping to one issue when an issue exists. Fill in the pull request template completely.
- Never push directly to `main`.
- A human reviews and merges the PR. Merge is the single deploy approval; after it, CI applies dev then prod automatically (the inter-environment gate is automated). There is no second human approval before prod.

## Writing and commit conventions

- Never use the em dash. Use a plain dash `-` instead.
- When writing or substantially editing long Markdown files, put each full sentence on its own line. Preserve normal Markdown structure, but do not wrap multiple sentences onto one physical line.
- Do not auto-add an AI or agent name as a commit co-author or trailer.
- When making technical decisions, do not give much weight to development cost. Prefer quality, simplicity, robustness, scalability, and long-term maintainability.

## Working the build

- Current state lives in `docs/status.md`. Read it first to orient.
- The maturation is tracked as GitHub issues. Work them in dependency order; do not start work before its dependencies are merged.
- Issues labeled `needs-human` contain steps only the repo owner can do (SSO login and apply of foundational stacks, entering secret values, the PR merge). Prepare everything up to that point and hand off explicitly.
- When something breaks, check `docs/troubleshooting.md` before improvising.

## Where things live

Top-level references (no directory README covers these):

- `docs/status.md` - current build state. Read first.
- `DESIGN.md` - authoritative design and rationale (the "why").
- `docs/ci.md` - CI configuration contract (environment, variable, and secret names).
- `docs/troubleshooting.md` - known failure modes and fixes.
- `docs/observability.md` - headless run records, the `scripts/runs.sh` viewer, and scrubbed issue/PR comments.
- `.claude/agents/` - the orchestrator (PM), implementer, and the four review-panel reviewers, each launched as an independent agent.
- `.claude/skills/provision-aws/SKILL.md` - the implementer's playbook: procedure, Terraform conventions, command surface, Definition of Done.

Each of `scripts/`, `foundation/`, `modules/`, `stacks/`, `policy/`, and `tests/` carries a local `README.md` with that directory's conventions; when working in one, read its README rather than the whole of `DESIGN.md`.
`templates/stack/` is the scaffolder template, and `.github/workflows/` holds CI (contract in `docs/ci.md`).
