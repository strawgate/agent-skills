#!/usr/bin/env bash
# Quick PR triage overview - ~1 GraphQL point
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 OWNER/REPO [OUT_DIR]

Fetches quick PR list for triage (~1 GraphQL point).

Example:
  $0 strawgate/fastforward
  $0 strawgate/fastforward /tmp/my-triage

Output:
  OUT_DIR/prs-overview.txt    # triage table
  OUT_DIR/prs-open.txt       # tab-separated list
  OUT_DIR/open-prs.json      # raw data

Run fetch-pr-details.sh OWNER/REPO PR_NUMBER for full per-PR context (CI, threads, diffs).
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage

repo="$1"
OUT_DIR="${2:-/tmp/pr-triage/${repo//\//__}}"

owner="${repo%%/*}"
repo_name="${repo#*/}"

mkdir -p "$OUT_DIR/prs" "$OUT_DIR/prs-merged" "$OUT_DIR/prs-closed"

echo "=== PR Triage Overview: $repo ==="
echo "Fetch cost: ~1 GraphQL point (all PRs in one query)"

OPEN_PRS="$OUT_DIR/open-prs.json"
PREV_PRS="$OUT_DIR/prev-open-prs.json"
[[ -f "$OPEN_PRS" ]] && cp "$OPEN_PRS" "$PREV_PRS"

# Fetch all open PRs with comments, threads, CI status in ONE query (1 point)
echo "Fetching PRs..."
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      pullRequests(first: 100, states: OPEN) {
        nodes {
          number
          title
          isDraft
          mergeable
          changedFiles
          additions
          deletions
          comments { totalCount }
          reviewThreads { totalCount }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup { state }
              }
            }
          }
        }
      }
    }
  }
' -F owner="$owner" -F repo="$repo_name" > "$OPEN_PRS"

OPEN_COUNT=$(jq '.data.repository.pullRequests.nodes | length' "$OPEN_PRS")
echo "  Found $OPEN_COUNT open PRs"

# Archive PRs that are no longer open
echo "Archiving closed/merged PRs..."
CURRENT_PR_NUMBERS=$(jq -r '.data.repository.pullRequests.nodes[].number' "$OPEN_PRS")

for pr_dir in "$OUT_DIR/prs"/*/; do
  [[ -d "$pr_dir" ]] || continue
  pr_num=$(basename "$pr_dir")
  pr_num_int=${pr_num#+([0-9])}
  if ! echo "$CURRENT_PR_NUMBERS" | grep -q "^${pr_num_int}$"; then
    echo "  Archiving #$pr_num"
    mkdir -p "$OUT_DIR/prs-closed/$pr_num"
    mv "$pr_dir"/* "$OUT_DIR/prs-closed/$pr_num/" 2>/dev/null || true
    rmdir "$pr_dir"
  fi
done

# Write overview
echo "Writing overview..."

jq -r '.data.repository.pullRequests.nodes | .[] | "\(.number)\t\(.isDraft)\t\(.mergeable)\t\(.changedFiles)\t\(.title)"' "$OPEN_PRS" > "$OUT_DIR/prs-open.txt"

{
  echo "# PR Triage Overview"
  echo ""
  echo "**Owner/Repo:** $repo"
  echo "**Open PRs:** $OPEN_COUNT"
  echo "**Fetch cost:** ~1 GraphQL point (single query for all PRs)"
  echo ""
  echo "Run \`fetch-pr-details.sh $repo PR_NUMBER\` for full per-PR context."
  echo ""
  echo "| # | Draft | Mergeable | CI | Threads | Comments | +L | -L | Title |"
  echo "|---|--------|-----------|-------|--------|---------|----|----|-------|"
  jq -r '.data.repository.pullRequests.nodes[] | @json' "$OPEN_PRS" | while IFS= read -r pr_json; do
    pr_num=$(echo "$pr_json" | jq -r '.number')
    additions=$(echo "$pr_json" | jq -r '.additions')
    deletions=$(echo "$pr_json" | jq -r '.deletions')
    ci_state=$(echo "$pr_json" | jq -r '.commits.nodes[0].commit.statusCheckRollup.state')
    thread_count=$(echo "$pr_json" | jq -r '.reviewThreads.totalCount')
    comment_count=$(echo "$pr_json" | jq -r '.comments.totalCount')

    # CI status
    case "$ci_state" in
      SUCCESS) ci_status="✓" ;;
      FAILURE|ERROR) ci_status="✗" ;;
      PENDING|EXPECTED) ci_status="⏳" ;;
      *) ci_status="?" ;;
    esac

    # Threads
    if [[ "$thread_count" -gt 0 ]]; then
      threads_status="✗$thread_count"
    else
      threads_status="✓"
    fi

    echo "| $pr_num | $(echo "$pr_json" | jq -r '.isDraft') | $(echo "$pr_json" | jq -r '.mergeable') | $ci_status | $threads_status | $comment_count | $additions | $deletions | $(echo "$pr_json" | jq -r '.title') |"
  done
  echo ""
  echo "## Per-PR Folders"
  echo ""
  echo "Run \`fetch-pr-details.sh $repo PR_NUMBER\` to populate folder with:"
  echo "- \`pr.json\`, \`checks.json\`, \`threads.json\` (GraphQL)"
  echo "- \`comments.json\`, \`reviews.json\`, \`pr.diff\`, \`files.json\`, \`diffs/\` (REST, free)"
} > "$OUT_DIR/prs-overview.txt"

echo ""
echo "Done: $OUT_DIR"
echo ""
echo "Overview: $OUT_DIR/prs-overview.txt"
echo "Active PRs: $OUT_DIR/prs/"