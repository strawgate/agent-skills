---
name: bug-hunt
description: Evidence-driven bug hunting. Reproduce one real user-impacting bug with a minimal artifact and write structured findings.
argument-hint: "[optional: target area, recent change, subsystem, workflow, or bug class]"
allowed-tools: Read Grep Glob Bash Agent WebSearch WebFetch Edit Write
---

# Bug Hunt

Default mode: find one real, reproducible, user-impacting bug. Most normal runs should end with one strong finding or `noop`, not a pile of weak suspicions.

If the user explicitly asks for a broad sweep, fan-out, backlog, or quota such as "find 30 bugs", switch to sweep mode:
- keep the same evidence bar per bug
- write many separate candidate markdown files
- do not stop after the first strong hit
- let the verifier or orchestrator rank and promote later

This skill is intentionally generic. It does not assume a language, framework, build tool, test runner, or hosting platform. Repo-specific rules belong in repo-local instructions layered on top of this skill.

## Quality Bar

A valid bug is something a real user or operator could plausibly hit:
- wrong output
- silent data loss or corruption
- accepted invalid configuration or input that should be rejected
- crash, hang, deadlock, livelock, or stuck retry loop
- resource leak, unbounded growth, or broken recovery path
- incorrect permission, auth, or state-transition behavior

Not valid by default:
- style nits
- vague "this looks suspicious"
- a failure from an existing test suite you did not author for this run
- repo-specific conventions you have not verified against the surrounding design
- extremely contrived inputs unless the user explicitly wants adversarial/security fuzzing

## Default Output Layout

Create a run directory before hunting. Prefer a repo-local temp path so multiple agents can coordinate through files:

```text
tmp/bug-hunt/YYYY-MM-DD-brief-name/
  claims/                  # optional; mainly for parallel runs
  candidates/
    <slug>.md
  verified/
    critical/
      <slug>.md
    high/
      <slug>.md
    medium/
      <slug>.md
    low/
      <slug>.md
```

If the repo cannot safely hold scratch data, use `/tmp/<repo>-bug-hunt-...`.

The markdown file is the primary artifact.
- Put the reproduction, evidence, command transcript, and analysis directly in the markdown when practical.
- If you need an extra file, place it next to the markdown using the same slug, for example `candidates/<slug>.txt` or `verified/high/<slug>.json`.
- Do not create a deep artifact tree unless the user explicitly wants it.

Treat these states differently:
- `claims/` means "someone is actively looking here"
- `candidates/` means "possible bug, not yet verified strongly enough"
- `verified/` means "reproduced, deduped, and assigned a final severity by the verifier or orchestrator"

## Multi-Agent Coordination

When multiple agents are bug hunting:

1. Inspect the run directory first.
   Read existing `claims/`, `candidates/`, and `verified/` files before starting.
2. Claim a narrow slice before digging in.
   Good slices: a subsystem, recent commit range, API surface, config path, failure mode, or user workflow.
3. Record your claim in a dedicated file.
   Include:
   - owner
   - focus area
   - commits/files being inspected
   - status: `active`, `abandoned`, `confirmed`, or `noop`
4. Search for duplicates before escalating.
   Check:
   - existing result files in the run directory
   - open issues
   - recently closed issues / merged PRs for the same symptom
5. One bug per markdown file.
   Do not mix several weak ideas into one report.
6. Prefer "pick three, keep one".
   If you are orchestrating multiple agents, give each a distinct angle and only escalate the strongest confirmed finding.
7. Let the parent agent consolidate.
   Sub-agents should usually write or report one best finding plus any downgraded candidates. The parent agent should deduplicate and decide what gets promoted.

In sweep mode, replace "pick three, keep one" with:
- cover the assigned slice broadly
- write every distinct candidate that clears the minimum evidence bar
- stop only when the slice is exhausted, time-boxed, or the quota is met
- leave ranking and promotion to the parent agent

If agents cannot safely share a filesystem in your environment, emulate the same flow by having the parent agent own the directory and mirror sub-agent claims/results into it.

## Standard Hunt Loop

### 1. Orient

- Identify the repository, target branch, and current branch.
- Prefer hunting on the latest default branch unless the user explicitly asks for another target.
- If your current checkout is stale, dirty, or tied to unrelated branch work, use an isolated worktree or equivalent clean checkout for the hunt.
- Read the local contribution or architecture guidance relevant to the target area.
- Review recent user-facing changes.
  A good default is the last 2-6 weeks of commits, PRs, or release notes.
