# The Context Budget

Most advice about documentation assumes a human reader who skims, searches, and stops when they have enough.
Agents do not read that way.
An agent loads documentation into a finite context window, reads it literally, and pays for every token whether it needed that token or not.

Once I started treating documentation as something an agent loads rather than something a human browses, a lot of my instincts inverted.
This post is what changed, and the small set of rules that made the docs in this repo cheaper and more reliable to consume, for agents and, it turned out, for humans too.

## TL;DR

- A document has a cost, not just a value. Every token an agent spends reading is one it cannot spend reasoning.
- The same design doc that is a gift to a human is a tax on an agent that only needed the tagging rule.
- Optimize for the shortest path to the exact fact: layer by load time, keep detail local, point instead of repeat, and keep state discoverable.
- Stale documentation is worse than missing documentation, because an agent acts on it.
- Documentation is context engineering. You are curating what lands in a finite window, not filling a reference shelf.

## The setup

This repo is an agentic AWS infrastructure workflow.
Independent agent sessions plan work, author Terraform, review it, and open pull requests, and a lot of what they do is read the repo's own documentation to figure out how to behave.

The docs were good.
A thorough design document, a crisp always-loaded rules file, per-topic references, a troubleshooting log.
By human standards it was in great shape.

Then I looked at it as an agent does.

## The realization: a document has a cost

A human opening a 270-line design document skims to the section they want and ignores the rest.
The cost of the other 250 lines is roughly zero.

An agent cannot do that.
When a task says "read the design document," the whole thing enters the context window, and now those 250 unrelated lines are sitting in working memory, spending budget, crowding out the plan and the diff the agent actually needs to reason about.

So the same document has two completely different cost profiles.
For the human it is a convenience with a table of contents.
For the agent it is a bill, paid in full, every time.

That reframing is the whole post.
Once a document has a cost and not only a value, you stop asking "is this useful to have written down" and start asking "is this the cheapest way for the agent that needs this one fact to get it."

## The moves

### Layer by load time

Not every document should be loaded at the same time, so split them by when they are needed.

There is exactly one always-loaded file, and it holds only the guardrails that bind every agent on every task.
Everything else, the role procedures, the infrastructure skill, the directory conventions, the full design rationale, loads on demand, when a task actually reaches for it.

The always-loaded file is the most expensive real estate in the repo, because every agent pays for it on every run.
So it is kept deliberately small, and the test for adding a line to it is not "is this true" but "does every agent need this on every task."
Almost nothing passes that test.

### Keep the detail local

The biggest single change was moving operational detail out of the central documents and next to the code it governs.

How the scripts work now lives in the scripts directory.
The policy conventions live with the policies.
The stack layout lives with the stacks.
The central design document kept the "why" and handed off the "how" to a pointer.

The payoff is locality of context.
An agent working in the policy directory reads a short, focused document about policy, instead of loading a large slice of the design document and paying for the networking and observability sections it will never use.
The detail did not disappear.
It moved to where the agent that needs it is already standing.

### Point, do not repeat

I used to think duplication was a maintenance problem: two copies drift, and you fix a thing in one place and forget the other.
That is true, but for an agent duplication is also a cost problem.

If the same fact is stated in three documents, an agent that reads all three pays for it three times, and if the three copies have drifted even slightly, it now has to reconcile them.
So each fact gets one authoritative home, and everything else points to it.
A pointer is a few tokens.
A restatement is the whole passage, again, plus the risk that it is now subtly wrong.

When I cleaned up the design document, most of the edits were not deletions of content.
They were replacements of a paragraph with a sentence and a link.

### Separate the why from the how

A related split: keep rationale and implementation detail in different documents, because they are needed by different tasks and they rot on different schedules.

The design document explains why the review panel precomputes its tool output once and hands it to reasoning-only reviewers.
The exact tool allowlist, the environment variables, the command flags, those live with the launcher and the skill.
An agent trying to understand the shape of the system does not want the flags.
An agent about to run the thing does not want the essay.
Giving each its own home means neither task pays for the other's content, and the implementation detail can change without editing the design.

### Keep the state discoverable

A cold agent cannot read the previous agent's memory.
If "where are we" lives only in one session's context, every run reconstructs it, differently.

So the current state of the build lives in a file in the repo, next to the design and the CI contract.
Any agent, from any toolchain, orients the same way, because it reads the same file.
This is the cheapest possible form of handoff: not a conversation, not a summary passed between sessions, just a document that is always true and always in the same place.

### Remove interpretation, not just length

Cutting tokens is not the only goal.
A short document that is ambiguous is still expensive, because the agent spends reasoning on the ambiguity and may resolve it differently than the last run did.

So alongside the trimming, the highest-value additions are the ones that remove interpretation: a glossary that fixes the vocabulary, a naming formula with exactly one output, a task-to-document map that routes an agent to the minimal set it needs.
These do not just make the docs shorter.
They make the space of reasonable readings narrower, which is what consistency across runs actually requires.

## Stale docs are a special kind of expensive

There is one failure mode that is worse for agents than for humans.

A human who reads "this is still to be built" about a thing that clearly already exists shrugs and moves on, because they can see the contradiction.
An agent tends to believe the document.
It will act on the stale statement, re-do finished work, or verify something that needs no verifying, and it will spend real budget doing it.

So an out-of-date document is not a neutral debt that you pay down later.
It is an active cost, and a source of wrong actions, every time it is read.
For an agent-consumed repo, "keep it true" is not tidiness.
It is correctness.

## The meta-principle

Everything above is one idea wearing different clothes.

You are not writing for a reader who skims and stops.
You are allocating a finite budget for a reader who loads, in full, and pays for all of it.

So the job is not "write down everything worth knowing."
The job is to arrange what is worth knowing so that the agent that needs one fact reaches it by the shortest path, pays for as little else as possible, and never has to guess or reconcile two versions on the way.
That is context engineering, and documentation is one of its main levers.

There is the same happy side effect the rest of this workshop has.
Every move that makes the docs cheaper for an agent, layering by load time, keeping detail local, pointing instead of repeating, keeping state discoverable, also makes them better for a human.
Progressive disclosure and a single source of truth were good documentation practice long before agents read on a budget.
The agents just make the cost of ignoring them impossible to hide.

## Coda

I started this thinking I was tidying up some documentation.
What I was actually doing was deciding, fact by fact, what an agent should have to pay to learn each thing, and arranging the repo so the answer was "as little as possible."
The docs got shorter in the middle and richer at the edges, and the whole thing got easier to reason about.
Write for the reader who loads, not the reader who skims, and the budget takes care of itself.
