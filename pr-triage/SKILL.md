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

Uses Python CLI via `uv run` from the unified gh-triage package:

```bash
# Overview: all PRs in one table (~1 GraphQL point)
uv run gh-triage prs OWNER/REPO

# Per-PR details: metadata, threads, comments, reviews, diff (1 GraphQL point + REST free)
uv run gh-triage pr-details OWNER/REPO PR_NUMBER

# Context bundle for follow-through
uv run gh-triage pr-context OWNER/REPO PR_NUMBER
```

## Step 1: Fetch Overview

```bash
uv run gh-triage prs OWNER/REPO
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
uv run gh-triage pr-details OWNER/REPO PR_NUMBER
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

## Fetching Check Run Details and Annotations

### Two Approaches

**GraphQL (recommended for summaries/title)** - Get summary info directly on CheckRun object
**REST (recommended for annotations)** - More detailed annotation data including raw_details, blob_href, title

### Step 1: Get Check Runs via GraphQL

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
                    status
                    conclusion
                    databaseId
                    summary
                    title
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.commits.nodes[].commit.checkSuites.nodes[].checkRuns.nodes[] | "\(.databaseId) \(.name): \(.conclusion // .status) — \(.title // "")"'
```

This returns lines like: `74448216645 preview: FAILURE —`

### Step 2: For Annotations (REST)

GitHub Actions checks use annotations with detailed file/line info:

```bash
# Get annotations (includes raw_details, blob_href, title - more than GraphQL)
gh api repos/OWNER/REPO/check-runs/CHECK_RUN_ID/annotations
```

Annotation fields:
- `path` - file path
- `annotation_level` - "notice", "warning", or "failure"
- `message` - the annotation message
- `raw_details` - additional details
- `start_line` / `end_line` - line numbers
- `blob_href` - URL to file in commit

### Example: Fetch All Failed Check Annotations

```bash
REPO="strawgate/o11yfleet"
PR_NUM="850"

# Get all failed check run IDs and their names
gh api graphql -f query="
{
  repository(owner: \"strawgate\", name: \"o11yfleet\") {
    pullRequest(number: $PR_NUM) {
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
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}" --jq '.data.repository.pullRequest.commits.nodes[].commit.checkSuites.nodes[].checkRuns.nodes[] | select(.conclusion == "FAILURE") | "\(.databaseId) \(.name)"' | while read -r id name; do
  echo "=== $name (ID: $id) ==="
  gh api repos/strawgate/o11yfleet/check-runs/$id/annotations 2>/dev/null | jq -r '.[] | "[\(.annotation_level)] \(.path):\(.start_line): \(.message)"'
done
```

### Quick Check: View PR Checks Summary

```bash
# Simple summary of all checks
gh pr checks PR_NUMBER

# Get checks with JSON (includes job IDs for logs)
gh pr checks PR_NUMBER --json name,status,conclusion,databaseId
```

## PR Rocket Checks (pr-rocket)

PR Rocket runs additional checks like: `test-coverage`, `docs-freshness`, `security-basics`, `no-anti-patterns`, `breaking-changes`, `performance`.

### Finding PR Rocket Check IDs

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
                checkRuns(first: 30) {
                  nodes {
                    name
                    status
                    conclusion
                    databaseId
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.commits.nodes[].commit.checkSuites.nodes[].checkRuns.nodes[] | select(.name | test("^PR Rocket"; "i")) | "\(.databaseId) \(.name): \(.conclusion // .status)"'
```

### Getting PR Rocket Check Details

PR Rocket checks use `summary` and `title` fields directly on CheckRun (GraphQL has these natively):

```bash
# Get all PR Rocket checks with summary/title via GraphQL
gh api graphql -f query="
{
  repository(owner: \"OWNER\", name: \"REPO\") {
    pullRequest(number: PR_NUMBER) {
      commits(last: 1) {
        nodes {
          commit {
            checkSuites(first: 10) {
              nodes {
                checkRuns(first: 30) {
                  nodes {
                    name
                    conclusion
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
}" --jq '.data.repository.pullRequest.commits.nodes[].commit.checkSuites.nodes[].checkRuns.nodes[] | select(.name | test("^PR Rocket"; "i")) | "\(.name): \(.conclusion) — \(.title // "")\n\(.summary[0:200])"'
```

Example output:
```
PR Rocket: no-anti-patterns: SUCCESS — No issues found
This diff only changes property access syntax from dot notation to bracket notation. Both `env?.OTEL_EXPORTER_URL` and `env?.["OTEL_EXPORTER_URL"]` are semantically identical for static property names...
```