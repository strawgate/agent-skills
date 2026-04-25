---
name: resolve-pr-threads
description: Resolve or unresolve review comment threads on GitHub PRs using the GraphQL API. Use when you need to resolve addressed review feedback or check thread status.
argument-hint: [owner/repo#PR_NUMBER e.g. "PrefectHQ/fastmcp#3827"]
allowed-tools: Bash
---

# Resolve PR Review Threads

Resolve or unresolve review comment threads on GitHub PRs via the GraphQL API.

## List unresolved threads on a PR

```bash
# Human-readable (tab-separated: id, status, outdated, path, line, author, body)
"$SKILL_DIR/../_shared/github-review-threads/scripts/review-threads.sh" unresolved OWNER/REPO PR_NUMBER

# Full JSON (for programmatic use)
"$SKILL_DIR/../_shared/github-review-threads/scripts/review-threads.sh" unresolved OWNER/REPO PR_NUMBER --json
```

## Resolve a thread

```bash
"$SKILL_DIR/../_shared/github-review-threads/scripts/review-threads.sh" resolve THREAD_ID
```

## Unresolve a thread

```bash
"$SKILL_DIR/../_shared/github-review-threads/scripts/review-threads.sh" unresolve THREAD_ID
```

## Count unresolved threads

```bash
"$SKILL_DIR/../_shared/github-review-threads/scripts/review-threads.sh" count OWNER/REPO PR_NUMBER
```

## Workflow

1. List unresolved threads
2. For each thread, determine if the feedback was addressed in the code
3. **Resolve** threads where the code change addresses the feedback
4. **Reply without resolving** threads where feedback is acknowledged but not addressed
5. Do NOT resolve threads without first replying to explain what was done
