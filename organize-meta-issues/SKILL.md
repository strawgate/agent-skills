---
name: organize-meta-issues
description: Plan and maintain bite-size meta issues and phased issue trees for bugs, features, and refactors. Use when the user says "organize meta issues", "issue planner", "plan metas", "bite-size metas", "group issues", "phase this work", "maintain issue structure", or "organize issues for copilot".
argument-hint: "[owner/repo and optional scope e.g. 'strawgate/memagent', 'strawgate/memagent bugs only', 'strawgate/memagent refactors']"
user-invocable: true
disable-model-invocation: false
---

# Issue Planner

Create and maintain a two-level issue structure that works for both humans and coding agents:

- Visitors can still find a specific bug or feature request as a normal issue.
- Copilot can be assigned a parent meta/phase issue that bundles a coherent block of mostly mechanical work.
- Features and refactors are broken into phases with assignable child issues instead of one oversized umbrella ticket.

Use this skill after an audit or when the repo's issue tree has become messy.

## Scripts

- [Fetch repo issue/PR data](./scripts/fetch-repo-data.sh)
- [Summarize existing meta structure](./scripts/summarize-meta-structure.sh)

## Step 0: Determine Repo and Scope

If `$ARGUMENTS` contains an `owner/repo` pattern, use that. Otherwise detect from the current git repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If neither works, ask the user.

Parse any remaining words in `$ARGUMENTS` as scope hints, such as:

- `bugs only`
- `features`
- `refactors`
- `config`
- `tailing`
- `docs`

## Step 1: Read Repo Docs First

Read the repo docs before planning issue structure. This prevents grouping work that looks similar but belongs to different architectural layers.

Read these if they exist:

- `README.md`
- `DEVELOPING.md` / `CONTRIBUTING.md`
- `CLAUDE.md` / `AGENTS.md`
- `docs/ARCHITECTURE.md` or any architecture doc
- `ROADMAP.md`
- `docs/**/*.md`
- `dev-docs/**/*.md`

If a prior audit exists, read it too.

## Step 2: Fetch GitHub Data

Run the data fetch script to collect the issue and PR inventory:

```bash
./scripts/fetch-repo-data.sh OWNER/REPO
```

This writes a timestamped directory under `/tmp/issue-organizer/OWNER__REPO/` containing:

- `open-issues.json`
- `open-prs.json`
- `merged-prs.json`
- `closed-prs.json`
- `labels.json`
- `repo.json`
- `summary.txt`

## Step 3: Map Existing Metas and Orphans

Run the structure summary script:

```bash
./scripts/summarize-meta-structure.sh OWNER/REPO
```

This writes:

- `meta-issues.json` — issues that already look like parent metas/phases/epics
- `child-links.tsv` — parent/child references extracted from issue bodies
- `orphan-open-issues.json` — open non-meta issues not linked from any parent
- `meta-summary.md` — readable inventory of the current structure

Read `meta-summary.md` before proposing changes.

## Step 4: Decide the Right Planning Shape

Choose the smallest structure that fits the work.

### A. Bite-size bug meta

Use for 3-8 related bugs when:

- They are in one subsystem or adjacent files
- The fix pattern is similar across issues
- The work is mostly mechanical or bounded
- One agent could plausibly handle the batch in one focused pass

Good examples:

- several diagnostics handler bugs in one file
- several docs/runtime mismatch bugs across the same docs set
- several config validation bugs in one config loader

Avoid bundling together:

- unrelated root causes across different layers
- one P0 architecture bug plus seven cosmetic cleanups
- work that requires broad product/design decisions

### B. Feature/refactor phase meta

Use when the work is too large for one bug meta but still needs structure.

Break it into phases when:

- order matters
- later work depends on earlier API or crate boundaries
- some issues are prerequisites, not peers
- the whole effort would be too much autonomy for a single agent

Typical shape:

1. Epic or umbrella issue: overall problem, goals, phases
2. Phase meta issues: each phase is an assignable block of work
3. Leaf issues: concrete visitor-facing bugs/features/tasks under each phase

Do not go deeper than this unless the repo already has a strong reason to do so.

## Step 5: Apply the Bite-size Test

Before creating or revising any meta, score the candidate bundle against these rules.

