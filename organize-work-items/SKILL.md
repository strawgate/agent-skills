---
name: organize-work-items
description: "Create and maintain work-unit issues: opinionated scheduling metas labeled work-unit that bundle low-discretion, low-conflict repo-local work for one agent run. Use when the user says organize work items, work unit, work-unit, scheduling issue, assignable batch, by-reference meta, or agent-sized batch."
argument-hint: "[owner/repo and optional scope e.g. 'strawgate/memagent', 'strawgate/memagent elasticsearch', 'strawgate/memagent pipeline.rs']"
user-invocable: true
disable-model-invocation: false
---

# Work Unit Planner

Create and maintain a scheduling layer on top of the normal issue tree.

This skill is intentionally opinionated.

Use it when the repo already has visitor-facing bug/feature/refactor issues and maybe some metas/phases, but you also want a separate set of assignable tickets that are optimized for one coding-agent run.

## The Model

Keep these issue types separate:

- **Leaf issues**: the user-visible bug reports, feature requests, docs fixes, refactors, and research items that visitors search for.
- **Meta / phase / epic issues**: conceptual organization of product or architecture work.
- **Work units**: scheduling tickets labeled `work-unit` that point at related issues by reference and define a bounded, low-conflict batch for one agent run.

Work units are not the source of truth for product intent. They are a scheduling layer.

That means:

- visitors still find the original bug/feature issue
- phases still describe initiative sequencing
- work units say "this specific block should be done together because it is merge-safe and repo-local"

## Scripts

- [Fetch repo issue/PR data](./scripts/fetch-repo-data.sh)
- [Summarize existing meta structure](./scripts/summarize-meta-structure.sh)
- [Summarize existing work-unit structure](./scripts/summarize-work-unit-structure.sh)

## Step 0: Determine Repo and Scope

If `$ARGUMENTS` contains an `owner/repo` pattern, use that. Otherwise detect from the current git repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If neither works, ask the user.

Parse remaining words in `$ARGUMENTS` as scope hints, such as:

- `pipeline`
- `elasticsearch`
- `docs`
- `phase 5`
- `config`
- `tailing`

## Step 1: Read the Repo Before Scheduling Work

Read the repo docs before you group work. Grouping by label alone produces bad work units.

Read these files if they exist:

- `README.md`
- `DEVELOPING.md` / `CONTRIBUTING.md`
- `CLAUDE.md` / `AGENTS.md`
- `docs/ARCHITECTURE.md` or any architecture doc
- `ROADMAP.md`
- `docs/**/*.md`
- `dev-docs/**/*.md`

If an issue audit or planning doc exists, read it first. Prefer prior audit output over re-inventing the repo structure from scratch.

## Step 2: Reuse Existing Planning Data

Run the shared data fetch and summary scripts:

```bash
./scripts/fetch-repo-data.sh OWNER/REPO
./scripts/summarize-meta-structure.sh OWNER/REPO
./scripts/summarize-work-unit-structure.sh OWNER/REPO
```

This gives you:

- open issue inventory
- open and merged PR inventory
- existing metas / phases / epics
- existing work units
- orphan issues not linked from a work unit yet
- grep-friendly title indexes and one-file-per-record dumps for issues and PRs

Read these outputs before proposing any changes:

- `/tmp/issue-organizer/OWNER__REPO/summary.txt`
- `/tmp/issue-organizer/OWNER__REPO/meta-summary.md`
- `/tmp/issue-organizer/OWNER__REPO/work-unit-summary.md`
- `/tmp/issue-organizer/OWNER__REPO/issue-titles.txt`
- `/tmp/issue-organizer/OWNER__REPO/pr-titles.txt`
- `/tmp/issue-organizer/OWNER__REPO/issues/open/*.txt`
- `/tmp/issue-organizer/OWNER__REPO/prs/open/*.txt`
- `/tmp/issue-organizer/OWNER__REPO/prs/merged/*.txt`
- `/tmp/issue-organizer/OWNER__REPO/prs/closed/*.txt`

Start with the title indexes to shortlist candidates, then grep the per-record
files when you need to cluster by subsystem, wording, or linked work.

## Step 3: Apply the Work-Unit Lens

Unlike normal meta planning, work units are optimized for execution, not taxonomy.

Primary optimization target:

**Accomplish as much work as possible with as little repo footprint and merge-conflict risk as possible.**

That means you are allowed to group together:

- several bugs in the same sink or subsystem
- a phase slice plus an adjacent bug if they touch the same file cluster
- docs fixes plus tiny code alignment changes in the same area
- several feature requests that are all part of the same narrow implementation seam

That also means you should split apart work that is thematically related but operationally bad to batch together.

Examples:

- Split one large file-input redesign into separate work units if one piece is parser behavior and another is checkpoint storage.
- Do not batch two architecture decisions together just because both are labeled `refactor`.
- Do not mix a repo-wide lint migration with a local correctness fix unless the exact same files are being touched anyway.

## Step 4: What Belongs in a Work Unit

A candidate belongs in the same work unit only if most answers are yes:

1. Same file cluster, crate, package, or subsystem?
2. Same likely reviewer or maintainer context?
3. Same test surface?
4. Similar risk level?
5. Similar fix shape or implementation pattern?
6. Low product/design discretion?
7. Low chance of colliding with another active work unit?
8. Plausibly completable in one agent run and one focused PR or PR stack?

