---
name: follow-the-pr
description: Follow a PR after you push it by polling for new review feedback, comments, CI state changes, and merge-readiness. Use when the user says "follow the PR", "watch this PR", "poll this PR", or wants the agent that opened a PR to keep tracking it until mergeable.
argument-hint: [OWNER/REPO PR_NUMBER or PR_URL, optional poll interval seconds]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, WebFetch
---

# Follow The PR

Use this skill after you create or update a pull request and want the same agent to keep watching it until it is mergeable or new action is required.

## Goal

Turn PR-following into a polling loop with explicit activation criteria so the agent does not have to continuously re-derive whether anything changed.

The skill should:
1. Establish a baseline snapshot of the PR state.
2. Poll at a fixed interval, default `300` seconds.
3. Exit the wait loop only when something actionable changed.
4. Refresh full PR context when action is required.
5. Let the agent address feedback or report merge readiness, then resume the loop.

## Scripts

- [Wait for PR activity](./scripts/wait-for-pr-activity.sh)
- Reuses [Fetch PR context bundle](../pr-triage/scripts/fetch-pr-context.sh)

## Inputs

Accept either:
- `OWNER/REPO PR_NUMBER`
- a full PR URL like `https://github.com/OWNER/REPO/pull/123`

If the poll interval is not provided, default to `300` seconds.

## Non-blocking checks

By default, the wait script treats these as non-blocking for merge-ready detection:
- `Code Coverage`
- `Kani proofs`

Override with:
```bash
FOLLOW_PR_NONBLOCKING_CHECKS='Code Coverage,Kani proofs,Some Other Check'
```

## Standard loop

### Step 1: Start or resume the watcher

```bash
./scripts/wait-for-pr-activity.sh OWNER/REPO PR_NUMBER --interval 300
```

The script writes state under:
```bash
/tmp/follow-pr/OWNER__REPO/pr-PR_NUMBER/
```

Artifacts:
- `snapshot.json`: normalized current PR state
- `context/`: refreshed PR context bundle when activation occurs

### Step 2: Interpret activation reasons

The script exits when one or more of these occurs:
- `merge_ready`: PR is mergeable, has zero unresolved threads, and only non-blocking checks remain red/pending
- `blocking_checks_changed`: a blocking CI failure appeared or changed
- `new_comment`: new top-level PR discussion comment
- `new_review`: new PR review body
- `unresolved_threads_changed`: unresolved review thread set changed
- `head_changed`: PR head SHA changed
- `review_requested`: review decision became `CHANGES_REQUESTED`
- `pr_closed`: PR merged or closed

When the script exits, inspect the returned summary and act accordingly.

### Step 3: On activation

If the reason is:
- `merge_ready`: report that clearly to the user. Do not merge without explicit permission.
- `blocking_checks_changed`: inspect the failing check logs and fix the issue if appropriate.
- `new_comment`, `new_review`, `unresolved_threads_changed`, or `review_requested`: use the refreshed context bundle in `context/` and address the feedback.
- `head_changed`: re-read the PR head state before making edits. If someone else advanced the branch, integrate that state instead of assuming your old local context is still valid.
- `pr_closed`: stop following it.

### Step 4: Resume follow mode

After you push fixes or finish triage, run the wait script again.

## Rules

- Never merge the PR without explicit user permission.
- If the branch moved under you and you were not the one who moved it, stop and reassess before editing.
- Always use the refreshed context bundle after activation instead of relying on stale cached review state.
- Prefer this skill after the agent pushes a PR update, not instead of fixing feedback.

## Example

```bash
/skill follow-the-pr strawgate/memagent 1776 300
```

Expected behavior:
1. Capture baseline.
2. Sleep.
3. Wake when CI fails, a review lands, or the PR becomes merge-ready.
4. Refresh context.
5. Act.
6. Resume waiting.
