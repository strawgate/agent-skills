#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 OWNER/REPO PR_NUMBER [OUT_DIR]" >&2
  exit 1
fi

repo="$1"
pr_number="$2"
out_dir="${3:-/tmp/pr-context/${repo//\//__}/pr-${pr_number}}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

mkdir -p "$out_dir" "$out_dir/diffs" "$out_dir/threads"

owner="${repo%/*}"
repo_name="${repo#*/}"

# PR metadata
gh pr view "$pr_number" --repo "$repo" \
  --json title,body,author,baseRefName,headRefName,headRefOid,url,number,state,isDraft,mergeable,additions,deletions,changedFiles,commits \
  > "$out_dir/pr.json"

# Full diff
if ! gh pr diff "$pr_number" --repo "$repo" > "$out_dir/pr.diff"; then
  echo "warning: failed to fetch full PR diff; continuing with per-file patches" >&2
  : > "$out_dir/pr.diff"
fi

# Changed files
gh api "repos/$repo/pulls/$pr_number/files" --paginate \
  | jq -s 'add // []' > "$out_dir/files.json"

# Per-file diffs with commentable line numbers
jq -c '.[]' "$out_dir/files.json" | while IFS= read -r entry; do
  filename="$(printf '%s\n' "$entry" | jq -r '.filename')"
  patch_text="$(printf '%s\n' "$entry" | jq -r '.patch // empty')"
  mkdir -p "$out_dir/diffs/$(dirname "$filename")"
  printf '%s\n' "$patch_text" | awk '
    /^@@/ {
      s=$3
      gsub(/\+/, "", s)
      split(s, a, ",")
      line=a[1]+0
      print
      next
    }
    /^\+/ { printf "%d\t%s\n", line++, $0; next }
    /^-/  { printf "  \t%s\n", $0; next }
    /^ /  { printf "%d\t%s\n", line++, $0; next }
    { print }
  ' > "$out_dir/diffs/${filename}.diff"
done

# Useful file orderings
jq -r '[.[] | .filename] | sort | .[]' "$out_dir/files.json" > "$out_dir/file_order_az.txt"
jq -r '[.[] | .filename] | sort | reverse | .[]' "$out_dir/files.json" > "$out_dir/file_order_za.txt"
jq -r '[.[] | {filename, size: ((.additions // 0) + (.deletions // 0))}] | sort_by(-.size) | .[].filename' "$out_dir/files.json" \
  > "$out_dir/file_order_largest.txt"

# Size summary
file_count="$(jq 'length' "$out_dir/files.json")"
diff_lines="$(wc -l < "$out_dir/pr.diff" | tr -d ' ')"
printf '%s files, %s diff lines\n' "$file_count" "$diff_lines" > "$out_dir/pr-size.txt"

# Reviews
if ! gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
  | jq -s 'add // []' > "$out_dir/reviews.json"; then
  printf '[]\n' > "$out_dir/reviews.json"
fi

# Review threads with resolution status
if ! gh api graphql --paginate \
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
  -F number="$pr_number" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes' \
  | jq -s 'add // []' > "$out_dir/review_threads.json"; then
  printf '[]\n' > "$out_dir/review_threads.json"
fi

jq '[.[] | select(.isResolved == false)]' "$out_dir/review_threads.json" > "$out_dir/unresolved_threads.json"
jq '[.[] | select(.isResolved == true)]' "$out_dir/review_threads.json" > "$out_dir/resolved_threads.json"
jq '[.[] | select(.isOutdated == true)]' "$out_dir/review_threads.json" > "$out_dir/outdated_threads.json"

jq -c '.[]' "$out_dir/review_threads.json" | while IFS= read -r thread; do
  filepath="$(printf '%s\n' "$thread" | jq -r '.path // empty')"
  [[ -z "$filepath" ]] && continue
  mkdir -p "$out_dir/threads/$(dirname "$filepath")"
  printf '%s\n' "$thread" >> "$out_dir/threads/${filepath}.jsonl"
done

find "$out_dir/threads" -name '*.jsonl' -print0 2>/dev/null | while IFS= read -r -d '' jsonl; do
  jq -s '.' "$jsonl" > "${jsonl%.jsonl}.json"
  rm -f "$jsonl"
done

# Discussion comments
if ! gh api "repos/$repo/issues/$pr_number/comments" --paginate \
  | jq -s 'add // []' > "$out_dir/comments.json"; then
  printf '[]\n' > "$out_dir/comments.json"
fi

# Linked issues referenced from the PR body
jq -r '.body // ""' "$out_dir/pr.json" \
  | grep -oiE '(fixes|closes|resolves)\s+#[0-9]+' \
  | grep -oE '[0-9]+$' \
  | sort -u \
  | while IFS= read -r issue_number; do
      gh api "repos/$repo/issues/$issue_number" > "$out_dir/issue-${issue_number}.json" || true
    done || true

cat > "$out_dir/README.md" <<MANIFEST
# PR Context

Pre-fetched PR data for $repo PR #$pr_number.

| File | Description |
| --- | --- |
| pr.json | PR metadata: title, body, author, base/head refs, SHA, mergeability, size |
| pr.diff | Full unified diff of the PR |
| files.json | Changed files with status, additions, deletions, and patch |
| diffs/<path>.diff | Per-file diffs with commentable right-side line numbers |
| file_order_az.txt | Changed files sorted alphabetically |
| file_order_za.txt | Changed files sorted reverse-alphabetically |
| file_order_largest.txt | Changed files sorted by diff size descending |
| pr-size.txt | Summary size metrics for review fan-out |
| reviews.json | Prior review submissions |
| review_threads.json | All review threads with resolution state |
| unresolved_threads.json | Unresolved review threads |
| resolved_threads.json | Resolved review threads |
| outdated_threads.json | Outdated review threads |
| threads/<path>.json | Per-file review threads |
| comments.json | PR discussion comments |
| issue-{N}.json | Linked issue details referenced by the PR body |
MANIFEST

echo "$out_dir"