Include an issue in the same meta only if most answers are yes:

1. Same subsystem or tightly adjacent subsystem?
2. Same validation style and test surface?
3. Same likely owner or reviewer?
4. Similar risk level?
5. Similar fix shape?
6. Low ambiguity, low product/design discretion?
7. Reasonable to land in one PR or one short series?

If not, split it.

## Step 6: Produce the Planning Output

Your output should be operational, not just descriptive.

Use a richer structure in chat than in the final GitHub issue body. The planner output can include rationale and grouping analysis; the final issue should keep only the durable information humans and agents need later.

### Required sections

#### Proposed new metas/phases

For each proposed parent issue, provide:

- title
- type: `meta` or `phase` or `epic`
- why these issues belong together
- child issue list
- why this is safe to assign to Copilot
- acceptance criteria

#### Existing metas to revise

Call out current metas that are:

- too broad
- too shallow
- mixing unrelated work
- missing child issues
- duplicating another parent

#### Orphans to attach

List open issues that should be attached to an existing parent or grouped into a new one.

#### Issues to split apart

If an existing meta is too big or too fuzzy, propose a replacement structure.

## Step 7: Use Standard Body Templates

These are **final issue body** templates, not required chat output formats. Keep them compact.

### Template: Bite-size bug meta

```markdown
meta: <subsystem> — <short grouped theme>

## Overview

<One short paragraph on the shared failure mode and affected area.>

## Included issues

| # | Priority | Issue |
|---|----------|-------|
| #123 | P1 | ... |
| #124 | P2 | ... |

## Why together

<One short paragraph on the shared code area, fix pattern, or test surface.>

## Done when

- [ ] <child 1 done>
- [ ] <child 2 done>
- [ ] regression tests cover the affected paths
```

### Template: Epic with phases

```markdown
epic: <bigger initiative>

## Problem

<Why the current state is bad.>

## Outcome

<What success looks like.>

## Phases

- [ ] #201 — Phase A: ...
- [ ] #202 — Phase B: ...
- [ ] #203 — Phase C: ...

## Notes

<Only include this section if there are real dependencies, sequencing constraints, or design-doc links worth preserving.>
```

### Template: Assignable phase meta

```markdown
phase: <initiative> — <phase name>

## Scope

<What this phase does and does not include.>

## Included issues

| # | Type | Issue |
|---|------|-------|
| #301 | refactor | ... |
| #302 | bug | ... |

## Why together

<Shared prerequisite or code boundary.>

## Done when

- [ ] API / crate boundary / behavior target completed
- [ ] tests updated
- [ ] follow-on phases unblocked
```

## Step 8: Maintenance Rules

When maintaining an existing issue tree:

- Keep leaf issues visitor-friendly and searchable
- Keep meta titles short and scannable
- Put the grouping rationale in the parent body, not only in your chat reply
- Cross-link parent and children both ways when possible
- Prefer adding a new child issue over bloating a parent description
- Close or narrow stale parents when the child list no longer matches reality
- If a parent has more than about 8 children, consider splitting it
- If a parent mixes bugs, refactors, and research, split by work type unless one is clearly prerequisite to the others

## Step 9: Present Ready-to-Run Commands

After proposing the structure, provide `gh` commands for the user to run or review.

Examples:

```bash
gh issue create --repo OWNER/REPO --title "meta: diagnostics API accuracy — double-counting, undocumented routes, method enforcement" --body-file /tmp/meta-diagnostics.md --label bug --label copilot

gh issue edit 772 --repo OWNER/REPO --body-file /tmp/meta-772-updated.md

gh issue comment 712 --repo OWNER/REPO --body "Tracked under #772"
```

Do not create or edit GitHub issues automatically unless the user explicitly asks.

## Guidelines

- Audit first, then plan. Don't invent parent issues before reading the existing structure.
- Favor bounded execution over thematic purity. A slightly imperfect grouping is acceptable if it creates a safe, assignable batch.
- Keep Copilot metas low-discretion. If success depends on novel architecture decisions, keep that work outside the batch or make it its own design issue.
- For bug metas, prefer common failure mode over common label.
- For feature/refactor planning, prefer dependency boundaries over superficial similarity.
- When in doubt, split large metas into phases and keep each phase concrete.