---
name: pr-triage
description: Triage, review, fix, and manage open PRs for a GitHub repo. Use when the user says "loop through PRs", "review PRs", "check PRs", "triage PRs", or "pr triage". NEVER merges without explicit user permission.
argument-hint: [owner/repo e.g. "strawgate/memagent"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# PR Triage

Triage all open PRs, review code, fix issues, and prepare for merge.

## Critical Rule: NEVER Merge Without Permission

**You MUST NOT merge any PR unless the user explicitly says to merge it.**

## Scripts

Uses Python CLI via `uv run`:

```bash
cd ~/.claude/skills/_shared/github-pr-triage

# Overview: all PRs in one table (~1 GraphQL point)
uv run pr-triage overview OWNER/REPO

# Per-PR details: CI, threads, comments, reviews, diff (~4 GraphQL points)
uv run pr-triage details OWNER/REPO PR_NUMBER

# Context bundle for follow-through
uv run pr-triage context OWNER/REPO PR_NUMBER
```

## Step 1: Fetch Overview

```bash
cd ~/.claude/skills/_shared/github-pr-triage
uv run pr-triage overview OWNER/REPO
```

This shows a table with all open PRs (CI status, threads, comments, +L/-L).

**GraphQL cost:** ~1 point for all PRs (includes CI status, thread counts, comment counts)

## Step 2: Review the Table

```
┏━━━━━━┳━━━━━━━━━━━┳━━━━┳━━━━━━━━┳━━━━━━┳━━━━━━┳━━━━━━━━━━━┓
┃ #    ┃ Mergeable ┃ CI ┃ Threads ┃ Commen… ┃ +L   ┃ Title     ┃
┡━━━━━━╇━━━━━━━━━━━╇━━━━╇━━━━━━━━╇━━━━━━╇━━━━━━╇━━━━━━━━━━━┩
│ 2664 │ MERGEABLE │ ✗  │ ✗50    │ 9     │ +525 │ feat: enfor…
│ 2667 │ MERGEABLE │ ✗  │ ✗12    │ 4     │ +331 │ refactor:…
```

**Priority order:**
1. `CONFLICTING` - must resolve conflicts
2. `CI: ✗` - failing checks
3. `Threads: ✗N` - N unresolved review threads
4. Large PRs - review carefully

## Step 3: Fetch Per-PR Details

For PRs needing work:

```bash
uv run pr-triage details OWNER/REPO PR_NUMBER
```

This fetches (REST, free):
- `comments.json` - PR comments
- `reviews.json` - PR reviews
- `pr.diff` - full unified diff
- `files.json` - file list with patches
- `diffs/<path>/<file>.diff` - per-file patches

GraphQL (paid):
- `pr.json` - full PR metadata
- `threads.json` - review threads with full body
- CI status (from statusCheckRollup)

**GraphQL cost:** ~4 points per PR

## Step 4: Address Feedback

Common fixes:
- **Lint failures** → run linter + formatter
- **Conflicts** → merge main, resolve, push
- **CI failures** → address specific failures
- **Review threads** → fix code or reply

## Step 5: Present Results

Merge-ready when:
1. CI is green
2. 0 unresolved threads
3. Code review passes

Then **ask user** which to merge.

## Guidelines

- **Overview is cheap** - 1pt for all PRs with rich info
- **Details are expensive** - only fetch what you need
- **REST is free** - comments, reviews, diffs don't cost points
- **Archive is automatic** - merged/closed PRs move to `prs-merged/`, `prs-closed/`
- **Never merge without explicit user permission**

## Data Structure

```
/tmp/pr-triage/OWNER__REPO/
├── open-prs.json          # Raw GraphQL response
├── prs-overview.txt        # Markdown triage table
├── prs/                   # Per-PR folders (populated by details)
│   └── 2664/
│       ├── pr.json         # Full PR metadata
│       ├── metadata.json   # Quick stats (mergeable, CI, threads)
│       ├── checks.json     # CI checks (empty - individual checks via gh pr checks)
│       ├── threads.json    # Review threads
│       ├── comments.json   # PR comments (REST, free)
│       ├── reviews.json    # PR reviews (REST, free)
│       ├── pr.diff         # Full diff (REST, free)
│       ├── files.json      # File list (REST, free)
│       └── diffs/          # Per-file patches (REST, free)
└── prs-closed/            # Archived closed PRs
```