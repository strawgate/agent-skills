#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<USAGE
usage:
  $0
  $0 PR_NUMBER
  $0 OWNER/REPO PR_NUMBER [OUT_DIR]

examples:
  $0
  $0 1733
  $0 strawgate/memagent 1733
  $0 strawgate/memagent 1733 /tmp/pr-context/memagent-1733
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 1
  fi
}

resolve_repo_from_cwd() {
  gh repo view --json nameWithOwner --jq '.nameWithOwner'
}

resolve_pr_from_branch() {
  local repo="$1"
  gh pr view --repo "$repo" --json number --jq '.number'
}

repo=""
pr_number=""
out_dir=""

case "${#@}" in
  0)
    repo="$(resolve_repo_from_cwd)"
    pr_number="$(resolve_pr_from_branch "$repo")"
    ;;
  1)
    if [[ "$1" =~ ^[0-9]+$ ]]; then
      repo="$(resolve_repo_from_cwd)"
      pr_number="$1"
    else
      usage
      exit 1
    fi
    ;;
  2|3)
    repo="$1"
    pr_number="$2"
    out_dir="${3:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac

if [[ ! "$repo" =~ .+/.+ ]]; then
  echo "invalid repo '$repo' (expected OWNER/REPO)" >&2
  exit 1
fi
if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "invalid PR number '$pr_number'" >&2
  exit 1
fi

require_cmd gh
require_cmd jq

gh auth status >/dev/null

if [[ -z "$out_dir" ]]; then
  out_dir="/tmp/pr-context/${repo//\//__}/pr-${pr_number}"
fi

mkdir -p "$out_dir" "$out_dir/diffs" "$out_dir/threads"

owner="${repo%/*}"
repo_name="${repo#*/}"

gh pr view "$pr_number" --repo "$repo" \
  --json number,title,body,url,state,isDraft,mergeable,baseRefName,headRefName,headRefOid,author,additions,deletions,changedFiles,commits,createdAt,updatedAt \
  > "$out_dir/pr.json"

gh api "repos/$repo/pulls/$pr_number" > "$out_dir/pull.json"

if ! gh pr diff "$pr_number" --repo "$repo" > "$out_dir/pr.diff"; then
  echo "warning: failed to fetch full PR diff" >&2
  : > "$out_dir/pr.diff"
fi

gh api "repos/$repo/pulls/$pr_number/files" --paginate | jq -s 'add // []' > "$out_dir/files.json"

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

jq -r '[.[] | .filename] | sort | .[]' "$out_dir/files.json" > "$out_dir/file_order_az.txt"
jq -r '[.[] | {filename, size: ((.additions // 0) + (.deletions // 0))}] | sort_by(-.size) | .[].filename' "$out_dir/files.json" > "$out_dir/file_order_largest.txt"

if ! gh api "repos/$repo/issues/$pr_number/comments" --paginate | jq -s 'add // []' > "$out_dir/comments.json"; then
  printf '[]\n' > "$out_dir/comments.json"
fi

if ! gh api "repos/$repo/pulls/$pr_number/reviews" --paginate | jq -s 'add // []' > "$out_dir/reviews.json"; then
  printf '[]\n' > "$out_dir/reviews.json"
fi

if ! gh api "repos/$repo/pulls/$pr_number/comments" --paginate | jq -s 'add // []' > "$out_dir/review_comments.json"; then
  printf '[]\n' > "$out_dir/review_comments.json"
fi

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

if ! gh api "repos/$repo/pulls/$pr_number/commits" --paginate | jq -s 'add // []' > "$out_dir/commits.json"; then
  printf '[]\n' > "$out_dir/commits.json"
fi

if ! gh pr checks "$pr_number" --repo "$repo" \
  --json name,state,bucket,link,workflow,startedAt,completedAt > "$out_dir/checks.json"; then
  printf '[]\n' > "$out_dir/checks.json"
fi

jq -n \
  --argjson files "$(jq 'length' "$out_dir/files.json")" \
  --argjson diff_lines "$(wc -l < "$out_dir/pr.diff" | tr -d ' ')" \
  --argjson comments "$(jq 'length' "$out_dir/comments.json")" \
  --argjson reviews "$(jq 'length' "$out_dir/reviews.json")" \
  --argjson review_comments "$(jq 'length' "$out_dir/review_comments.json")" \
  --argjson threads "$(jq 'length' "$out_dir/review_threads.json")" \
  --argjson unresolved_threads "$(jq 'length' "$out_dir/unresolved_threads.json")" \
  --argjson commits "$(jq 'length' "$out_dir/commits.json")" \
  --argjson checks_total "$(jq 'length' "$out_dir/checks.json")" \
  --argjson checks_failed "$(jq '[.[] | select(.state=="FAILURE" or .state=="ERROR")] | length' "$out_dir/checks.json")" \
  '{files:$files,diff_lines:$diff_lines,comments:$comments,reviews:$reviews,review_comments:$review_comments,threads:$threads,unresolved_threads:$unresolved_threads,commits:$commits,checks_total:$checks_total,checks_failed:$checks_failed}' \
  > "$out_dir/summary.json"

cat > "$out_dir/README.md" <<MANIFEST
# PR Context Bundle

Repo: $repo
PR: #$pr_number

## Included Data
- pr.json: PR metadata (title/body/base/head/mergeability/size)
- pull.json: raw REST pull object (requested reviewers, labels, etc.)
- pr.diff: full unified diff
- files.json: changed files metadata + patch snippets
- diffs/<path>.diff: per-file patches with right-side commentable line numbers
- comments.json: top-level PR conversation comments
- reviews.json: review submissions (APPROVED / CHANGES_REQUESTED / COMMENTED)
- review_comments.json: inline PR review comments (REST)
- review_threads.json: GraphQL review threads with resolved/outdated state
- unresolved_threads.json: unresolved review threads
- resolved_threads.json: resolved review threads
- outdated_threads.json: outdated review threads
- threads/<path>.json: per-file grouped review threads
- commits.json: commits in the PR
- checks.json: check-run snapshot from gh pr checks
- summary.json: quick counts for triage
MANIFEST

echo "$out_dir"
