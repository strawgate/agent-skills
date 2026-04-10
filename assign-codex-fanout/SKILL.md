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

## Scripts

- [Launch cloud fanout](./scripts/launch-cloud-fanout.py)

## Default strategy

- one cloud task per workstream
- choose attempt count by importance, not by habit
- prompts stored in the repo
- current branch used unless explicitly overridden

Recommended attempt scaling:

- `4x` only for the most important architecture forks or high-stakes implementation bets
- `3x` for important but narrower workstreams
- `2x` for medium-value or confirmatory work
- `1x` for speculative or "crazy idea" investigations

## Workflow

### 1. Frame the main task

Write down:

- the decision or execution goal
- the repo constraints
- what each workstream should deliver
- how the outputs will be compared later

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

### 3a. Make prompts self-contained

Treat every cloud prompt as if the agent can see:

- the committed repo
- the current branch
- the prompt text

and **cannot reliably see**:

- your local artifact bundle
- uncommitted docs
- local diffs from previous cloud tasks
- hidden session/thread context from earlier cloud tasks

Therefore, the prompt itself should include:

- the specific direction you want explored
- a short summary of any prior result that matters
- links or task IDs only as references, not as the sole source of context
- a hard `Required execution checklist` when precision matters
- what not to do
- what success looks like
- the exact deliverable path

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

### 4. Launch Codex Cloud

Use:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/launch-cloud-fanout.py \
  --prompt-dir <dir-with-prompts> \
  --attempts 4
```

For mixed-fanout waves, override individual prompts:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/launch-cloud-fanout.py \
  --prompt-dir <dir-with-prompts> \
  --attempts 2 \
  --prompt-attempt <prompt-a>.prompt.md=4 \
  --prompt-attempt <prompt-b>.prompt.md=1
```

Important rule:

- if the user wants "4 agents on the same problem", use one task with `--attempts 4`
- do not create 4 separate tasks unless they explicitly want separate task threads
- for mixed-value waves, launch prompts individually with different `--attempts` counts rather than forcing every workstream to the same fanout level

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
- if the workstream is hot-path-sensitive, require benchmark evidence in the prompt
- if benchmark evidence is the point of the task, separate `required evidence` from `optional exploration`
- for benchmark work, require the agent to say whether the result is `directional` or `decision-grade`
- for benchmark work, require the agent to say what evidence would change its mind
- if the workstream is research-only, ask for a decisive recommendation instead of a vague survey
- explicitly summarize prior findings when doing follow-up work; do not assume cloud tasks share memory
- include the architectural tension you want resolved, not just the topic name
- say what should remain custom, what may use libraries, and what evidence would change your mind
- use `1x` deliberately for speculative bets where breadth matters less than simply getting one thoughtful pass

## Example

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/launch-cloud-fanout.py \
  --cwd /path/to/repo \
  --prompt-dir dev-docs/research/fanout-2026-04-05 \
  --pattern '*.prompt.md' \
  --attempts 4
```

Then hand the resulting manifest to `$assign-codex-fanin`.