- Build a short list of candidate bug surfaces from recent change hotspots, high-complexity areas, and behavior with real user impact.
- Build a lightweight issue cache up front.
  Prefer one initial snapshot of:
  - open issues relevant to the assigned slice
  - recent closed issues / merged PRs relevant to the assigned slice
  Save or summarize that cache in the run directory if multiple agents are coordinating.
  Do not hit the issue tracker from scratch for every single candidate when a cached slice-local list would do.

### 2. Dedup

Before investing deeply in a candidate:
- check the cached open issues for the symptom
- check the cached closed issues / merged PRs for the same behavior
- check the run directory for overlapping claims or findings

If the behavior is already tracked or already fixed on the target branch, do not report it as a new bug by default.

Default policy:
- exact match or same root cause as an existing issue/PR: skip it
- likely same family but not clearly distinct: downgrade confidence or leave as a note
- only keep it when you can explain what is materially new

Examples of materially new evidence:
- current-main confirmation on an old issue
- a much smaller or more deterministic reproduction
- a narrowed root cause
- a stronger severity/impact demonstration
- proof that the previous fix did not fully address the problem

### 3. Form a Concrete Hypothesis

Good hypothesis:
- names the behavior
- names the trigger
- predicts the impact
- suggests a minimal reproduction path

Example shape:
- "When X receives Y after Z, it incorrectly does A instead of B, causing C."

### 4. Reproduce It Yourself

This is mandatory.

Write a new minimal artifact for this run:
- a focused script
- a tiny fixture
- a minimal test
- a single API/CLI invocation sequence
- a small workflow or config snippet

The reproduction must be authored for this hunt, not borrowed from an existing failing suite.

Capture:
- exact commands
- exact inputs
- stdout/stderr
- exit code or observed behavior
- any required environment assumptions

Put the reproduction directly in the markdown when possible. If a sidecar file is needed, place it next to the markdown with the same slug.

If you cannot get to a direct reproduction, do not write a verified finding. Write a `candidates/<short-name>.md` note instead with the missing step or uncertainty.

### 5. Confirm Impact

State:
- who is affected
- what breaks
- whether the bug is deterministic
- whether data is wrong, lost, duplicated, or stuck
- whether the behavior is a regression, and if so, from what change

### 6. Write the Candidate or Verified Finding

Hunters should usually start by writing `candidates/<short-name>.md`.

In sweep mode:
- write one markdown file per bug candidate
- keep going until you exhaust the slice or hit the requested quota
- avoid bundling multiple bugs into one report just to save time
- skip already-known issues unless you have materially new evidence

The verifier or orchestrator should promote strong findings into one of:
- `verified/critical/<short-name>.md`
- `verified/high/<short-name>.md`
- `verified/medium/<short-name>.md`
- `verified/low/<short-name>.md`

Use this structure:

```md
# <short bug title>

## Summary
One paragraph: trigger, behavior, impact.

## Slice
What area or claim this came from.

## Dedup Check
- Open issues searched:
- Closed issues / merged PRs searched:
- Existing hunt files checked:
- Search keywords used:

## Reproduction
1. ...
2. ...

## Expected
...

## Actual
...

## Evidence
- Inline transcript or sidecar file path(s):
- Key command output:
- Relevant code references:

## Severity
Proposed user impact. Final severity is assigned by the verifier or orchestrator.

## Next Step
`issue`, `fix`, `test-only`, or `noop`
```

### 7. Promote, Downgrade, or Noop

Promote to `verified/` only if the bug clears the quality bar, was reproduced directly, and has been deduped.

Prefer this split of responsibilities:
- hunter: writes or updates `candidates/<slug>.md`
- verifier/orchestrator: confirms, assigns severity, and promotes to `verified/<severity>/<slug>.md`

Choose `noop` if:
- you could not reproduce it
- the impact is weak or speculative
- it is already tracked
- it is already fixed
- it only surfaced through unrelated existing test failures

## What To Look For

Good generic hunting angles:
- validation gaps between "accepted" and "supported"
- state-machine transitions after partial failure or restart
- behavior at boundaries: empty, huge, missing, duplicate, reordered, interrupted, partially written
- disagreement between docs, schema, builder, runtime, and outputs
- retry, shutdown, checkpoint, recovery, or flush paths that drop or duplicate work
- coercions or sanitization that silently turn bad input into plausible-looking output

## Escalation Rule

If the user asks you to file issues or prepare fixes:
- verify first
- dedup second
- only then escalate

Do not turn a candidate into a GitHub issue or code change until it has crossed the evidence bar.
