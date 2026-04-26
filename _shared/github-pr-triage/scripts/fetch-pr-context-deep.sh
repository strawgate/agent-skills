#!/usr/bin/env bash
# Deep fetch for a specific PR - full context with diffs and threads
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 OWNER/REPO PR_NUMBER [OUT_DIR]

Fetches full PR context including:
- Diff
- Review threads
- Per-file diffs
- Full comments/reviews

Uses REST where possible (free), GraphQL only for threads.

Example:
  $0 strawgate/fastforward 2668
EOF
  exit 1
}

[[ $# -lt 2 ]] && usage

repo="$1"
pr_num="$2"
OUT_DIR="${3:-/tmp/pr-triage/${repo//\//__}/prs/${pr_num}}"

mkdir -p "$OUT_DIR/diffs"

echo "=== Deep fetch: $repo #$pr_num ==="

# ── Diff (REST - free) ────────────────────────────────────────────────────────
echo "  Fetching diff..."
if ! gh pr diff "$pr_num" --repo "$repo" > "$OUT_DIR/pr.diff" 2>/dev/null; then
  echo 'error: failed to fetch diff' >&2
fi

# ── Files (REST - free) ────────────────────────────────────────────────────
echo "  Fetching file list..."
gh api "repos/$repo/pulls/$pr_num/files" --paginate | jq -s 'add // []' > "$OUT_DIR/files.json"

# ── Per-file diffs (REST - free) ────────────────────────────────────────────
echo "  Fetching per-file diffs..."
jq -c '.[]' "$OUT_DIR/files.json" | while IFS= read -r entry; do
  filename=$(printf '%s\n' "$entry" | jq -r '.filename')
  patch_text=$(printf '%s\n' "$entry" | jq -r '.patch // empty')
  mkdir -p "$OUT_DIR/diffs/$(dirname "$filename")"
  printf '%s\n' "$patch_text" > "$OUT_DIR/diffs/${filename}.diff"
done

# ── Review threads (GraphQL - 1 point) ────────────────────────────────────
echo "  Fetching review threads..."
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_THREADS="$SKILL_DIR/../../github-review-threads/scripts/review-threads.sh"

if [[ -x "$REVIEW_THREADS" ]]; then
  if ! "$REVIEW_THREADS" list "$repo" "$pr_num" --json > "$OUT_DIR/threads.json" 2>/dev/null; then
    echo '[]' > "$OUT_DIR/threads.json"
  fi
else
  echo '[]' > "$OUT_DIR/threads.json"
fi

# Count unresolved
UNRESOLVED=$(jq '[.[] | select(.isResolved == false)] | length' "$OUT_DIR/threads.json" 2>/dev/null || echo 0)
echo "  Unresolved threads: $UNRESOLVED"

# ── Summary ─────────────────────────────────────────────────────────────────
{
  echo "# PR Context Deep Fetch"
  echo ""
  echo "Repo: $repo"
  echo "PR: #$pr_num"
  echo ""
  echo "Files: $(jq 'length' "$OUT_DIR/files.json")"
  echo "Diff lines: $(wc -l < "$OUT_DIR/pr.diff")"
  echo "Unresolved threads: $UNRESOLVED"
} > "$OUT_DIR/README.md"

echo "Done: $OUT_DIR"
echo ""
echo "Contents:"
ls -la "$OUT_DIR/"