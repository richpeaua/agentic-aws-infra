# The Review Panel

What do you get by adding a panel of AI reviewers to a pipeline that already has automated security, compliance, and cost gates?

I expected the answer to be "a bit of redundancy and some nicer explanations."
The actual answer, on the very first run, was: the panel found a hole in one of the automated gates that the gate itself could not report.

This post is about a shift-left multi-agent review panel for infrastructure code, why it earns its place next to deterministic gates rather than duplicating them, and the moment it justified itself.

## The setup

The workflow is a GitOps pipeline for AWS infrastructure.
An implementer agent authors Terraform, opens a pull request, and CI runs a stack of gates: tflint, Checkov for security, Conftest/OPA for our own compliance policies, and Infracost for cost.
A human merges, and CI applies the change to dev then prod through the pipeline.
That is already a lot of automated checking.

So why add agents that review the same code?

## Deterministic gates are necessary but not sufficient

A scanner is a pattern matcher.
It is fast, consistent, and cheap, and you absolutely want it in the loop.
But it only knows the checks it ships with, it cannot reason about intent, and it cannot tell you about its own blind spots.

- It cannot say "this bucket is public, and here is the blast radius if that assumption is ever wrong."
- It cannot say "these four resources are individually fine but the architecture around them is fragile."
- It cannot say "the waiver you wrote covers the wrong resource."
- And critically, it cannot say "by the way, I am not actually enforcing what you think I am enforcing."

Those are all reasoning tasks, and reasoning is what a language model is for.

## The panel

The design is four read-only reviewer subagents, each mirroring one CI gate and adding the judgment the scanner lacks:

- Security, mirroring Checkov, plus threat modeling and blast-radius analysis.
- Compliance, mirroring Conftest, checking our own tag, naming, region, and structure rules.
- Cost, mirroring Infracost, plus right-sizing and "what could grow unbounded" judgment.
- Correctness, mirroring tflint, plus idempotency, state design, and module-interface review.

Three design choices make this work rather than turn into noise.

First, each reviewer is scoped to exactly one concern.
No overlap, no four agents all commenting on the same public bucket.

Second, each reviewer is read-only.
It can read the code and run the real analysis tools, but it cannot edit files or apply anything.
That means the reviewers can run in parallel without fighting over the same files, and the author stays the single writer.

Third, every reviewer emits the same structured shape: findings with a severity, a file-and-line anchor, a concrete fix, and a one-line verdict.
Consistency across runs is not a hope, it is a format.
Two runs of the same review produce the same shape, so the output is scannable and the implementer can synthesize it mechanically.

The panel runs before the PR is opened.
Problems get caught and fixed while the change is still a draft, and CI stays a backstop rather than the first line of defense.
This is what "shift left" actually means in practice: move the finding to the cheapest place to fix it.

## The moment it paid off

The first real run was a demo: point the panel at a static-site module that had already passed every CI gate.
I expected four green verdicts and some pleasant prose.

The compliance, cost, and correctness reviewers did roughly that, with a few genuinely useful minor findings (a missing input validation that would let a typo silently mis-name resources, a missing lifecycle rule, some duplicated literals).

Then the security reviewer said something the scanner never could.

It observed that our Checkov gate was configured to hard-fail on HIGH and CRITICAL findings and treat everything else as advisory.
But open-source Checkov, without a platform API key, does not reliably attach severity metadata to its findings.
If nothing is labeled HIGH, then a rule that says "block on HIGH" blocks nothing.
The gate could be passing security findings it was explicitly designed to stop, and every green check mark would look exactly the same as a real pass.

This trap is now documented where it is actionable: [`policy/README.md`](../policy/README.md#checkov-checkov) states the block-on-any-finding rule, and [`docs/troubleshooting.md`](../docs/troubleshooting.md#checkov-gate-does-not-block-a-clearly-bad-resource) records the fix.

That is a latent hole in a security control, discovered by reading the control's configuration and reasoning about what it would actually do, not by running it.
A scanner cannot find that class of bug, because the scanner is the thing with the bug.
It took a reviewer whose job is to think about security, not just execute security checks.

## The lesson

The instinct is to see a review panel as redundant once you have automated gates.
The opposite is true.
Deterministic gates and reasoning reviewers fail in different ways, so they cover for each other.

- The gate catches the thing the model forgets to look for.
- The model catches the thing the gate cannot express, including the gate's own misconfiguration.

You want both, aimed at the same code, from different angles.
The gate is your floor.
The panel is the thing that notices the floor has a gap in it.

And there is a bonus that matters for any team, human or agent: because each reviewer has a fixed rubric and a fixed output format, the review is consistent no matter who or what triggered it.
The panel is not just a quality check.
It is a quality check that produces the same shape of answer every time, which is the only kind of check you can actually build a process around.

## Coda

I added the panel expecting nicer comments.
I got a security audit of my security gate, for free, on the first run.
The takeaway is not "agents are better than scanners."
It is that "correct" and "reasoned about" are different properties, and mature infrastructure wants both.
