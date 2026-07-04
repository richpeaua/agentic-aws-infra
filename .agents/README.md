# Local agent run store

This directory holds observability records for headless multi-agent runs launched by
`scripts/implement.sh`, `scripts/review.sh`, and `scripts/agent.sh`.

## Do not commit run artifacts

`.agents/runs/` is git-ignored on purpose and must stay that way.

Run records under `.agents/runs/<run-id>/` can contain **sensitive context**:

- raw prompts and issue/context text (`prompt.txt`),
- full agent stdout and stderr (`stdout.txt`, `stderr.txt`),
- review-panel shared artifacts (`artifacts/`) including Terraform plan output,
- account IDs, bucket names, role ARNs, or emails that appear in tool output.

This repository is **public**. Never add, force-add, or commit anything under `.agents/runs/`.
Only scrubbed, bounded summaries are ever sent to GitHub (issue/PR comments); the detailed
artifacts stay here, local and ignored.

## Inspecting runs

Use the local viewer instead of reading these files by hand:

```sh
scripts/runs.sh list                 # active and recent parent runs
scripts/runs.sh list --children      # include review-panel reviewer child runs
scripts/runs.sh list --json          # machine-readable
scripts/runs.sh show <run-id>        # metadata + artifact paths for one run
scripts/runs.sh clean --older-than 30d
```

See `docs/observability.md` for the full operator workflow.
