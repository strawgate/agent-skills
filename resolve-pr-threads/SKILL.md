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
gh api graphql -f query='
  query {
    repository(owner: "OWNER", name: "REPO") {
      pullRequest(number: PR_NUMBER) {
        reviewThreads(first: 50) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes {
                databaseId
                body
              }
            }
          }
        }
      }
    }
  }
' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {threadId: .id, commentId: .comments.nodes[0].databaseId, body: (.comments.nodes[0].body[:100])}'
```

## Resolve a thread

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: {threadId: "THREAD_ID"}) {
      thread { isResolved }
    }
  }
' --jq '.data.resolveReviewThread.thread.isResolved'
```

## Unresolve a thread

```bash
gh api graphql -f query='
  mutation {
    unresolveReviewThread(input: {threadId: "THREAD_ID"}) {
      thread { isResolved }
    }
  }
' --jq '.data.unresolveReviewThread.thread.isResolved'
```

## Workflow

1. List unresolved threads
2. For each thread, determine if the feedback was addressed in the code
3. **Resolve** threads where the code change addresses the feedback
4. **Reply without resolving** threads where feedback is acknowledged but not addressed
5. Do NOT resolve threads without first replying to explain what was done
