---
name: assign-codex-fanin
description: Collect Codex Cloud task outputs from a fanout run, inspect per-attempt diffs and extracted artifacts, and synthesize the results into one recommendation or integration plan. Use after assign-codex-fanout or whenever you already have cloud task IDs to consolidate.
argument-hint: [manifest path or consolidation goal e.g. "fanout-manifest.json", "synthesize cloud results for OTLP migration"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# Assign Codex Fanin

Collect and consolidate Codex Cloud outputs for `$ARGUMENTS`.

## What this skill does

1. Reads a fanout manifest or a list of task IDs.
2. Downloads task status, final diffs, and per-attempt diffs.
3. Extracts created-file contents where possible, including from successful attempts when a final diff is not available yet.
4. Compares convergence, disagreements, and alternate ideas.
5. Produces one synthesis or integration memo.

This skill is intentionally generic:

- use it after research fanout
- use it after implementation fanout
- use it to compare multiple prototype branches or docs

## Scripts

- [Collect cloud artifacts](./scripts/collect-cloud-artifacts.py)
- [Wait until a wave is ready for fan-in](./scripts/wait-for-fanin.py)

## Workflow

### 1. Gather the manifest

Prefer the manifest created by `$assign-codex-fanout`.

Use:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/collect-cloud-artifacts.py \
  <manifest.json>
```

This creates an artifact bundle with:

- `status.txt`
- `final.diff.txt`
- `attempt-N.diff.txt`
- extracted created files where the diff contains a new file
- extracted attempt-created files when the task is still pending but one or more attempts already finished
- `artifact-index.json`

When the fanout manifest includes `remote_branch` / `remote_head`, treat that as
the cloud-visible source of truth rather than the current local branch tip.

If you expect the wave to keep running for a while and want to avoid premature
“fan in?” checks, use:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/wait-for-fanin.py \
  <manifest.json>
```

Readiness modes:

- `--mode partial`: wake up once every task has either a final diff or at least
  one successful attempt diff
- `--mode full`: wake up only once every task has a task-level final diff

The waiter re-runs artifact collection on each poll, refreshes
`artifact-index.json`, and exits once the selected readiness threshold is met.

### 2. Inspect convergence

For each workstream, answer:

- what most attempts agree on
- where attempts disagree
- whether the selected final attempt is actually the best one for this repo
- what ideas appeared only in non-selected attempts
- whether a pending task already has enough successful attempts to use in synthesis

### 2a. Use partial results when they are good enough

Do not block a whole fan-in on one slow or stuck task if:

- the task is still pending
- one or more attempt diffs are already available
- those attempts already answer the question well enough

In those cases:

- synthesize with the available attempt outputs
- say explicitly that the task-level final diff was not available yet
- record the confidence impact, if any

### 3. Cross-check with the repo

Do not synthesize cloud outputs in isolation. Compare them against:

- current source files
- architecture docs
- verification constraints
- tests
- benchmark harnesses

Use the manifest's `remote_branch` / `remote_head` when present to reason about
what the cloud actually saw. Do not silently assume the current local branch tip
matches the launched branch state.

### 4. Produce one synthesis

Use `templates/synthesis-outline.md`.

Depending on the task, the synthesis can be:

- an architectural direction memo
- an implementation integration plan
- a ranked prototype comparison
- an adopt / benchmark / reject matrix

## Practical rules

- inspect attempt diffs, not just final diffs, when the quality bar matters
- use the best available evidence, not only task-level finals
- prefer the waiter script when a wave is still running, instead of repeatedly
  treating placeholder `no diff` bundles as if they were meaningful evidence
- do not average the attempts blindly; fit the synthesis to the repo’s real constraints
- preserve strong reasons to keep custom code when the repo has hot-path or proof boundaries
- for implementation fanin, call out merge conflicts, overlapping write scopes, and missing tests
- for benchmark fanin, call out whether the evidence is `directional` or `decision-grade`
- for benchmark fanin, note when a result depends on a still-pending task with partial attempts only

## Example

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/collect-cloud-artifacts.py \
  dev-docs/research/fanout-2026-04-05/fanout-manifest.json
```

Then read the generated artifact index and write the synthesis memo.
