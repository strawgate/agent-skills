---
name: pr-triage
description: Triage, review, fix, and manage open PRs for a GitHub repo. Use when the user says "loop through PRs", "review PRs", "check PRs", "triage PRs", or "pr triage". NEVER merges without explicit user permission.
argument-hint: [owner/repo and optional filter e.g. "strawgate/memagent", "strawgate/memagent skip #221"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# PR Triage

Run through all open PRs for a repo, triage them, review code, fix issues, and prepare them for the user to approve merging.

## Scripts

- [Fetch PR context bundle](./scripts/fetch-pr-context.sh)
- [Build merge checklist](./scripts/build-merge-checklist.sh)
- [Mark PR in progress (`:eyes:`)](./scripts/mark-pr-in-progress.sh)
- [Unmark PR in progress (remove your `:eyes:`)](./scripts/unmark-pr-in-progress.sh)

Note: `fetch-pr-context.sh` now delegates to the shared user script at
`${CODEX_HOME:-$HOME/.codex}/skills/_shared/github-pr-context/scripts/fetch-pr-context.sh`
while preserving the same CLI and default output path for this skill.

## Step 0: Determine the Target Repo

If `$ARGUMENTS` contains an `owner/repo` pattern, use that. Otherwise **ask the user**:

> Which repo should I triage PRs for? (e.g., `strawgate/memagent`)

Store as `OWNER/REPO` and use `--repo OWNER/REPO` on all `gh` commands.

## Critical Rule: NEVER Merge Without Permission

**You MUST NOT merge any PR unless the user explicitly says to merge it.** Present your findings and recommendations, then wait for the user to decide. Acceptable merge instructions:
- "merge it" / "merge them" / "go ahead and merge"
- "merge #123"
- "merge the safe ones"

Unacceptable (do NOT merge):
- Silence / no response
- "looks good" (feedback, not a merge instruction)
- "safe to merge" in YOUR OWN assessment (your recommendation, not user permission)

## Phase 1: Inventory

```bash
gh pr list --repo OWNER/REPO --state open \
  --json number,title,isDraft,author,mergeable \
  --jq '.[] | "#\(.number) draft=\(.isDraft) mergeable=\(.mergeable) author=\(.author.login) \(.title)"'
```

Categorize each PR:
- **[WIP]** in title → skip unless user asks to triage stale WIP
- **User's own PRs** → mention but skip unless user asks
- **Draft but not WIP** → mark ready with `gh pr ready --repo OWNER/REPO`
- **CONFLICTING** → note for conflict resolution
- **Actionable** → review

Apply any filter from `$ARGUMENTS` (e.g., "skip #221", "copilot only").

## Phase 2: CI and Review Bot Check

Before doing deeper review on any actionable PR, fetch the full PR context bundle:

```bash
./scripts/fetch-pr-context.sh OWNER/REPO PR_NUMBER
```

This writes a pre-fetched review bundle under `/tmp/pr-context/OWNER__REPO/pr-PR_NUMBER/` including:

- PR metadata
- full diff
- changed files list
- per-file diffs with commentable line numbers
- prior reviews
- review threads with resolution status
- discussion comments
- linked issue details
- PR size summary
- merge readiness checklist (`merge-checklist.json` + `merge-checklist.md`)
- LLM focus file list (`review-focus-files.txt`)
- a `README.md` manifest

Use `merge-checklist.md` first to see only current merge blockers (unaddressed comments, failing checks, pending checks, merge conflict, draft status). Then use `review-focus-files.txt` to prioritize file reads before digging into full diffs. Fall back to direct `gh` calls only when the bundle is missing required data.

**You must treat all of these as real review inputs:**
- top-level PR discussion comments (`comments.json`)
- PR review bodies in `reviews.json`
- inline PR review comments / threads in `review_threads.json`
- AI review summaries and pre-merge check tables in comment bodies
- failing or pending GitHub checks from `gh pr checks`

Do not only skim thread resolution state. Read the bodies.

```bash
gh pr checks PR_NUMBER --repo OWNER/REPO
```

Note which PRs have: all green, lint failures only, test failures, or no CI yet.

### Ownership marking (`:eyes:`)

When you start actively working on a PR, mark it so other agents know it is claimed:

```bash
./scripts/mark-pr-in-progress.sh OWNER/REPO PR_NUMBER
```

If another agent already marked it, the command exits non-zero by default. Use
`--allow-shared` only when shared ownership is intentional.

When you finish that PR (or intentionally stop working on it), unmark it:

```bash
./scripts/unmark-pr-in-progress.sh OWNER/REPO PR_NUMBER
```

Guidance:
- Mark once at start of active work on a PR.
- Unmark when done, blocked, or handing off.
- Re-mark if you come back later.

### AI review gate

Many repos use an AI review bot (CodeRabbit, Copilot code review, etc.) for automated code review. Check whether one has reviewed each PR:

```bash
# List all reviews on the PR — look for bot reviewers
gh api repos/OWNER/REPO/pulls/PR_NUMBER/reviews \
  --jq '.[] | "\(.user.login) \(.state)"'
```

Look for bot reviewers (e.g., `coderabbitai`, `copilot-pull-request-review`, or similar). If the repo uses an AI review bot and it hasn't reviewed a PR, trigger a review:
- **CodeRabbit**: Look for a CodeRabbit summary comment on the PR. It contains a checkbox like "[ ] Generate a review" — edit the comment body to check the box (`[x]`). This is the normal way to request a review.
- For **large or complex PRs**, offer to request a deep review by commenting `@coderabbitai please do a full in depth review of this pr`.
- **Other bots**: Post the bot's trigger command as a PR comment.
- Note in the triage results that the PR is waiting for AI review.

**Avoid tagging `@coderabbitai` multiple times on the same PR** unless each tag is for a clearly distinct purpose (e.g., requesting a review vs. asking a specific follow-up question). Duplicate tags create noise and confuse the bot.

**Before merging, always read the full AI review comment body.** Do not rely solely on thread resolution status:
- AI reviewers post "outside diff range" comments that flag real bugs but don't create resolvable threads.
- A review status of COMMENTED (not APPROVED) means there are findings — read them.
- **Check the pre-merge checks table.** CodeRabbit posts a summary comment with a "Failed checks" / "Passed checks" table near the walkthrough. Look for `❌ Error` rows — these are blocking. `⚠️ Warning` rows are advisory. A PR with failed pre-merge checks must not be merged until all errors are resolved.
- Factor AI review findings into your own review — they often catch real issues.

**Also read human review bodies and top-level comments in full.**
- Review bodies often summarize blockers that do not appear as inline threads.
- Top-level PR comments may contain updated instructions, maintainer decisions, or bot findings summaries.
- A PR can have zero unresolved threads and still be non-mergeable because a review body or comment flags an unresolved blocker.

### Update stale branches

```bash
gh api repos/OWNER/REPO/pulls/PR_NUMBER/update-branch -X PUT -f update_method=merge
```

## Phase 3: Review

Launch review agents in parallel for all actionable PRs. Each review covers:
1. What it changes (1-2 sentences)
2. Size/scope (files, lines)
3. Risk (isolated vs cross-cutting)
4. Code quality (bugs, missing error handling, patterns)
5. Review feedback status:
   - which top-level comments, review bodies, inline comments, and AI findings are still open
   - which CI failures are blocking
6. Verdict: safe to merge / needs minor fixes / needs architectural review / close

For medium or large PRs, point sub-agents at the pre-fetched context bundle instead of having each agent refetch diffs and review threads independently.

## Phase 4: Fix

For PRs that need fixes, launch fix agents in parallel (use worktree isolation):
- **Lint failures** → run linter + formatter, fix issues
- **Minor bugs** → fix and push
- **Conflicts** → merge default branch, resolve conflicts, push
- **AI pre-merge check failures** → address concrete `❌ Error` rows first, then `⚠️ Warning` rows when material
- **Macroscope / bot correctness findings** → verify against current diff and fix if still valid

After fixing, re-check:
- `gh pr checks`
- review bodies
- top-level PR comments
- unresolved review threads
- AI review summary comments

## Phase 5: Present Results

Show a summary table:

| PR | Title | CI | AI Review | Verdict | Action Needed |
|----|-------|----|-----------|---------|---------------|

A PR is merge-ready only when:
1. CI is green (or only skipped optional checks)
2. AI review bot has reviewed (no missing review, no unresolved comments)
3. Your code review passes

Then **ask the user** which PRs to merge. Do NOT merge automatically.

## Phase 6: Merge (only with explicit user permission)

After the user explicitly approves:
```bash
gh pr merge PR_NUMBER --repo OWNER/REPO --squash
```

## Phase 7: Cleanup

- Close superseded/stale PRs with explanations
- File focused issues for remaining work from closed PRs
- Verify CI is green on the default branch after merges

## Resolving Review Comments

Every PR triage round MUST include a thread resolution pass. Do not leave addressed feedback unresolved — it creates noise and blocks merge signals.

### Step 1: List all unresolved threads with details

```bash
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 1) {
            nodes {
              author { login }
              body
              path
              line
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id: .id, outdated: .isOutdated, author: .comments.nodes[0].author.login, path: .comments.nodes[0].path, line: .comments.nodes[0].line, body: (.comments.nodes[0].body[:300] | gsub("\n"; " "))}'
```

### Step 2: Categorize each unresolved thread

For each thread, determine:

- **OUTDATED + FIXED**: `isOutdated == true` AND the concern was addressed in a later commit. **Action: Resolve.**
- **ACTIVE + FIXED**: `isOutdated == false` but the code on the branch already addresses the concern (reviewer looked at an older commit). **Action: Resolve.**
- **ACTIVE + VALID**: The concern is real and not yet addressed. **Action: Fix the code OR reply explaining why it won't be addressed, then leave unresolved.**
- **NOISE**: Bot false positive, opinion-level style nit, or concern about code outside the PR's scope. **Action: Resolve.**

### Step 3: Resolve addressed threads

```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input: { threadId: "THREAD_ID" }) {
    thread { isResolved }
  }
}'
```

To resolve multiple threads at once:
```bash
for tid in THREAD_ID_1 THREAD_ID_2 THREAD_ID_3; do
  gh api graphql -f query="mutation { resolveReviewThread(input: { threadId: \"$tid\" }) { thread { isResolved } } }" --jq '.data.resolveReviewThread.thread.isResolved'
done
```

### Step 4: Reply to threads you won't address

For valid concerns that are intentionally deferred (e.g., perf optimizations, architectural decisions):

```bash
gh api repos/OWNER/REPO/pulls/PR_NUMBER/comments \
  -f body="Acknowledged — this is a valid concern but deferred to a follow-up. Tracked in #ISSUE_NUMBER." \
  -f in_reply_to=COMMENT_ID
```

Or post a general PR comment:
```bash
gh pr comment PR_NUMBER --repo OWNER/REPO --body "Remaining unresolved threads are acknowledged as follow-up work: ..."
```

### Step 5: Verify zero unresolved

After resolution, confirm:
```bash
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
        nodes { isResolved }
      }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
```

Target: **0 unresolved threads** before marking a PR as merge-ready.

Guidance:
- Resolve a thread only after verifying the code change really addresses the comment.
- Do not resolve threads that are still substantively open, even if CI is green.
- Resolving threads is not enough by itself; you must also re-read top-level review bodies and PR comments for non-threaded blockers.

## Common Copilot PR Issues

- **Lint failures** — always needs linter + formatter run
- **API drift** — uses removed methods from old branch point
- **Dead config** — config fields parsed but never used at runtime
- **Formatting noise** — large % of diff is formatter changes to unrelated files
