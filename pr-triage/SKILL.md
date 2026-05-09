---
name: pr-triage
description: Triage, review, fix, and manage open PRs for a GitHub repo. NEVER merges without explicit user permission.
allowed-tools: Read Grep Glob Bash Edit Write Agent WebSearch WebFetch
metadata:
  argument-hint: "[owner/repo e.g. 'strawgate/memagent']"
---

# PR Triage

Triage all open PRs, review code, fix issues, and prepare for merge.

## Critical Rule: NEVER Merge Without Permission

**You MUST NOT merge any PR unless the user explicitly says to merge it.**

## Scripts

### Data fetching (shared gh-triage wrappers)

```bash
# Overview: all PRs in one table (~1 GraphQL point)
${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-prs OWNER/REPO

# Per-PR details: metadata, threads, comments, reviews, diff (1 GraphQL point + REST free)
${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-pr-details OWNER/REPO PR_NUMBER

# Context bundle for follow-through
${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-pr-context OWNER/REPO PR_NUMBER
```

### Local helpers

- [build-merge-checklist.sh](${CLAUDE_SKILL_DIR}/scripts/build-merge-checklist.sh) — reads a PR bundle dir and emits a merge-readiness checklist
- [mark-pr-in-progress.sh](${CLAUDE_SKILL_DIR}/scripts/mark-pr-in-progress.sh) — claim a PR so other agents skip it
- [unmark-pr-in-progress.sh](${CLAUDE_SKILL_DIR}/scripts/unmark-pr-in-progress.sh) — release the claim

## Step 1: Fetch Overview

```bash
${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-prs OWNER/REPO
```

This shows a table with all open PRs (CI status, threads, comments, +L/-L).

**GraphQL cost:** ~1 point for all PRs (uses totalCount for efficient info)

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
${CLAUDE_SKILL_DIR}/../_shared/gh-triage/scripts/gh-pr-details OWNER/REPO PR_NUMBER
```

This fetches:
- **REST (free):** comments, reviews, diff, files
- **GraphQL (1 point):** PR metadata, review threads with resolved status, CI status

**GraphQL cost:** ~1 point per PR (threads only, metadata via REST)

## Step 4: Address Feedback

Common fixes:
- **Lint failures** → run linter + formatter
- **Conflicts** → merge main, resolve, push
- **CI failures** → for failed checks, fetch annotations to understand the specific failure (see "Fetching Check Run Details" above)
- **Review threads** → fix code or reply

## Step 5: Present Results

Merge-ready when:
1. CI is green
2. 0 unresolved threads
3. Code review passes

Then **ask user** which to merge.

## Guidelines

- **Overview is cheap** - 1pt for all PRs with rich info
- **Details are efficient** - metadata via REST (free), threads via GraphQL (1pt)
- **REST is free** - comments, reviews, diffs don't cost points
- **Never merge without explicit user permission**

## Data Structure

```
/tmp/gh-triage/OWNER__REPO/
├── open-prs.json          # Raw GraphQL response
├── prs/                   # Per-PR folders (populated by pr-details)
│   └── 2664/
│       ├── pr.json         # Full PR metadata
│       ├── metadata.json   # Quick stats (mergeable, CI, threads)
│       ├── threads.json    # Review threads (GraphQL)
│       ├── comments.json   # PR comments (REST, free)
│       ├── reviews.json    # PR reviews (REST, free)
│       ├── pr.diff         # Full diff (REST, free)
│       ├── files.json      # File list (REST, free)
│       └── checks/         # Check run details (REST, free)
│           └── 74448216645/
│               ├── check-run.json  # Full check run metadata
│               └── annotations.json # Check run annotations
└── prs-merged/            # Archived merged PRs
```

## Fetching Check Run Details

```bash
# Simple summary of all checks
gh pr checks PR_NUMBER --repo OWNER/REPO

# Get checks with JSON
gh pr checks PR_NUMBER --repo OWNER/REPO --json name,status,conclusion,databaseId

# Get annotations for a specific failed check run (REST, free)
gh api repos/OWNER/REPO/check-runs/CHECK_RUN_ID/annotations
```

Annotation fields: `path`, `annotation_level` (notice/warning/failure), `message`, `start_line`/`end_line`, `blob_href`.

To find check run IDs for failed checks:

```bash
gh api graphql -f query='
{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      commits(last: 1) {
        nodes {
          commit {
            checkSuites(first: 10) {
              nodes {
                checkRuns(first: 20) {
                  nodes {
                    name
                    conclusion
                    databaseId
                    title
                    summary
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.commits.nodes[].commit.checkSuites.nodes[].checkRuns.nodes[] | select(.conclusion == "FAILURE") | "\(.databaseId) \(.name): \(.title // "")"'
```