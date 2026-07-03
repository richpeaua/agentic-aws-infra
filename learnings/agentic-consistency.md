# Agentic Consistency

How do you get an AI agent to build cloud infrastructure the same careful way every single time, across dozens of independent runs, with different context each time?

That turned out to be the real problem.
Not "can an agent write Terraform" (it can), but "will a hundred agent runs produce work that is consistent enough to trust."
This post is what I learned building an agentic AWS infrastructure workflow, and the small set of techniques that moved it from "impressive demo" to "something I would actually let touch an account."

## TL;DR

- One good agent run is easy. Consistency across many runs is the hard part.
- Prose rules do not create consistency, because prose gets interpreted, and every interpretation is a place two runs diverge.
- Consistency comes from removing choices: shared scripts, scaffolders, checklists, formulas, and discoverable state.
- The guiding move: turn "how should I do this?" into "run this" or "copy this" or "check this box."

## The setup

The project started small: an agent that authors Terraform from a natural-language request, plans it, shows the cost, and applies it after approval.
That worked end to end on the first try.
A static site went live, the loop closed, everyone clapped.

Then we matured it into something production-shaped.
Version control, a public repo, GitOps with CI applying through OpenID Connect instead of laptop credentials, a stack of quality and security and compliance gates, a multi-agent review panel, and dev and prod environments.
Each of those is its own decision, and each one multiplies the number of ways a future agent run could quietly do the wrong thing.

## The real problem: the second run

The first agent run has all the context.
It just made the decisions, so it remembers why the bucket is named that way and which directory the state key points at.

The second run does not.
A fresh agent, or a different agent framework entirely, picks up a task with none of that context.
It re-derives everything, and it re-derives it slightly differently.
One run puts the environment in the resource name, the next run forgets.
One run pins the module version, the next uses latest.
One run remembers that the state key must not change when a stack moves, the next orphans the state and proposes recreating live infrastructure.

None of these are model-capability failures.
They are consistency failures, and they compound.

## Why prose rules fail

My first instinct was to write better rules.
A crisp `AGENTS.md` with the operating procedure, the conventions, the golden rule.

Prose helps, but it has a ceiling.
Prose is interpreted, and interpretation is exactly where runs diverge.
"Include the environment in resource names" reads as obvious to a human and as three different naming schemes to three agent runs.
"Run the checks before opening a PR" invites each run to choose its own set of checks.

The rule was not wrong.
It just left too many degrees of freedom, and every degree of freedom is a coin flip that resolves differently across runs.

## The fix: remove the choices

The shift that worked was to stop describing the work and start constraining it.
Every place an agent has to decide how to do something is a place to replace judgment with a script, a template, or a checklist.

### One command surface

Instead of prose listing the commands to run, there is a `scripts/` directory that both local work and CI invoke.
`scripts/check.sh` runs formatting, validation, linting, and the scanners.
`scripts/plan.sh` initializes against remote state and produces a plan and a cost estimate.
`scripts/new-stack.sh` scaffolds a new stack.
`scripts/scan-secrets.sh` fails if a forbidden identifier is staged.

Now every run executes identical steps, because they are the same file.
And because CI calls the same scripts, "green locally" reliably predicts "green in CI."
The parity is structural, not aspirational.

I deliberately used portable bash rather than a Makefile, because `make` behaves differently across macOS and Linux, and the whole point was to remove surprises.

### Scaffold, do not describe

The highest-leverage change was a stack template plus a generator.
`scripts/new-stack.sh <name>` renders a reusable module and thin dev and prod roots from one canonical template, pre-wired with the backend, the tags, and the naming.

"Follow the layout conventions" is an invitation to vary.
"Run the scaffolder" produces the same structure every time.
Copying a known-good shape is far more consistent than reconstructing it from rules, and it collapses an entire category of divergence to zero.

### A definition of done

Consistency is not only about how work starts.
It is about agreeing when work is finished.

So there is an explicit Definition of Done, encoded as a checklist in the pull request template.
Plan is clean and a re-plan is a no-op.
Secret scan passed.
Review findings resolved.
Tags present, environment in names, versions pinned.
No local apply of an application stack.

Two agents that check the same boxes converge on the same bar, even if they took different paths to get there.

### Name things by formula

Ambiguous naming guarantees inconsistent naming.
So the scheme is a formula: base every name on `project-stack-environment`, and for globally-unique names append the account ID sourced from the current caller identity, never hardcoded.

A formula has one output.
"Make it unique somehow" has as many outputs as there are runs.

### Make the state of the world discoverable

A cold agent cannot read the previous agent's memory.
If "where are we" lives only in one session's context, every run reconstructs it differently.

So the current state lives in the repo, in a status document, next to the design and the CI contract.
Any agent, including one from a different toolchain entirely, orients the same way because it reads the same file.

### Write down the gotchas once

Every failure we hit the hard way became an entry in a troubleshooting document.
OpenID Connect trust conditions scoped to the wrong subject.
The cost tool that quietly changed its command and now requires an organization.
The provider lock file generated for one platform breaking CI on another.
The backend state key that must not change when a directory moves.

Left undocumented, each of these is rediscovered, and rediscovered differently.
Written down, they are handled the same way every time.

## The meta-principle

Everything above is one idea wearing different clothes.

Consistency is not something you ask an agent for.
It is something you engineer into the environment the agent works in, by removing the choices that would otherwise be made inconsistently.

A capable model plus a high-variance environment produces high-variance work.
The same model plus a low-variance environment, full of scripts and templates and checklists and discoverable state, produces consistent work.
You are not making the agent smarter.
You are making the space of "reasonable next actions" narrow enough that any reasonable agent lands in the same place.

There is a nice side effect.
Every constraint that makes an agent more consistent also makes a human contributor more consistent.
A scaffolder, a checklist, and a shared script surface are just good engineering hygiene that happens to be exactly what agents need.

## What I would tell someone starting

Do not invest first in a longer rules document.
Invest in the artifacts that remove interpretation.

Ask, for each thing an agent must decide: can this be a script instead of an instruction, a template instead of a description, a checklist instead of a judgment, a formula instead of a guideline, a file instead of a memory.
Every "yes" is one fewer coin flip.

Write the rules too.
But treat prose as the layer of last resort, for the genuinely judgment-bound decisions that cannot be mechanized, and mechanize everything else.

## Coda

The demo was the easy part.
The engineering was making the hundredth run look like the first.
It turns out that is less about prompting and more about building a workshop where it is hard to do the wrong thing and easy to do the right one, then letting the agent work in it.
