---
name: pr-triage
description: Triage, review, fix, and manage open PRs for a GitHub repo. Use when the user says "loop through PRs", "review PRs", "check PRs", "triage PRs", or "pr triage". NEVER merges without explicit user permission.
argument-hint: [owner/repo and optional filter e.g. "strawgate/memagent", "strawgate/memagent skip #221"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# PR Triage

Run through all open PRs for a repo, triage them, review code, fix issues, and prepare them for the user to approve merging.

## Scripts

- [Fetch PR context bundle](${CLAUDE_SKILL_DIR}/scripts/fetch-pr-context.sh)
- [Build merge checklist](${CLAUDE_SKILL_DIR}/scripts/build-merge-checklist.sh)
- [Mark PR in progress](${CLAUDE_SKILL_DIR}/scripts/mark-pr-in-progress.sh)
- [Unmark PR in progress](${CLAUDE_SKILL_DIR}/scripts/unmark-pr-in-progress.sh)

## Critical Rule: NEVER Merge Without Permission

**You MUST NOT merge any PR unless the user explicitly says to merge it.** Present findings and wait for user decision.

## Step 0: Determine the Target Repo

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

## Step 1: Fetch Repo Data with Semantic Indexes

For the full repo picture, run:

```bash
~/.claude/skills/_shared/github-repo-inventory/scripts/index-repo.sh OWNER/REPO
```

This creates `/tmp/issue-organizer/OWNER__REPO/` with:

```
├── issues/N/issue.txt       # Full issue with similar_issues, similar_merged_prs
├── prs/N/pr.txt           # Full PR with similar_issues
├── prs-merged-last-100.txt # Recent merged PRs
└── issues-open.txt
```

**Use this to find:**
- What issues a PR addresses (via `prs/N/pr.txt` similar_issues)
- Related open PRs that might conflict
- PRs that duplicate the same fix

## Step 2: List Open PRs

```bash
gh pr list --repo OWNER/REPO --state open \
  --json number,title,isDraft,author,mergeable \
  --jq '.[] | "#\(.number) draft=\(.isDraft) mergeable=\(.mergeable) author=\(.author.login) \(.title)"'
```

Categorize:
- **[WIP]** in title → skip unless asked
- **Draft but not WIP** → mark ready
- **CONFLICTING** → note for resolution
- **Actionable** → review

## Step 3: Fetch PR Context for Each Actionable PR

```bash
${CLAUDE_SKILL_DIR}/scripts/fetch-pr-context.sh OWNER/REPO PR_NUMBER
```

This writes to `/tmp/pr-context/OWNER__REPO/pr-NUMBER/`:
- PR metadata, diff, changed files
- Per-file diffs with line numbers
- Prior reviews and threads
- `merge-checklist.md`
- `review-focus-files.txt`

## Step 4: Check Semantic Relationships

When reviewing a PR, use `/tmp/issue-organizer/OWNER__REPO/prs/N/pr.txt` to see:

```
similar_issues:
  #1234 (score=0.782) ...
  #5678 (score=0.654) ...
```

This shows what **open issues** the PR might address. If a PR strongly matches an issue you're triaging, it's likely the fix.

**To find related open PRs** (potential conflicts):
```bash
# Look for PRs with similar titles or touching same areas
grep -l "elasticsearch\|ES\|loki" /tmp/issue-organizer/OWNER__REPO/prs/*/pr.txt
```

## Step 5: CI and Review Check

```bash
gh pr checks PR_NUMBER --repo OWNER/REPO
```

Check for:
- All green
- Lint failures only
- Test failures
- No CI yet

## Step 6: Review (Use Parallel Subagents)

Launch review agents for actionable PRs in parallel. Each review:
1. What it changes (1-2 sentences)
2. Size/scope (files, lines)
3. Risk (isolated vs cross-cutting)
4. Code quality
5. Review feedback status
6. Verdict: safe to merge / needs fixes / needs review / close

## Step 7: Fix

For PRs needing fixes:
- **Lint failures** → run linter + formatter
- **Minor bugs** → fix and push
- **Conflicts** → merge default branch, resolve
- **AI pre-merge check failures** → address `❌ Error` rows first

## Step 8: Present Results

| PR | Title | CI | AI Review | Verdict |
|----|-------|----|-----------|---------|

**Merge-ready only when:**
1. CI is green
2. AI review bot has reviewed
3. Your code review passes

Then **ask the user** which PRs to merge.

## Step 9: Merge (Only With Permission)

```bash
gh pr merge PR_NUMBER --repo OWNER/REPO --squash
```

## Step 10: Thread Resolution

Before marking PR merge-ready, resolve all threads:

```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
"$SKILL_DIR/../_shared/github-review-threads/scripts/review-threads.sh" unresolved OWNER/REPO PR_NUMBER
```

Categorize each thread:
- **OUTDATED + FIXED** → resolve
- **ACTIVE + FIXED** → resolve
- **ACTIVE + VALID** → fix code or reply explaining deferral
- **NOISE** → resolve

Target: **0 unresolved threads** before merge.

## Guidelines

- **Use semantic similarity to understand PR intent.** If a PR strongly matches an issue's similar_issues, it likely addresses it.
- **Find related PRs** that touch the same subsystem — flag potential conflicts.
- **Never merge without explicit user permission.**
- **Read AI review comment bodies in full** — not just thread resolution status.