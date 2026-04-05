---
name: find-stale-issues
description: Audit all open GitHub issues against PRs and codebase to find stale, resolved, duplicate, and overlapping issues. Use when the user says "find stale issues", "stale issues", "issue audit", "audit issues", "clean up issues", "issue triage", or "find-stale-issues".
argument-hint: "[owner/repo and optional scope e.g. 'strawgate/logfwd', 'strawgate/logfwd label:bug', 'strawgate/logfwd since 2025-01-01']"
---

# Issue Audit

Audit all open GitHub issues against merged PRs, open PRs, and the current codebase. Produce a structured report identifying issues that can be closed, narrowed, or deduplicated.

## Step 0: Determine the Target Repo

If `$ARGUMENTS` contains an `owner/repo` pattern, use that. Otherwise detect from the current git repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If neither works, **ask the user**. Store as `OWNER/REPO`.

## Phase 1: Read All Project Docs

Read these files if they exist (skip missing ones silently). This context is essential for understanding issue intent:

- `README.md`
- `DEVELOPING.md` / `CONTRIBUTING.md`
- `CLAUDE.md` / `AGENTS.md`
- `docs/ARCHITECTURE.md` or any architecture doc
- `CHANGELOG.md` (last 5-10 entries)
- `ROADMAP.md` or any roadmap/planning docs
- Any `docs/` or `dev-docs/` directory — read all `.md` files

Also check for prior audit results:
```bash
find . -iname "*audit*" -o -iname "*triage*" | grep -i issue
```

## Phase 2: Download All Open Issues

Fetch every open issue with full metadata. Use pagination to get all of them:

```bash
# Get total count first
gh api repos/OWNER/REPO/issues?state=open\&per_page=1 \
  --jq length 2>/dev/null
gh issue list --repo OWNER/REPO --state open --limit 1 \
  --json totalCount -q '.[0] // empty'

# Download all open issues with full detail
gh issue list --repo OWNER/REPO --state open --limit 500 \
  --json number,title,body,labels,assignees,milestone,createdAt,updatedAt,comments \
  > /tmp/issues-open.json

# Count what we got
jq length /tmp/issues-open.json
```

If more than 500 issues exist, paginate:
```bash
PAGE=1
echo '[]' > /tmp/issues-open.json
while true; do
  BATCH=$(gh api "repos/OWNER/REPO/issues?state=open&per_page=100&page=$PAGE&direction=asc" \
    --jq '[.[] | select(.pull_request == null)]')
  [ "$(echo "$BATCH" | jq length)" -eq 0 ] && break
  jq -s '.[0] + .[1]' /tmp/issues-open.json <(echo "$BATCH") > /tmp/issues-open-tmp.json
  mv /tmp/issues-open-tmp.json /tmp/issues-open.json
  PAGE=$((PAGE + 1))
done
```

## Phase 3: Download All PRs (Open and Closed/Merged)

```bash
# All merged PRs (these are what fix issues)
gh pr list --repo OWNER/REPO --state merged --limit 500 \
  --json number,title,body,mergedAt,headRefName,labels \
  > /tmp/prs-merged.json

# All open PRs (in-flight work)
gh pr list --repo OWNER/REPO --state open --limit 500 \
  --json number,title,body,isDraft,headRefName,labels \
  > /tmp/prs-open.json

# All closed-not-merged PRs (abandoned work — useful for context)
gh pr list --repo OWNER/REPO --state closed --limit 500 \
  --json number,title,body,headRefName,labels,mergedAt \
  | jq '[.[] | select(.mergedAt == null)]' \
  > /tmp/prs-closed.json

echo "Merged: $(jq length /tmp/prs-merged.json)"
echo "Open:   $(jq length /tmp/prs-open.json)"
echo "Closed: $(jq length /tmp/prs-closed.json)"
```

For repos with extensive history, paginate merged PRs the same way as issues.

## Phase 4: Build the Cross-Reference Map

For each open issue, search for evidence of resolution. This phase produces *candidates* — issues that might be resolved. Phase 5 verifies them against the actual codebase before promoting any candidate to "Definitely Resolved."

### 4a. Explicit references in PRs

