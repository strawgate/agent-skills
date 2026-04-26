---
name: pr-triage
description: Triage, review, fix, and manage open PRs for a GitHub repo. Use when the user says "loop through PRs", "review PRs", "check PRs", "triage PRs", or "pr triage". NEVER merges without explicit user permission.
argument-hint: [owner/repo and optional filter e.g. "strawgate/memagent", "strawgate/memagent skip #221"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# PR Triage

Triage all open PRs, review code, fix issues, and prepare for merge.

## Critical Rule: NEVER Merge Without Permission

**You MUST NOT merge any PR unless the user explicitly says to merge it.**

## Scripts

- [Fetch PR triage overview](${CLAUDE_SKILL_DIR}/scripts/fetch-pr-triage.sh)
- [Deep fetch for specific PR](${CLAUDE_SKILL_DIR}/scripts/fetch-pr-context-deep.sh)

## Step 0: Determine the Target Repo

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

## Step 1: Fetch Overview

```bash
~/.claude/skills/_shared/github-pr-triage/scripts/fetch-pr-triage.sh OWNER/REPO
```

This creates `/tmp/pr-triage/OWNER__REPO/`:
```
├── open-prs.json           # Raw listing
├── prs-overview.txt       # Quick triage view
├── prs/                   # Active open PRs
│   └── 2664/
│       ├── pr.json         # PR metadata
│       ├── checks.json     # CI checks
│       ├── metadata.json   # Quick stats (mergeable, CI failures)
│       ├── comments.json   # Discussion (REST, free)
│       ├── reviews.json   # Reviews (REST, free)
│       └── threads.json   # Review threads (GraphQL, 1pt)
├── prs-merged/            # Archived after merge
└── prs-closed/          # Archived after close
```

**GraphQL cost:** ~16 points for 5 PRs fresh, 1 point cached.

## Step 2: Quick Triage with `prs-overview.txt`

```
# | Draft | Mergeable | CI | Files | Title
---
2664 | false | CONFLICTING | ✓ | 54 | feat: enforce indexing_slicing...
2679 | false | MERGEABLE | ✗3 | 2 | fix(loki): normalize endpoint...
```

**Priority order:**
1. `CONFLICTING` - must resolve conflicts
2. `CI: ✗N` - N failing checks
3. `Draft` - needs marking ready
4. Large PRs (54 files) - review carefully

## Step 3: Deep Dive for Problematic PRs

For PRs with CI failures, conflicts, or needing review:

```bash
~/.claude/skills/_shared/github-pr-triage/scripts/fetch-pr-context-deep.sh OWNER/REPO PR_NUMBER
```

This fetches:
- `pr.diff` - full unified diff
- `files.json` - changed files
- `diffs/<file>.diff` - per-file patches
- `threads.json` - review threads with resolved/outdated state

## Step 4: CI and Review Check

For each PR needing work:

```bash
gh pr checks PR_NUMBER --repo OWNER/REPO
```

Check for:
- All green ✓
- Lint failures only
- Test failures
- No CI yet

## Step 5: Review Threads

Review threads tell you what needs addressing:

```bash
~/.claude/skills/_shared/github-review-threads/scripts/review-threads.sh list OWNER/REPO PR_NUMBER
```

Categorize each thread:
- **OUTDATED + FIXED** → resolve
- **ACTIVE + FIXED** → resolve
- **ACTIVE + VALID** → fix code or reply
- **NOISE** → resolve

## Step 6: Code Review

Launch review agents in parallel for actionable PRs. Each review:
1. What it changes
2. Size/scope (files, lines)
3. Risk (isolated vs cross-cutting)
4. Code quality
5. Verdict: safe to merge / needs fixes / needs review / close

## Step 7: Fix

For PRs needing fixes:
- **Lint failures** → run linter + formatter
- **Conflicts** → merge main, resolve, push
- **CI failures** → address specific failures

## Step 8: Present Results

| PR | Title | CI | Threads | Verdict |
|----|-------|----|-----|---------|

Merge-ready when:
1. CI is green
2. 0 unresolved threads
3. Your code review passes

Then **ask user** which to merge.

## Step 9: Merge (Only With Permission)

```bash
gh pr merge PR_NUMBER --repo OWNER/REPO --squash
```

## Guidelines

- **Use caching.** Second run costs only 1 point.
- **Archive is automatic.** Merged/closed PRs move to `prs-merged/`, `prs-closed/`.
- **REST is free.** Comments, reviews, diffs use REST - don't avoid fetching them.
- **GraphQL costs points.** `gh pr checks` = 2pts, threads = 1pt. Fetch wisely.
- **Never merge without explicit user permission.**