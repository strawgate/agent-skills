#!/usr/bin/env bash
# Shared helper for GitHub PR review threads (GraphQL).
# Consolidates the reviewThreads query + resolve/unresolve mutations
# used by resolve-pr-threads, pr-triage, follow-the-pr, and pr-context.
#
# Usage:
#   review-threads.sh list       OWNER/REPO PR_NUMBER [--json]
#   review-threads.sh unresolved OWNER/REPO PR_NUMBER [--json]
#   review-threads.sh count      OWNER/REPO PR_NUMBER
#   review-threads.sh resolve    THREAD_ID
#   review-threads.sh unresolve  THREAD_ID

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  review-threads.sh list       OWNER/REPO PR_NUMBER [--json]
  review-threads.sh unresolved OWNER/REPO PR_NUMBER [--json]
  review-threads.sh count      OWNER/REPO PR_NUMBER
  review-threads.sh resolve    THREAD_ID
  review-threads.sh unresolve  THREAD_ID
EOF
  exit 1
}

[[ $# -lt 2 ]] && usage

cmd="$1"; shift

# ── List / unresolved / count ───────────────────────────────────────────────

list_threads() {
  local repo="$1" pr="$2" filter="${3:-all}" json_flag="${4:-}"
  local owner="${repo%/*}" repo_name="${repo#*/}"

  local raw
  raw="$(gh api graphql --paginate \
    -f query='query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              isOutdated
              isCollapsed
              path
              line
              startLine
              comments(first: 100) {
                nodes {
                  id
                  databaseId
                  body
                  createdAt
                  author { login }
                }
              }
            }
          }
        }
      }
    }' \
    -F owner="$owner" \
    -F repo="$repo_name" \
    -F number="$pr" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes' \
    | jq -s 'add // []')"

  case "$filter" in
    unresolved) raw="$(jq '[.[] | select(.isResolved == false)]' <<<"$raw")" ;;
    resolved)   raw="$(jq '[.[] | select(.isResolved == true)]' <<<"$raw")" ;;
    *) ;; # all
  esac

  if [[ "$json_flag" == "--json" ]]; then
    printf '%s\n' "$raw"
  else
    # Compact human-readable output: one line per thread
    jq -r '.[] | [
      .id,
      (if .isResolved then "resolved" else "UNRESOLVED" end),
      (if .isOutdated then "outdated" else "current" end),
      (.path // "(no file)"),
      (.line // 0 | tostring),
      (.comments.nodes[0].author.login // "unknown"),
      (.comments.nodes[0].body[:120] | gsub("\n"; " "))
    ] | join("\t")' <<<"$raw"
  fi
}

# ── Resolve / unresolve ────────────────────────────────────────────────────

mutate_thread() {
  local mutation="$1" thread_id="$2"
  gh api graphql \
    -f query="mutation { ${mutation}(input: {threadId: \"${thread_id}\"}) { thread { isResolved } } }" \
    --jq ".data.${mutation}.thread.isResolved"
}

# ── Dispatch ────────────────────────────────────────────────────────────────

case "$cmd" in
  list)
    [[ $# -lt 2 ]] && usage
    list_threads "$1" "$2" "all" "${3:-}"
    ;;
  unresolved)
    [[ $# -lt 2 ]] && usage
    list_threads "$1" "$2" "unresolved" "${3:-}"
    ;;
  count)
    [[ $# -lt 2 ]] && usage
    list_threads "$1" "$2" "unresolved" "--json" | jq 'length'
    ;;
  resolve)
    [[ $# -lt 1 ]] && usage
    mutate_thread "resolveReviewThread" "$1"
    ;;
  unresolve)
    [[ $# -lt 1 ]] && usage
    mutate_thread "unresolveReviewThread" "$1"
    ;;
  *)
    usage
    ;;
esac