PRs that mention issue numbers (Fixes #N, Closes #N, Resolves #N, or just #N):

```bash
# Search merged PR bodies and titles for each issue number
for ISSUE_NUM in $(jq -r '.[].number' /tmp/issues-open.json); do
  MATCHES=$(jq -r --arg n "#$ISSUE_NUM" \
    '.[] | select(.title + " " + (.body // "") | test($n)) | "#\(.number) \(.title)"' \
    /tmp/prs-merged.json)
  if [ -n "$MATCHES" ]; then
    echo "Issue #$ISSUE_NUM -> $MATCHES"
  fi
done
```

### 4b. Branch name references

```bash
# PRs with branch names referencing issue numbers
for ISSUE_NUM in $(jq -r '.[].number' /tmp/issues-open.json); do
  jq -r --arg n "$ISSUE_NUM" \
    '.[] | select(.headRefName | test("(^|[^0-9])" + $n + "($|[^0-9])")) | "#\(.number) branch=\(.headRefName)"' \
    /tmp/prs-merged.json 2>/dev/null
done
```

### 4c. Comment-based references

```bash
# For high-value issues, fetch comments to see if someone said "fixed in PR #X"
gh api repos/OWNER/REPO/issues/ISSUE_NUM/comments \
  --jq '.[].body' 2>/dev/null
```

### 4d. Duplicate and overlap detection

PR cross-references only find resolved issues — they miss duplicates entirely. This step compares issues against each other.

Group all open issues by subsystem. Derive groups from file paths, component names, or labels mentioned in the issue bodies (e.g., "file tailing," "OTLP encoding," "config validation," "diagnostics," "TCP/UDP," "documentation"). Then within each group:

1. **Exact duplicates** — Two issues describing the same bug or feature. Compare root cause, proposed fix, and affected code. Titles can differ while the underlying issue is identical.
2. **Subset duplicates** — An issue whose scope is entirely contained within another (especially a meta/epic). If closing the parent would close the child, it's a subset.
3. **Overlapping metas** — Meta/epic issues that bundle overlapping sets of child issues. Map out child issue lists for each meta and look for children claimed by multiple parents, or metas whose scopes partially cover the same ground.

For each candidate duplicate pair, read both issue bodies in full. Title-only comparison is insufficient — an issue titled "HTTP retry" might actually be about connection pooling, while one titled "backoff logic" might be its true duplicate.

## Phase 5: Verify Candidates Against the Codebase

**This is the most important phase.** PR cross-references tell you a fix was *attempted* — only the codebase tells you it *landed and covers the full issue scope.*

Common false positives that cross-referencing alone misses:
- A PR fixed the issue in one file but the same bug exists in 5 other files (partial fix)
- A PR was merged but the code was later reverted or overwritten
- A PR references an issue but only addresses part of its scope
- The issue describes a component that was renamed/refactored — the PR touched the old name, the bug persists under the new name

### Verification via parallel subagents

Launch **parallel subagents** to verify candidates. Group candidates into batches of 3-5 issues per agent by theme (e.g., one agent verifies file tailing fixes, another verifies documentation fixes, another verifies output sink fixes). Each agent should:

1. Read the issue body to understand the full scope
2. Read the referenced PR body to understand what was claimed to be fixed
3. **Check the current codebase** — grep for the specific function, pattern, error message, or code construct the issue describes. Confirm the fix is present and complete.
4. For documentation issues, check ALL files that might contain the documented item (README, book/, docs/, examples/), not just the primary doc file
5. Return a verdict: CONFIRMED RESOLVED, PARTIALLY RESOLVED, or NOT RESOLVED, with file paths and line numbers as evidence

Example agent prompt:
> You are verifying whether open GitHub issues have been resolved. For each issue below, check the actual codebase to confirm the fix is present and covers the full scope.
>
> **ISSUE #N — "title"**
> Claim: Fixed by PR #M. [brief description of what the PR did]
> - Check [specific file] for [specific fix]
> - Verify [specific behavior] is handled
>
> For each issue, give a verdict: CONFIRMED RESOLVED, PARTIALLY RESOLVED, or NOT RESOLVED, with specific evidence (file paths, line numbers, code snippets).

Similarly, verify duplicate candidates:
> You are verifying whether specific pairs of open issues are true duplicates.
>
> **PAIR: #N vs #M**
> Claim: Both describe [X].
> - Read both issue bodies from /tmp/issues-open.json
> - Check the codebase to confirm they describe the same thing
> - Are they truly identical in scope or does one have broader/different coverage?

**Only promote a candidate to "Definitely Resolved" after a subagent has confirmed the fix exists in the current code.** If verification is ambiguous, downgrade to "Likely Resolved."

## Phase 6: Classify Each Issue

After verification, assign each open issue to exactly one category.

### Classification rules:

**Definitely Resolved** — A merged PR addresses this issue AND a verification subagent confirmed the fix exists in the current codebase. Both conditions are required.

**Likely Resolved** — Strong evidence the issue is fixed but verification was inconclusive. Examples:
- The code/component described in the issue no longer exists (refactored away)
- A merged PR addresses the same area but doesn't explicitly reference this issue
- The issue describes behavior that current code clearly handles
- Verification found the fix but the agent noted caveats

**Partially Resolved** — Verification confirmed some aspects are fixed, others remain. Record:
- What's fixed (with PR references and codebase evidence)
- What's still open (specific remaining work, with file paths where relevant)

**Duplicate** — Verification confirmed two issues describe the same problem. Keep the one that is:
- More detailed, OR
- Has a parent meta/epic, OR
- Is newer and better scoped

**Stale** — No activity in 6+ months AND:
- The feature area has changed significantly, OR
- The issue describes a problem that may no longer exist, OR
- The issue is a feature request that doesn't align with current direction

**Overlapping Metas** — Meta/epic issues that partially overlap in scope. These shouldn't be closed but need scope clarification.

**Still Open** — Genuinely open issues. Don't include these in the report unless the count is useful for the summary.

## Phase 7: Produce the Report

### Report Structure

---

#### Summary

| Metric | Count |
|--------|-------|
| Open issues audited | N |
| Definitely resolved (close now) | N |
| Likely resolved (verify then close) | N |
| Partially resolved (update scope) | N |
| Duplicates (close) | N |
| Stale (review) | N |
| Overlapping metas (narrow scope) | N |
| Still genuinely open | N |

---

#### Definitely Resolved

Issues with verified evidence of resolution. **Action: close with comment referencing the fixing PR.**

| Issue | Title | Fixed By | Evidence |
|-------|-------|----------|----------|
| #N | Title | PR #M | Brief description of fix + codebase verification |

---

#### Likely Resolved

Strong evidence but verification was inconclusive. **Action: verify the specific claim, then close.**

| Issue | Title | Evidence | Verify By |
|-------|-------|----------|-----------|
| #N | Title | Component removed in PR #M | Check that X no longer needed |

Include a specific verification step for each — don't just say "verify then close". Say what to verify: run a command, check a file, test a scenario.

---

#### Partially Resolved

Some work done, some remaining. **Action: comment on the issue with remaining scope.**

| Issue | Title | Done | Remaining |
|-------|-------|------|-----------|
| #N | Title | PR #M fixed X | Y and Z still needed (file paths where relevant) |

---

#### Duplicates

| Close | Keep | Reason |
|-------|------|--------|
| #N | #M | Both describe X; #M has more detail and is parented under #K |

---

#### Stale Issues

Issues with no activity and unclear relevance. **Action: comment asking if still relevant, close after 30 days with no response.**

| Issue | Title | Last Activity | Why Stale |
|-------|-------|---------------|-----------|
| #N | Title | 2025-03-01 | Component rewritten since filing |

---

#### Overlapping Metas

Meta/tracking issues with overlapping scope. **Action: clarify boundaries, cross-reference.**

For each overlap, state:
- Which issues overlap
- What the overlapping scope is
- Recommended resolution (narrow one, merge, cross-reference)

---

#### Batch Actions

Provide ready-to-run commands for all closures:

```bash
# Definitely resolved — close with comment
gh issue close N --repo OWNER/REPO --comment "Resolved by PR #M. Verified: [one-line evidence]."
gh issue close N --repo OWNER/REPO --comment "Resolved by PR #M. Verified: [one-line evidence]."

# Duplicates — close with reference
gh issue close N --repo OWNER/REPO --comment "Duplicate of #M. [brief reason]."

# Partially resolved — comment with remaining scope
gh issue comment N --repo OWNER/REPO --body "Partial fix: PR #M addressed X. Remaining: Y (file:line), Z (file:line)."

# Stale — comment for feedback
gh issue comment N --repo OWNER/REPO --body "This issue has been open with no activity since DATE. Is it still relevant? Will close in 30 days if no response."
```

---

## Guidelines

- **Read issue bodies.** Titles are misleading. An issue titled "HTTP retry" might actually be about connection pooling once you read it.
- **Read PR bodies and diffs.** A PR that references an issue might only partially fix it. Check the actual changes.
- **PR cross-reference is necessary but not sufficient.** A PR that says "Fixes #N" might fix only part of #N, might have been reverted, or might have fixed the issue in one place while the same bug exists in others. Always verify against current code before classifying as Definitely Resolved.
- **Be conservative with "Definitely Resolved."** If there's any doubt, put it in "Likely Resolved" instead. False closures waste more time than leaving issues open.
- **For documentation issues, check every doc file.** A fix to `docs/CONFIG_REFERENCE.md` doesn't help if `README.md`, `book/`, `examples/`, and `DEPLOYMENT.md` still contain the wrong information.
- **Respect meta issues.** Don't close a parent meta just because some children are done. Check that ALL listed work items are complete. Map out child issues and verify each one.
- **Note label conventions.** If the repo uses priority labels (P0, P1), severity labels, or type labels, use them in your analysis to prioritize what matters.
- **Check for issue hierarchies.** Look for "parent" or "tracking" issues that list sub-issues. Cross-reference completeness. Watch for child issues claimed by multiple metas.
- **Consider the author's intent.** Read the full issue thread, not just the opening post. The scope may have evolved in comments.
- **Fetch comments for ambiguous cases.** If classification is unclear from the title/body alone, fetch the issue comments for additional context.
- **Use parallel subagents liberally.** Verification is the bottleneck. Group candidates by theme (3-5 per agent) and launch agents in parallel. Each agent reads the issue body, the PR body, and checks the codebase independently.
- **Never close issues yourself.** Present findings and batch commands. The user decides what to close.
