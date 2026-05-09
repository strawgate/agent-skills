---
name: organize-work-items
description: Create and maintain work-unit issues — scheduling metas that bundle low-discretion, low-conflict work for one agent run.
argument-hint: "[owner/repo and optional scope e.g. 'strawgate/memagent', 'strawgate/memagent elasticsearch', 'strawgate/memagent pipeline.rs']"
allowed-tools: Read Grep Glob Bash Agent
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

- [gh-issues](${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-issues) — fetch all open issues
- [gh-prs](${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-prs) — fetch all open PRs
- [gh-triage-to-records.py](${CLAUDE_SKILL_DIR}/../_shared/github-repo-inventory/scripts/gh-triage-to-records.py) — convert JSON to text records
- [build-semantic-index.sh](${CLAUDE_SKILL_DIR}/../_shared/github-repo-inventory/scripts/build-semantic-index.sh) — build similarity indexes
- [summarize-work-unit-structure.sh](${CLAUDE_SKILL_DIR}/scripts/summarize-work-unit-structure.sh) — summarize existing work-unit structure

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

- `README.md`, `DEVELOPING.md`, `CONTRIBUTING.md`, `AGENTS.md`
- `docs/ARCHITECTURE.md`, `ROADMAP.md`
- `docs/**/*.md`, `dev-docs/**/*.md`

If an issue audit or planning doc exists, read it first.

## Step 2: Fetch and Index Repo Data

```bash
# Fetch issue overview (~1 GraphQL point)
${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-issues OWNER/REPO -o /tmp/gh-triage/OWNER__REPO

# Convert gh-triage JSON to .txt records
python3 ${CLAUDE_SKILL_DIR}/../_shared/github-repo-inventory/scripts/gh-triage-to-records.py /tmp/gh-triage/OWNER__REPO

# Build semantic indexes
bash ${CLAUDE_SKILL_DIR}/../_shared/github-repo-inventory/scripts/build-semantic-index.sh OWNER/REPO
```

This creates in `/tmp/issue-organizer/OWNER__REPO/`:

```
├── issues/                        # Consolidated folders
│   └── 02561/issue.txt         # Full issue with similar_*
├── prs/
│   └── 00937/pr.txt
├── issues-open.txt                # Minimal index: # | date | title
├── issues-closed-last-100.txt   # Recent closed issues
├── prs-merged-last-100.txt      # Recent merged PRs
└── prs-open.txt
```

## Step 3: Use Semantic Similarity for Batching

Each `issue.txt` includes `similar_issues` - use this to find related issues that should be batched together.

**Grouping strategy:**
1. Read `issues-open.txt` to see all open issues
2. For each candidate work unit, read the `similar_issues` from each member issue
3. Issues with high mutual similarity scores are good batching candidates

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

## Step 5: What Does NOT Belong in a Work Unit

Do not create a work unit when the work requires high discretion:

- unresolved architecture choices
- research spikes
- cross-cutting repo-wide cleanups
- big prerequisite refactors with unclear stop points
- items whose success criteria are still debated

## Step 6: Use the Standard Work-Unit Template

```markdown
work-unit: <subsystem> — <batch name>

## Purpose

<What this batch accomplishes and why these items should land together.>

## Repo footprint

- `path/to/file_or_dir`
- `path/to/tests`

## In scope

| # | Type | Why included |
|---|------|--------------|
| #123 | bug | same handler and tests |
| #124 | docs | same API surface |

## Non-goals

- <things intentionally excluded to keep the batch safe>

## Done when

- [ ] listed issues resolved or updated
- [ ] regression tests added or updated
- [ ] docs and implementation aligned for this slice
```

## Step 7: Present Ready-to-Run Commands

```bash
gh issue create --repo OWNER/REPO \
  --title "work-unit: elasticsearch sink — small correctness fixes" \
  --label work-unit \
  --label copilot \
  --body-file /tmp/work-unit.md
```

## Guidelines

- Audit first, schedule second.
- Optimize for merge-safe repo footprint before thematic purity.
- Use `similar_issues` to find batching candidates - high mutual similarity = good batch.
- Prefer by-reference work units over duplicating issue content.
- Use metas/phases for explanation and sequencing; use work units for execution.
- It is acceptable for a work unit to mix bug, docs, feature, and refactor items if the code footprint is the same.
- If in doubt, make the work unit smaller and more local.