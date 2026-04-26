#!/usr/bin/env bash
# Fetch full details for ONE PR - ~4 GraphQL points
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 OWNER/REPO PR_NUMBER [OUT_DIR]

Fetches full context for a single PR (~4 GraphQL points).

Example:
  $0 strawgate/fastforward 2664
  $0 strawgate/fastforward 2664 /tmp/my-triage

Output (in OUT_DIR/prs/PR_NUMBER/):
  metadata.json     # quick stats
  pr.json          # full PR metadata
  checks.json      # CI checks
  threads.json     # review threads
  comments.json    # PR comments (REST, free)
  reviews.json     # PR reviews (REST, free)
  pr.diff          # full diff (REST, free)
  files.json       # file list (REST, free)
  diffs/           # per-file diffs (REST, free)
EOF
  exit 1
}

[[ $# -lt 2 ]] && usage

repo="$1"
pr_num="$2"
OUT_DIR="${3:-/tmp/pr-triage/${repo//\//__}}"

owner="${repo%%/*}"
repo_name="${repo#*/}"

pr_dir="$OUT_DIR/prs/${pr_num}"
mkdir -p "$pr_dir/diffs"

echo "=== PR Details: $repo #$pr_num ==="

# Fetch PR metadata (GraphQL - 1 point)
echo "  Fetching PR metadata..."
gh pr view "$pr_num" --repo "$repo" \
  --json number,title,body,state,isDraft,mergeable,baseRefName,headRefName,author,additions,deletions,changedFiles,commits,createdAt,updatedAt \
  > "$pr_dir/pr.json"

is_draft=$(jq -r '.isDraft' "$pr_dir/pr.json")
mergeable=$(jq -r '.mergeable' "$pr_dir/pr.json")
updated=$(jq -r '.updatedAt' "$pr_dir/pr.json")

# Fetch CI checks (GraphQL - 2 points, skip for draft)
echo "  Fetching CI checks..."
if [[ "$is_draft" != "true" ]]; then
  if ! gh pr checks "$pr_num" --repo "$repo" \
    --json name,state,bucket,link,workflow \
    > "$pr_dir/checks.json" 2>/dev/null; then
    echo '[]' > "$pr_dir/checks.json"
  fi
else
  echo '[]' > "$pr_dir/checks.json"
fi

# Fetch review threads (GraphQL - 1 point)
echo "  Fetching review threads..."
if ! gh api graphql --paginate \
  -f query='query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            isResolved
            isCollapsed
            isOutdated
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
  -F number="$pr_num" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes' > "$pr_dir/threads.json" 2>/dev/null; then
  echo '[]' > "$pr_dir/threads.json"
fi

# Fetch comments (REST - free)
echo "  Fetching comments..."
if ! gh api "repos/$repo/pulls/$pr_num/comments" --paginate | jq -s 'add // []' > "$pr_dir/comments.json" 2>/dev/null; then
  echo '[]' > "$pr_dir/comments.json"
fi

# Fetch reviews (REST - free)
echo "  Fetching reviews..."
if ! gh api "repos/$repo/pulls/$pr_num/reviews" --paginate | jq -s 'add // []' > "$pr_dir/reviews.json" 2>/dev/null; then
  echo '[]' > "$pr_dir/reviews.json"
fi

# Fetch full diff (REST - free)
echo "  Fetching diff..."
if ! gh pr diff "$pr_num" --repo "$repo" > "$pr_dir/pr.diff" 2>/dev/null; then
  echo '' > "$pr_dir/pr.diff"
fi

# Fetch file list with patches (REST - free)
echo "  Fetching per-file diffs..."
if gh api "repos/$repo/pulls/$pr_num/files" --paginate | jq -s 'add // []' > "$pr_dir/files.json" 2>/dev/null; then
  jq -c '.[]' "$pr_dir/files.json" | while IFS= read -r entry; do
    filename=$(printf '%s\n' "$entry" | jq -r '.filename')
    patch_text=$(printf '%s\n' "$entry" | jq -r '.patch // empty')
    [[ -n "$patch_text" ]] || continue
    mkdir -p "$pr_dir/diffs/$(dirname "$filename")"
    printf '%s\n' "$patch_text" > "$pr_dir/diffs/${filename}.diff"
  done
else
  echo '[]' > "$pr_dir/files.json"
fi

# Write metadata (quick stats)
checks_failed=$(jq '[.[] | select(.state=="FAILURE" or .state=="ERROR")] | length' "$pr_dir/checks.json" 2>/dev/null || echo 0)
diff_lines=$(wc -l < "$pr_dir/pr.diff" 2>/dev/null || echo 0)
unresolved_threads=$(jq '[.[] | select(.isResolved == false)] | length' "$pr_dir/threads.json" 2>/dev/null || echo 0)

jq -n \
  --argjson number "$pr_num" \
  --argjson isDraft "$is_draft" \
  --arg mergeable "$mergeable" \
  --argjson checksFailed "$checks_failed" \
  --arg updated "$updated" \
  --argjson diffLines "$diff_lines" \
  --argjson unresolvedThreads "$unresolved_threads" \
  '{number:$number, isDraft:$isDraft, mergeable:$mergeable, checksFailed:$checksFailed, updatedAt:$updated, diffLines:$diffLines, unresolvedThreads:$unresolvedThreads}' \
  > "$pr_dir/metadata.json"

# Write PR-specific overview
{
  echo "# PR #$pr_num: $(jq -r '.title' "$pr_dir/pr.json")"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| Author | $(jq -r '.author.login' "$pr_dir/pr.json") |"
  echo "| Draft | $is_draft |"
  echo "| Mergeable | $mergeable |"
  echo "| CI | $([[ "$checks_failed" -gt 0 ]] && echo "✗ $checks_failed failed" || echo "✓") |"
  echo "| Unresolved Threads | $([[ "$unresolved_threads" -gt 0 ]] && echo "✗ $unresolved_threads" || echo "✓") |"
  echo "| Diff Lines | $diff_lines |"
  echo "| Files | $(jq 'length' "$pr_dir/files.json") |"
  echo "| Created | $(jq -r '.createdAt' "$pr_dir/pr.json") |"
  echo "| Updated | $updated |"
  echo ""
  echo "## Data Files"
  echo ""
  echo "| File | Description |"
  echo "|------|-------------|"
  echo "| metadata.json | Quick stats (mergeable, CI, threads) |"
  echo "| pr.json | Full PR metadata |"
  echo "| checks.json | CI check results |"
  echo "| threads.json | Review threads |"
  echo "| comments.json | PR comments (REST, free) |"
  echo "| reviews.json | PR reviews (REST, free) |"
  echo "| pr.diff | Full unified diff (REST, free) |"
  echo "| files.json | File list with patches (REST, free) |"
  echo "| diffs/ | Per-file patches (REST, free) |"
  echo ""
  echo "## Failing Checks"
  echo ""
  jq -r '.[] | select(.state == "FAILURE" or .state == "ERROR") | "- \(.name) (\(.workflow))"' "$pr_dir/checks.json" 2>/dev/null || echo "None"
  echo ""
  echo "## Unresolved Threads"
  echo ""
  if [[ "$unresolved_threads" -gt 0 ]]; then
    jq -r '.[] | select(.isResolved == false) | "### \(.path):\(.line // "")\n\nAuthor: \(.comments.nodes[0].author.login)\n\n\(.comments.nodes[0].body[0:500])..."' "$pr_dir/threads.json" 2>/dev/null | head -100
  else
    echo "None"
  fi
} > "$pr_dir/README.md"

echo ""
echo "Done: $pr_dir"
echo ""
ls -la "$pr_dir/"