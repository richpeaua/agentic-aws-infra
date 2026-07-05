# Contributing

*Audience: making a change to this repository - the short version of how work flows.*

This repository is operated by agents and a human owner under one set of rules.
The authoritative, always-loaded workflow lives in [`AGENTS.md`](./AGENTS.md); read it before contributing. In brief:

- Every change goes on a `<type>/<scope>` branch (`feat`, `fix`, `chore`, `ci`, or `docs`) and enters `main` through a pull request. Never push to `main`.
- One logical change per PR, mapped to one issue where an issue exists. Fill in the PR template completely.
- Before committing, run `scripts/scan-secrets.sh`; never commit account IDs, bucket names, role ARNs, or emails (this repo is public).
- Infrastructure is authored as Terraform and reviewed by the local review panel before the PR; CI runs the gates and performs all applies. No one applies application stacks locally.
- A human reviews and merges. Merge is the single deploy approval.

For the "why" behind these rules, see [`DESIGN.md`](./DESIGN.md).
For where to start on a given task, use the task-routing table in [`AGENTS.md`](./AGENTS.md).
