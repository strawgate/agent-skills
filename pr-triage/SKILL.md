---
name: pr-triage
description: Triage, review, fix, and manage open PRs for a GitHub repo. Use when the user says "loop through PRs", "review PRs", "check PRs", "triage PRs", or "pr triage". NEVER merges without explicit user permission.
argument-hint: [owner/repo and optional filter e.g. "strawgate/memagent", "strawgate/memagent skip #221"]
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebSearch, WebFetch
---

# PR Triage

Run through all open PRs for a repo, triage them, review code, fix issues, and prepare them for the user to approve merging.

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

## Phase 2: CI Check

```bash
gh pr checks PR_NUMBER --repo OWNER/REPO
```

Note which PRs have: all green, lint failures only, test failures, or no CI yet.

Update stale branches:
```bash
gh api repos/OWNER/REPO/pulls/PR_NUMBER/update-branch -X PUT -f update_method=merge
```

## Phase 3: Review

Launch review agents in parallel for all actionable PRs. Each review covers:
1. What it changes (1-2 sentences)
2. Size/scope (files, lines)
3. Risk (isolated vs cross-cutting)
4. Code quality (bugs, missing error handling, patterns)
5. Verdict: safe to merge / needs minor fixes / needs architectural review / close

## Phase 4: Fix

For PRs that need fixes, launch fix agents in parallel (use worktree isolation):
- **Lint failures** → run linter + formatter, fix issues
- **Minor bugs** → fix and push
- **Conflicts** → merge default branch, resolve conflicts, push

## Phase 5: Present Results

Show a summary table:

| PR | Title | Verdict | Action Needed |
|----|-------|---------|---------------|

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

After fixing review feedback, resolve addressed threads:
```bash
# List unresolved threads
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
        nodes { id isResolved comments(first: 1) { nodes { body } } }
      }
    }
  }
}'

# Resolve a thread
gh api graphql -f query='mutation {
  resolveReviewThread(input: { threadId: "THREAD_ID" }) {
    thread { isResolved }
  }
}'
```

## Common Copilot PR Issues

- **Lint failures** — always needs linter + formatter run
- **API drift** — uses removed methods from old branch point
- **Dead config** — config fields parsed but never used at runtime
- **Formatting noise** — large % of diff is formatter changes to unrelated files
