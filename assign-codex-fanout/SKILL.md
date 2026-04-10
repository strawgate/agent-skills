---
name: assign-codex-fanout
description: Split a large repo task into workstreams, create prompt files, and launch one Codex Cloud task per workstream with multiple attempts. Use for research fanout, implementation fanout, prototyping, audits, or benchmark investigations.
argument-hint: [topic or execution goal e.g. "library adoption", "benchmark 3 serializer paths", "prototype OTAP shared types"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# Assign Codex Fanout

Run a Codex Cloud fanout for `$ARGUMENTS`.

## What this skill does

1. Frames the overall task.
2. Splits it into 3-5 parallel workstreams.
3. Writes one prompt file per workstream.
4. Launches one Codex Cloud task per prompt file with `--attempts N`.
5. Produces a manifest for later collection and synthesis.

This skill is intentionally generic:

- use it for research
- use it for implementation/prototyping
- use it for audits, benchmarks, migrations, or design exploration

The point is not merely to "ask more questions in parallel."
The point is to delegate real principal-engineer-grade investigation and execution while
you remain the final integrator and decision-maker.

Treat Codex Cloud agents as capable of:

- reading and understanding the repo deeply
- searching the web and primary docs when external context matters
- running tests, benchmarks, and focused experiments
- editing code and docs when the workstream calls for it
- comparing multiple viable approaches instead of stopping at the first plausible one
- producing repo-local artifacts that make fan-in easier

The real leverage comes from best-of-N:

- launch `2x` or `3x` when the problem is important enough to benefit from independent reasoning
- ask for grounded recommendations and alternatives, not just a single answer
- preserve enough structure in the prompt that different attempts can diverge productively without drifting off-mission

## Scripts

- [Launch cloud fanout](./scripts/launch-cloud-fanout.py)

## Default strategy

- one cloud task per workstream
- choose attempt count by importance, not by habit
- prompts stored in the repo
- use the current branch only if you have confirmed the cloud environment can resolve it
- otherwise prefer the repo default branch and restate the branch-specific diff in the prompt

Recommended attempt scaling:

- `4x` only for the most important architecture forks or high-stakes implementation bets
- `3x` for important but narrower workstreams
- `2x` for medium-value or confirmatory work
- `1x` for speculative or "crazy idea" investigations

When deciding whether to use `2x` or `3x`, prefer asking:

- Do I want independent takes on the same hard decision?
- Would I benefit from seeing different implementation shapes or research instincts?
- Is the fan-in step likely to choose the best attempt rather than average them?

If yes, fan out more aggressively.

## Workflow

### 1. Frame the main task

Write down:

- the decision or execution goal
- the repo constraints
- what each workstream should deliver
- how the outputs will be compared later
- whether the workstream should optimize for:
  - decisive recommendation
  - executable prototype
  - benchmark-backed comparison
  - architecture proposal
  - implementation plus tests

Before writing prompts, decide what "good disagreement" would look like.
If you want multiple attempts to explore the same problem, make that explicit:

- ask for the best recommendation
- ask for plausible alternatives
- ask what evidence would change the recommendation
- ask the agent to surface risks and tradeoffs rather than converging too early

### 2. Create workstreams

Prefer 3-5 workstreams that are meaningfully distinct.

Good fanout categories:

- subsystem slices
- competing implementation options
- benchmark variants
- audit tracks
- protocol / storage / control-plane splits

### 3. Write prompt files

Create one prompt file per workstream. Use `templates/task-workstream-prompt.md`.

Prompts can request:

- research memos
- code prototypes
- tests
- benchmark harnesses
- docs
- migration plans

Write prompts as delegations to a strong principal engineer, not as a fragile ticket.
The agent should understand both:

- what it must accomplish
- how much initiative it is expected to use

Good prompts usually tell the cloud agent:

- it has full permission to investigate broadly inside the repo
- it may use web/docs/benchmarks/tests when they improve the answer
- it should compare multiple credible approaches when the problem is design-heavy
- it should leave behind concrete artifacts that make the final fan-in easier
- it should not stop at surface-level summary if code inspection or experimentation is warranted
- it should keep working until the remaining new findings are likely low-value noise rather than high-signal repo debt

### 3a. Make prompts self-contained

Treat every cloud prompt as if the agent can see **only**:

- the committed repo
- the branch or ref you explicitly launched against
- the prompt text

and **cannot reliably see**:

- your local artifact bundle
- uncommitted docs
- local diffs from previous cloud tasks
- your current local git diff, unless you paste or summarize it directly in the prompt
- hidden session/thread context from earlier cloud tasks
- your non-default PR branch, unless you have explicitly verified it exists and resolves in cloud
- local files that are not committed on the launched branch, even if they exist in your checkout

Reality model to enforce in every important fanout:

- if you launch against `main`, assume the cloud agent sees `main` and the prompt text, and nothing else
- if you want the cloud agent to use a rubric, prior memo, issue rewrite, or branch-specific context, either commit it on the launched branch or paste the relevant content directly into the prompt
- links are not sufficient continuity on their own; restate the actual conclusions or requirements in the prompt itself
- when in doubt, inline more context, not less

Therefore, the prompt itself should include:

- the specific direction you want explored
- a short summary of any prior result that matters
- a short but concrete summary of the branch-specific code changes when launching against default branch instead of the PR branch
- if a local diff matters, the canonical diff context itself:
  - `git diff --stat` summary
  - exact changed-file list
  - commit list when helpful
  - raw or excerpted patch hunks for the specific files you want reviewed
- links or task IDs only as references, not as the sole source of context
- a hard `Required execution checklist` when precision matters
- what not to do
- what success looks like
- the exact deliverable path
- minimum investigation depth when quality matters, for example:
  - `Spend at least 10 minutes doing real investigation before finalizing unless tooling blocks you.`
  - `Do not stop once you have one plausible finding; continue until the remaining new items are likely low-value noise.`
- a confidence rule when the task is an audit, for example:
  - `Only promote a finding when confidence is roughly 0.7 or higher.`
  - `Downgrade lower-confidence items to watch items instead of mixing them with main findings.`
- the degree of autonomy you expect:
  - recommendation only
  - investigate + prototype
  - investigate + implement + test
  - benchmark and compare alternatives

Also include the operating assumptions you want the agent to follow, for example:

- `You are expected to investigate like a principal engineer, not merely summarize obvious files.`
- `Use the repo, tests, docs, benchmarks, and web research as needed to produce a grounded result.`
- `Do not stop at the first plausible idea if the problem has meaningful design space.`
- `If two approaches are credible, compare them and explain why you chose one.`
- `If a quick prototype, benchmark, or targeted code change would sharpen the recommendation, do it.`
- `If the prompt includes a canonical diff section, treat that diff as the source of truth even if you cannot see the branch in cloud.`
- `Assume you only have the committed repo on the launched branch plus this prompt text.`
- `Keep investigating until the only newly discovered items are likely throwaway noise, duplicates, or low-confidence suspicions.`
- `Use confidence thresholds so the final output favors signal over volume.`

If this is a follow-up wave, restate the prior prototype or research conclusion in plain language inside the prompt.
When the work is benchmark-sensitive, it is often worth being blunt:

- say `You MUST do A, B, and C`
- list exact benchmark files/commands to touch
- require a recommendation label
- then add a separate line inviting the agent to use judgment for adjacent exploration after the required work is complete

When prior cloud work matters, prefer creating a repo-local summary input first:

- write a short local memo or brief that captures the prior conclusion
- point the new prompt at that local file
- do not rely on task URLs alone for continuity

When a **local diff** matters, do not rely on a repo-local file that only exists on your branch unless you have verified the cloud task can see that branch.
Prefer one of these:

- paste the important diff directly into the prompt
- paste a tightly scoped patch excerpt for the exact files/functions under review
- include `git diff --stat`, `git diff --name-only`, and the relevant hunks inline

If the question depends on "what changed on my branch?", the prompt must answer that question itself.

If the task depends on a shared rubric, checklist, or policy note, do **not**
just point at a local path and assume cloud can read it. Either:

- commit that file on the launched branch first, or
- paste the rubric/checklist into the prompt itself

For design-heavy or architecture-heavy work, the prompt should usually ask for all of:

- a primary recommendation
- at least one alternative
- tradeoffs and failure modes
- exact files/modules likely to change
- a suggested sequencing plan
- what evidence would change the recommendation

This helps best-of-N fanout produce different high-quality attempts you can actually compare.

### 3b. Prefer default-branch launches when cloud branch visibility is uncertain

Codex Cloud may fail to resolve a non-default branch even when it exists locally or was recently pushed.
If you see task startup failures like `base ref does not exist` or `no diff`, treat that as a branch-resolution failure.

In that case:

- launch against the repo default branch (for this repo, `main`)
- inline the branch-specific context into the prompt itself
- include:
  - the intended branch name
  - the exact files or subsystems changed
  - the important behavior changes and edge cases under discussion
  - the precise question you want the cloud agent to answer
  - if diff accuracy matters, the exact patch or hunk excerpts you want reviewed

Do not assume the cloud task can reconstruct a PR branch from the task URL or your local checkout.

### 4. Launch Codex Cloud

Use:

```bash
python3 "${HOME}/.agents/skills/assign-codex-fanout/scripts/launch-cloud-fanout.py" \
  --prompt-dir <dir-with-prompts> \
  --attempts 4
```

For mixed-fanout waves, override individual prompts:

```bash
python3 "${HOME}/.agents/skills/assign-codex-fanout/scripts/launch-cloud-fanout.py" \
  --prompt-dir <dir-with-prompts> \
  --attempts 2 \
  --prompt-attempt <prompt-a>.prompt.md=4 \
  --prompt-attempt <prompt-b>.prompt.md=1
```

Important rule:

- if the user wants "4 agents on the same problem", use one task with `--attempts 4`
- do not create 4 separate tasks unless they explicitly want separate task threads
- for mixed-value waves, launch prompts individually with different `--attempts` counts rather than forcing every workstream to the same fanout level
- if a non-default branch matters, verify it exists remotely first; otherwise use the default branch and a self-contained prompt
- for audit fanouts, prefer over-specifying the prompt rather than assuming cloud can discover local context

### 5. Save the manifest

The launch script writes a manifest with:

- prompt files
- branch
- cloud environment
- task IDs
- task URLs

That manifest is the handoff input for `$assign-codex-fanin`.

## Practical rules

- keep prompts specific and repo-grounded
- prefer one concrete deliverable per workstream
- if the workstream is implementation-oriented, define the write scope clearly
- for implementation workstreams, explicitly require: working change + meaningful coverage increase + self-review pass before return
- if the workstream is hot-path-sensitive, require benchmark evidence in the prompt
- if benchmark evidence is the point of the task, separate `required evidence` from `optional exploration`
- for benchmark work, require the agent to say whether the result is `directional` or `decision-grade`
- for benchmark work, require the agent to say what evidence would change its mind
- if the workstream is research-only, ask for a decisive recommendation instead of a vague survey
- explicitly summarize prior findings when doing follow-up work; do not assume cloud tasks share memory
- if the task depends on an unmerged PR branch, treat the prompt as the canonical handoff and restate the diff context directly
- if the task depends on a local diff, assume the cloud agent has **zero** diff visibility unless you inline it
- include the architectural tension you want resolved, not just the topic name
- say what should remain custom, what may use libraries, and what evidence would change your mind
- use `1x` deliberately for speculative bets where breadth matters less than simply getting one thoughtful pass
- when the question is important, prefer `2x` or `3x` and plan to choose the best attempt during fan-in
- write prompts that invite real investigation, not timid compliance
- if the best answer may require code, tests, benchmarks, or web research, say so explicitly instead of implying the agent should stay read-only
- when code is expected, ask the agent to report both what it implemented and what additional verification depth it added
- prefer asking for a recommendation plus supporting evidence over asking for an undifferentiated survey
- ask for repo-local output files so the useful work survives beyond the task transcript

## Example

```bash
python3 "${HOME}/.agents/skills/assign-codex-fanout/scripts/launch-cloud-fanout.py" \
  --cwd /path/to/repo \
  --prompt-dir dev-docs/research/fanout-2026-04-05 \
  --pattern '*.prompt.md' \
  --attempts 4
```

Then hand the resulting manifest to `$assign-codex-fanin`.