Target shape:

- roughly 3-8 related leaf issues, or
- one narrow slice of a phase, or
- one file-cluster batch with mixed issue types

Good work units usually touch one of these shapes:

- one top-level crate/package
- one hot file plus its tests
- one API surface and its docs
- one migration slice with explicit non-goals

## Step 5: What Does NOT Belong in a Work Unit

Do not create a work unit when the work requires high discretion.

Keep these out unless the user explicitly wants a design-heavy batch:

- unresolved architecture choices
- research spikes
- cross-cutting repo-wide cleanups
- big prerequisite refactors with unclear stop points
- items whose success criteria are still debated
- anything likely to trigger conflicts across several active branches

Those should stay as normal issues, epics, or design tasks until they can be sliced more narrowly.

## Step 6: Distinguish Work Units from Metas and Phases

Use this decision rule:

- If the issue exists to explain the problem space, it is a `meta`, `phase`, or `epic`.
- If the issue exists to schedule one merge-safe agent run, it is a `work-unit`.

Work units can point to:

- leaf issues
- phase issues
- meta issues

But they should only reference the exact slice being scheduled now.

Do not duplicate the whole parent issue body into the work unit. Link by reference and restate only the scoped batch.

## Step 7: Produce Opinionated Output

Your output must be operational.

Use a richer structure in chat than in the final GitHub issue body. The planning output should justify the grouping. The final work-item issue should stay compact and execution-oriented.

### Required sections

#### Proposed work units

For each proposed work unit, provide:

- title
- why this is one agent run
- repo footprint
- linked issues
- linked metas/phases if any
- why it is low-discretion
- why it is merge-safe relative to neighboring work
- exit criteria

#### Existing work units to revise

Call out work units that are:

- too broad
- too abstract
- overlapping another work unit
- missing the actual leaf issues
- stale because the referenced work already landed
- fighting the repo shape by spanning too many subsystems

#### Issues or phases that still need a work unit

List important work that is currently unscheduled even though it is now batchable.

#### Items that should stay out of work units

Explicitly identify design-heavy or cross-cutting work that should remain as normal issues or phases.

## Step 8: Use the Standard Work-Unit Template

This is the **final issue body** template. Keep it compact and biased toward execution.

```markdown
work-unit: <subsystem> — <batch name>

## Purpose

<What this batch accomplishes and why these items should land together.>

## Repo footprint

- `path/to/file_or_dir`
- `path/to/tests`
- `path/to/docs`

## In scope

| # | Type | Why included |
|---|------|--------------|
| #123 | bug | same handler and tests |
| #124 | docs | same API surface |

## Related metas / phases

<Only include this section if the work item is slicing an existing meta or phase.>

## Non-goals

- <things intentionally excluded to keep the batch safe>

## Done when

- [ ] listed issues resolved or updated
- [ ] regression tests added or updated
- [ ] docs and implementation aligned for this slice
- [ ] follow-on work, if any, linked explicitly
```

## Step 9: Maintenance Rules

When maintaining work-unit structure:

- Each open leaf issue should usually belong to zero or one open work unit.
- Allow multiple work-unit references only when one is an umbrella phase scheduler and the body clearly explains the boundary.
- If a work unit grows past about 8 leaf issues, split it.
- If a work unit spans more than 2-3 adjacent top-level areas, split it.
- If a work unit body does not mention repo footprint, tighten it.
- If a work unit has no explicit non-goals, it is probably too fuzzy.
- If a referenced issue is closed, remove it from the work unit or close the work unit.
- If a phase issue is too large for one agent run, create multiple work units that reference different slices of that phase.
- Prefer revising a stale work unit over creating a near-duplicate.

## Step 10: Naming and Labeling Rules

Use the `work-unit` label on all work units.

Title format:

```text
work-unit: <repo area> — <execution-oriented batch name>
```

Good titles:

- `work-unit: elasticsearch sink — small correctness and retry fixes`
- `work-unit: pipeline.rs — phase 5c cleanup plus begin_batch bug`
- `work-unit: docs/config — 10 runtime-alignment fixes`

Bad titles:

- `meta: polish`
- `work-unit: miscellaneous`
- `phase 5c and some other stuff`

Prefer repo-area-first titles because the point is scheduling by footprint, not storytelling.

## Step 11: Present Ready-to-Run Commands

Provide commands, but do not create or edit issues unless the user explicitly asks.

Examples:

```bash
gh issue create --repo OWNER/REPO \
  --title "work-unit: diagnostics.rs — counter fixes and route enforcement" \
  --label work-unit \
  --label copilot \
  --body-file /tmp/work-unit-diagnostics.md

gh issue edit 123 --repo OWNER/REPO --body-file /tmp/work-unit-123-updated.md

gh issue comment 712 --repo OWNER/REPO --body "Scheduled in work unit #123."
```

## Guidelines

- Audit first, schedule second.
- Optimize for merge-safe repo footprint before thematic purity.
- Prefer by-reference work units over duplicating issue content.
- Use metas/phases for explanation and sequencing; use work units for execution.
- It is acceptable for a work unit to mix bug, docs, feature, and refactor items if the code footprint is the same and the discretion level is low.
- It is not acceptable for a work unit to become a second epic.
- If in doubt, make the work unit smaller and more local.
