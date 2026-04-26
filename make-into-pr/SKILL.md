---
name: make-into-pr
description: Turn a local change into a high-confidence PR by doing a rigorous self-review, tightening tests/docs/benchmarks, creating the PR, and then following it until merge-ready or merged.
argument-hint: [optional owner/repo, branch/base, or PR title hints]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, Agent
---

# Make Into PR

Use this skill when a local change should be turned into a polished pull request with strong evidence, good organization, and a post-push follow-through loop.

This skill is intentionally opinionated: do not treat "make a PR" as "commit current diff and push it". The default is to raise the bar before opening the PR.

## Goal

For the current worktree:
1. Understand the full diff and intended user-facing outcome.
2. Perform an in-depth self-review like a strong external reviewer would.
3. Improve organization, naming, docs, tests, and benchmark evidence until the change is genuinely PR-ready.
4. Create the PR with a clear description and validation summary.
5. Immediately transition into [$follow-the-pr](/Users/billeaston/.Codex/skills/follow-the-pr/SKILL.md) and keep looping on feedback, CI, and review until the PR is merged or explicitly paused.

## Review Standard

Treat the change like a serious code review, not a formatting pass. Review for:
- correctness and behavioral regressions
- missing edge cases and invariants
- API and abstraction quality
- operational cost: CPU, memory, I/O, latency, allocations
- test quality and missing coverage
- documentation quality and discoverability
- rollout and maintenance risk

A good mental model is: "What would a skeptical maintainer or high-signal bot reviewer call out on this PR?"

## Phase 1: Understand the Diff

Start by collecting:
- `git status --short`
- `git diff --stat`
- `git diff` on the touched files
- if useful, `git diff --name-only` grouped by change area

Then summarize for yourself:
- what the change is trying to accomplish
- which files are core implementation vs tests/docs/benchmarks
- what the likely risky surfaces are

Do not open a PR yet.

## Phase 2: Deep Self-Review

Review the diff as if you were a strict reviewer.

### Checklist

- Is the implementation shape the right one, or merely the first one that worked?
- Is the public API too broad, too narrow, or prematurely generic?
- Is there hidden coupling to internals that should be documented or isolated?
- Are there any O(n), O(n*m), or full-scan paths that should be scoped better?
- Are failure modes explicit and testable?
- Are invariants documented where a future maintainer would need them?
- Are tests covering the behavior that is actually easy to break?
- If performance matters, do benchmarks prove the win on realistic workloads?
- Does the change introduce technical debt that should be paid before PR time?

### Findings-first mindset

Prefer real findings over summaries. If something is weak, fix it now unless it would derail the main goal.

## Phase 3: Tighten the Change

Based on the self-review, improve the diff before PR creation.

Typical upgrades:
- simplify or clarify the implementation structure
- remove premature abstraction or add missing structure
- add missing tests
- add benchmark scripts or comparison data when performance is part of the claim
- document architectural decisions and non-goals
- improve PR-facing developer docs
- rename things that will confuse reviewers later

Be willing to make additional commits worth of change if they materially improve PR quality.

## Phase 4: Validation

Validation should match the nature of the change.

Minimum expectation:
- format/lint on touched files
- focused tests for changed behavior
- if performance or storage efficiency is part of the claim, benchmark it

Prefer:
- before/after comparisons
- targeted regression tests for the tricky edge cases you found in review
- one concise validation summary you can reuse in the PR body

If some validation could not be run, say so explicitly in the PR body.

## Phase 5: Prepare the PR

Before creating the PR, make sure you can explain:
- the problem
- the chosen design
- why this organization is right for now
- what evidence supports the change
- what remains intentionally out of scope

Then:
- create/switch to the correct branch
- stage the intended files only
- commit intentionally
- push
- open the PR (draft or ready, depending on confidence and project norms)

### PR body quality bar

The PR body should usually include:
- short problem statement
- concise change summary
- validation / benchmark results
- design notes or non-goals when relevant
- any caveats that reviewers should know

## Phase 6: Review the Actual PR

Once the PR exists, review the PR artifact too, not just the code.

If a PR review MCP or equivalent tooling is available, use it now on the actual PR.
For local-only situations, do another pass over the PR diff and body exactly as reviewers will see them.

Look for:
- unclear title/body
- missing benchmark context
- confusing organization of commits/files
- reviewer questions you can pre-answer in the PR description

Fix and update the PR before moving on.

## Phase 7: Follow Through Until Merge

After the PR is up, immediately switch into [$follow-the-pr](/Users/billeaston/.Codex/skills/follow-the-pr/SKILL.md).

That means:
- watch for CI changes
- watch for review comments and unresolved threads
- fix actionable feedback
- rerun validation as needed
- push updates
- resume follow mode
- continue until the PR is merged, closed, or explicitly paused by the user

Do not treat "PR opened" as the finish line.

## Rules

- Do not open a PR before the self-review pass is done.
- Do not hide weak spots; either fix them or call them out explicitly.
- Do not over-generalize the design just because future flexibility is imaginable.
- Do not merge without explicit user permission.
- After opening the PR, default to continuing with `follow-the-pr` until merge readiness or merge.

## Deliverable Standard

A successful run of this skill produces:
- a stronger local diff than the one it started with
- good tests/docs/benchmarks for the actual claim
- a well-written PR
- an active follow-through loop after opening the PR
