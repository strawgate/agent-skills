#!/usr/bin/env bash
# Efficient PR triage data fetcher with caching and archive management
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 OWNER/REPO [OUT_DIR]

Fetches PR triage data efficiently with:
- REST for listing (free)
- Caching with ETag/Last-Modified
- Automatic archive of merged/closed PRs

Example:
  $0 strawgate/fastforward
  $0 strawgate/fastforward /tmp/my-triage

Output: OUT_DIR/prs/, OUT_DIR/prs-merged/, OUT_DIR/prs-closed/
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage

repo="$1"
OUT_DIR="${2:-/tmp/pr-triage/${repo//\//__}}"

# Ensure directories exist
mkdir -p "$OUT_DIR/prs" "$OUT_DIR/prs-merged" "$OUT_DIR/prs-closed"

echo "=== PR Triage: $repo ==="
echo "Output: $OUT_DIR"

# ── Step 1: Fetch overview of open PRs (REST, 1 point) ──────────────────────
echo ""
echo "[1/4] Fetching open PR overview..."

OPEN_PRS="$OUT_DIR/open-prs.json"
PREV_PRS="$OUT_DIR/prev-open-prs.json"

# Track previous state
if [[ -f "$OPEN_PRS" ]]; then
  cp "$OPEN_PRS" "$PREV_PRS"
fi

# Fetch current open PRs (REST - free points)
gh pr list --repo "$repo" --state open \
  --json number,title,state,isDraft,mergeable,author,additions,deletions,changedFiles,updatedAt \
  > "$OPEN_PRS"

OPEN_COUNT=$(jq 'length' "$OPEN_PRS")
echo "  Found $OPEN_COUNT open PRs"

# ── Step 2: Archive merged/closed PRs ────────────────────────────────────────
echo ""
echo "[2/4] Archiving merged/closed PRs..."

# Get current open PR numbers
CURRENT_PR_NUMBERS=$(jq -r '.[].number' "$OPEN_PRS")

# Check each PR folder - if PR is no longer open, move to archive
for pr_dir in "$OUT_DIR/prs"/*/; do
  [[ -d "$pr_dir" ]] || continue

  pr_num=$(basename "$pr_dir")
  pr_num_int=${pr_num#+([0-9])} # remove leading zeros for gh

  # Check if this PR is still open
  if ! echo "$CURRENT_PR_NUMBERS" | grep -q "^${pr_num_int}$"; then
    # Check merged vs closed
    # We could check with gh pr view but that costs points
    # For now just archive to closed - user can manually move to merged if needed

    echo "  Archiving #$pr_num to prs-closed/"
    mkdir -p "$OUT_DIR/prs-closed/$pr_num"
    mv "$pr_dir"/* "$OUT_DIR/prs-closed/$pr_num/" 2>/dev/null || true
    rmdir "$pr_dir"
  fi
done

# ── Step 3: Fetch/update context for open PRs ─────────────────────────────────
echo ""
echo "[3/4] Fetching context for open PRs..."

FETCHED=0
SKIPPED=0
MERGED_COUNT=0

while IFS= read -r pr_line; do
  pr_num=$(echo "$pr_line" | jq -r '.number')
  is_draft=$(echo "$pr_line" | jq -r '.isDraft')
  mergeable=$(echo "$pr_line" | jq -r '.mergeable')
  updated=$(echo "$pr_line" | jq -r '.updatedAt')

  pr_dir="$OUT_DIR/prs/${pr_num}"
  mkdir -p "$pr_dir"

  # Check if we need to update (based on updated timestamp)
  META_FILE="$pr_dir/metadata.json"
  NEEDS_UPDATE=true

  if [[ -f "$META_FILE" ]]; then
    LAST_UPDATED=$(jq -r '.updatedAt // ""' "$META_FILE" 2>/dev/null || echo "")
    if [[ "$LAST_UPDATED" == "$updated" ]]; then
      NEEDS_UPDATE=false
      SKIPPED=$((SKIPPED + 1))
    fi
  fi

  if [[ "$NEEDS_UPDATE" == "true" ]]; then
    echo "  #$pr_num (draft=$is_draft, mergeable=$mergeable) - fetching..."
    FETCHED=$((FETCHED + 1))

    # Fetch PR metadata (GraphQL - 1 point)
    gh pr view "$pr_num" --repo "$repo" \
      --json number,title,body,state,isDraft,mergeable,baseRefName,headRefName,author,additions,deletions,changedFiles,commits,createdAt,updatedAt \
      > "$pr_dir/pr.json"

    # Fetch checks if not draft and has updates (GraphQL - 2 points)
    if [[ "$is_draft" != "true" ]]; then
      if ! gh pr checks "$pr_num" --repo "$repo" \
        --json name,state,bucket,link,workflow \
        > "$pr_dir/checks.json" 2>/dev/null; then
        echo '[]' > "$pr_dir/checks.json"
      fi
    else
      echo '[]' > "$pr_dir/checks.json"
    fi

    # Fetch comments (REST - free)
    if ! gh api "repos/$repo/pulls/$pr_num/comments" --paginate | jq -s 'add // []' > "$pr_dir/comments.json" 2>/dev/null; then
      echo '[]' > "$pr_dir/comments.json"
    fi

    # Fetch reviews (REST - free)
    if ! gh api "repos/$repo/pulls/$pr_num/reviews" --paginate | jq -s 'add // []' > "$pr_dir/reviews.json" 2>/dev/null; then
      echo '[]' > "$pr_dir/reviews.json"
    fi

    # Fetch review threads (GraphQL - 1 point)
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
      -F owner="${repo%%/*}" \
      -F repo="${repo#*/}" \
      -F number="$pr_num" \
      --jq '.data.repository.pullRequest.reviewThreads.nodes' > "$pr_dir/threads.json" 2>/dev/null; then
      echo '[]' > "$pr_dir/threads.json"
    fi

    # Fetch full diff (REST - free)
    if ! gh pr diff "$pr_num" --repo "$repo" > "$pr_dir/pr.diff" 2>/dev/null; then
      echo '' > "$pr_dir/pr.diff"
    fi

    # Fetch file list with patches, save per-file diffs (REST - free)
    mkdir -p "$pr_dir/diffs"
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

    # Write minimal metadata for quick triage (includes diffLines and unresolved threads)
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
      > "$META_FILE"

  else
    echo "  #$pr_num - skipping (unchanged)"
  fi

