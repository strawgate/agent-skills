---
name: find-stale-issues
description: Audit all open GitHub issues against PRs and codebase to find stale, resolved, duplicate, and overlapping issues. Use when the user says "find stale issues", "stale issues", "issue audit", "audit issues", "clean up issues", "issue triage", or "find-stale-issues".
argument-hint: "[owner/repo and optional scope e.g. 'strawgate/logfwd', 'strawgate/logfwd label:bug', 'strawgate/logfwd since 2025-01-01']"
---

# Issue Audit

Audit all open GitHub issues against recently closed PRs, merged PRs, recent commits, open PRs, and the current codebase. Produce a structured report identifying issues that can be closed, narrowed, deduplicated, or marked stale after investigation.

## Scripts

- [Fetch and index repo data](${CLAUDE_SKILL_DIR}/../_shared/github-repo-inventory/scripts/index-repo.sh)

## Step 0: Determine the Target Repo

If `$ARGUMENTS` contains an `owner/repo` pattern, use that. Otherwise detect from the current git repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If neither works, **ask the user**. Store as `OWNER/REPO`.

## Step 1: Fetch and Index Repo Data

Run the index script to fetch data and build semantic similarity indexes:

```bash
${CLAUDE_SKILL_DIR}/../_shared/github-repo-inventory/scripts/index-repo.sh OWNER/REPO
```

This writes to `/tmp/issue-organizer/OWNER__REPO/` with this structure:

```
OWNER__REPO/
├── raw/                           # Raw GitHub API data
│   ├── open-issues.json
│   ├── closed-issues.json
│   ├── merged-prs.json
│   └── ...
├── issues/                        # Consolidated issue folders
│   └── 02561/issue.txt          # Full issue with similar_*
├── prs/                           # Consolidated PR folders
│   └── 00937/pr.txt
├── issues-open.txt                # Minimal index: # | date | title
├── issues-closed-last-100.txt     # Recent closed issues
├── prs-merged-last-100.txt       # Recent merged PRs
└── prs-closed-last-20.txt        # Recent closed PRs
```

## Step 2: Read Project Docs

Read these files if they exist (skip missing ones silently):

- `README.md`, `DEVELOPING.md`, `CONTRIBUTING.md`, `AGENTS.md`
- `docs/ARCHITECTURE.md`, `ROADMAP.md`
- `docs/**/*.md`, `dev-docs/**/*.md`

Also check for prior audit results:
```bash
find . -iname "*audit*" -o -iname "*triage*" | grep -i issue
```

## Step 3: Find Candidates Using Semantic Similarity

Each consolidated `issue.txt` includes:
- `similar_issues`: Top 8 semantically similar *open* issues
- `similar_merged_prs`: Top 8 semantically similar *merged* PRs
- `similar_closed_issues`: Top 8 semantically similar *closed* issues

**High-similarity matches (score > 0.65) are strong candidates for:**
1. Already resolved (similar_merged_prs)
2. Duplicates (similar_issues with high score)

### Quick scan for obvious candidates

Look for issues where:
- `similar_merged_prs` contains a PR that **explicitly references the issue** (e.g., `PR #2618 ... (#2207)`)
- Issue body contains `Status: COMPLETED`
- Issue is a `phase:` with similar_merged_prs containing the referenced PRs

Example script to find candidates:
```bash
# Find issues with high-similarity merged PRs
for issue_dir in /tmp/issue-organizer/OWNER__REPO/issues/*/; do
  issue_num=$(basename "$issue_dir")
  issue_file="$issue_dir/issue.txt"

  # Check if issue body says COMPLETED
  if grep -qi "status.*completed" "$issue_file"; then
    echo "COMPLETED: #$issue_num"
  fi

  # Check if similar_merged_prs contains explicit reference
  top_pr=$(grep -A1 "similar_merged_prs:" "$issue_file" | head -2 | tail -1 | grep -o "#[0-9]*")
  if echo "$top_pr" | grep -q "(#"; then  # explicit ref
    echo "EXPLICIT: #$issue_num <- $top_pr"
  fi
done
```

## Step 4: Verify Candidates

**For resolved candidates:**
1. Read the issue body to understand full scope
2. Read the similar merged PR to understand what was fixed
3. Check the current codebase to confirm the fix is present

**For duplicate candidates:**
1. Read both issue bodies
2. Confirm they describe the same problem
3. Check if one is a subset of the other

Use parallel subagents for verification:
> You are verifying whether open GitHub issues have been resolved. For each issue below, check the actual codebase to confirm the fix is present.
>
> **ISSUE #N — "title"**
> Claim: Fixed by PR #M. [brief description]
> - Check [specific file] for [specific fix]

## Step 5: Classify Issues

**Definitely Resolved** — Merged PR explicitly references issue AND codebase confirms fix.

**Likely Resolved** — High semantic similarity (>0.7) to a related PR, but not explicit reference.

**Duplicate** — Two issues with high similarity (>0.8) to each other, describing the same problem.

**Still Open** — No strong evidence of resolution.

## Step 6: Produce Report

### Report Structure

---

#### Summary

| Metric | Count |
|--------|-------|
| Open issues audited | N |
| Definitely resolved | N |
| Likely resolved | N |
| Duplicates | N |
| Still open | N |

---

#### Definitely Resolved

| Issue | Title | Fixed By | Evidence |
|-------|-------|----------|----------|
| #N | Title | PR #M | Brief description |

---

#### Duplicates

| Close | Keep | Reason |
|-------|------|--------|
| #N | #M | Both describe X |

---

#### Batch Actions

```bash
# Definitely resolved
gh issue close N --repo OWNER/REPO --comment "Resolved by PR #M. [evidence]."

# Duplicates
gh issue close N --repo OWNER/REPO --comment "Duplicate of #M. [reason]."
```

---

## Guidelines

- **Use consolidated issue folders.** Read `/tmp/issue-organizer/OWNER__REPO/issues/N/issue.txt` for full context.
- **Use minimal indexes first.** `issues-open.txt` for listing, `prs-merged-last-100.txt` for recent PRs.
- **Semantic similarity is a guide, not proof.** High scores (>0.7) are strong hints; always verify.
- **Be conservative.** If in doubt, mark as "Likely Resolved" instead of "Definitely."
- **Never close issues yourself.** Present findings and batch commands for user approval.