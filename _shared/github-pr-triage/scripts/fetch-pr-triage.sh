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
  OUT_DIR/prs/               # per-PR folders (metadata only)

Run fetch-pr-details.sh for full per-PR context (CI, threads, diffs).
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage

repo="$1"
OUT_DIR="${2:-/tmp/pr-triage/${repo//\//__}}"

mkdir -p "$OUT_DIR/prs" "$OUT_DIR/prs-merged" "$OUT_DIR/prs-closed"

echo "=== PR Triage Overview: $repo ==="

# Fetch open PRs (GraphQL - 1 point for up to 100 PRs)
OPEN_PRS="$OUT_DIR/open-prs.json"
PREV_PRS="$OUT_DIR/prev-open-prs.json"

[[ -f "$OPEN_PRS" ]] && cp "$OPEN_PRS" "$PREV_PRS"

echo "Fetching open PRs..."
gh pr list --repo "$repo" --state open \
  --json number,title,state,isDraft,mergeable,author,additions,deletions,changedFiles,updatedAt \
  > "$OPEN_PRS"

OPEN_COUNT=$(jq 'length' "$OPEN_PRS")
echo "  Found $OPEN_COUNT open PRs"

# Archive PRs that are no longer open
echo "Archiving closed/merged PRs..."
CURRENT_PR_NUMBERS=$(jq -r '.[].number' "$OPEN_PRS")

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

# Write quick overview
echo "Writing overview..."

jq -r '.[] | "\(.number)\t\(.isDraft)\t\(.mergeable)\t\(.changedFiles)\t\(.title)"' "$OPEN_PRS" > "$OUT_DIR/prs-open.txt"

{
  echo "# PR Triage Overview"
  echo ""
  echo "**Owner/Repo:** $repo"
  echo "**Open PRs:** $OPEN_COUNT"
  echo "**Fetch cost:** ~1 GraphQL point"
  echo ""
  echo "Run \`fetch-pr-details.sh $repo PR_NUMBER\` for full per-PR context (CI, threads, diffs)."
  echo ""
  echo "| # | Draft | Mergeable | Files | +L | -L | Title |"
  echo "|---|--------|-----------|-------|----|----|-------|"
  while IFS= read -r pr_line; do
    pr_num=$(echo "$pr_line" | jq -r '.number')
    additions=$(echo "$pr_line" | jq -r '.additions')
    deletions=$(echo "$pr_line" | jq -r '.deletions')
    echo "| $pr_num | $(echo "$pr_line" | jq -r '.isDraft') | $(echo "$pr_line" | jq -r '.mergeable') | $(echo "$pr_line" | jq -r '.changedFiles') | $additions | $deletions | $(echo "$pr_line" | jq -r '.title') |"
  done < <(jq -c '.[]' "$OPEN_PRS")
  echo ""
  echo "## Per-PR Folders"
  echo ""
  echo "Each PR has a folder at \`prs/PR_NUMBER/\` with:"
  echo "- \`metadata.json\` - populated after running \`fetch-pr-details.sh\`"
  echo ""
  echo "## Next Steps"
  echo ""
  echo "1. Review overview above"
  echo "2. Pick PRs to investigate"
  echo "3. Run \`fetch-pr-details.sh $repo PR_NUMBER\` for full details"
} > "$OUT_DIR/prs-overview.txt"

echo ""
echo "Done: $OUT_DIR"
echo ""
echo "Overview: $OUT_DIR/prs-overview.txt"
echo "Active PRs: $OUT_DIR/prs/"