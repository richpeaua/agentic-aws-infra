# Reviewer output contract

The shared output shape for every reviewer in the review panel (`security`, `compliance`, `cost`, `correctness`).
It is defined once here so the format has a single source of truth: each reviewer file references it, and `scripts/agent.sh` inlines this file into every `*-reviewer` rubric at launch (the same way the implementer's skill is inlined), so a reviewer on either provider always receives it.
`scripts/review.sh` parses the `VERDICT:` line this contract mandates, so keep its wording exact.

## Evidence (all reviewers)

Ground every finding in evidence: a `file:line` anchor, or a specific line of the tool output you were handed.
Reasoning-only does not mean speculation - do not raise a finding you cannot point at.

## Findings (all reviewers)

List findings most severe first, one per line, in this shape:

- **[severity]** `path:line` - one-sentence issue. Fix: concrete remediation.

If there is nothing to report, say so in one line (for example "No security issues found.") before the verdict.

## Severity ladder (security, compliance, correctness)

Highest first:

- `blocker` - must be fixed before the PR. Each reviewer sharpens what this means for its dimension (a serious security hole; a hard-policy violation; a change that breaks apply or idempotency).
- `high` - should be fixed before merge.
- `medium` / `low` - improvements, not merge-blocking.
- `nit` - trivial or stylistic.

## Verdict (required last line)

End with exactly one line beginning `VERDICT:`.
It is mandatory: `scripts/review.sh` fails the panel for any reviewer whose output has no `VERDICT:` line.

Blocking reviewers (security, compliance, correctness):

- `VERDICT: PASS` when there is no `blocker` or `high` finding.
- `VERDICT: CHANGES NEEDED (<n> blocker/high)` when there is. The literal phrase `CHANGES NEEDED` is what fails the panel, so use it only when the change must not merge as-is.

## Cost is advisory (cost reviewer only)

Cost never blocks the panel, so it uses its own scale and verdict:

- Lead with `Estimated monthly cost: $X` (plus the delta for a change to existing infra).
- Findings use impact levels `high` / `medium` / `low`, and frame the fix as `Suggestion:` (a cheaper or leaner alternative and the rough saving).
- End with `VERDICT: OK`, or `VERDICT: REVIEW COST (<reason>)` when spend deserves a second look. Never emit `CHANGES NEEDED` - that is what keeps cost advisory.