done < <(jq -c '.[]' "$OPEN_PRS")

echo ""
echo "[4/4] Summary"
echo "  PRs found: $OPEN_COUNT"
echo "  Fetched: $FETCHED"
echo "  Skipped (cached): $SKIPPED"

# ── Write overview files ──────────────────────────────────────────────────────
echo ""
echo "[+] Writing overview files..."

# Quick listing for triage
jq -r '.[] | "\(.number)\t\(.isDraft)\t\(.mergeable)\t\(.changedFiles)\t\(.title)"' "$OPEN_PRS" \
  > "$OUT_DIR/prs-open.txt"

# Detailed listing with CI status and unresolved threads
{
  echo "# | Draft | Mergeable | CI | Threads | Title"
  echo "---"
  while IFS= read -r pr_line; do
    pr_num=$(echo "$pr_line" | jq -r '.number')
    meta_file="$OUT_DIR/prs/${pr_num}/metadata.json"
    checks_failed=0
    unresolved_threads=0
    if [[ -f "$meta_file" ]]; then
      checks_failed=$(jq -r '.checksFailed // 0' "$meta_file")
      unresolved_threads=$(jq -r '.unresolvedThreads // 0' "$meta_file")
    fi
    ci_status="✓"
    if [[ "$checks_failed" -gt 0 ]]; then
      ci_status="✗$checks_failed"
    fi
    threads_status="✓"
    if [[ "$unresolved_threads" -gt 0 ]]; then
      threads_status="✗$unresolved_threads"
    fi
    echo "$pr_num | $(echo "$pr_line" | jq -r '.isDraft') | $(echo "$pr_line" | jq -r '.mergeable') | $ci_status | $threads_status | $(echo "$pr_line" | jq -r '.title')"
  done < <(jq -c '.[]' "$OPEN_PRS")
} > "$OUT_DIR/prs-overview.txt"

echo ""
echo "Done: $OUT_DIR"
echo ""
echo "Active PRs: $OUT_DIR/prs/"
echo "Archived: $OUT_DIR/prs-merged/, $OUT_DIR/prs-closed/"
echo "Overview: $OUT_DIR/prs-overview.txt"