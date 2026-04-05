#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 OWNER/REPO [OUT_DIR]" >&2
  exit 1
fi

repo="$1"
out_dir="${2:-/tmp/issue-organizer/${repo//\//__}}"

mkdir -p "$out_dir"

fetch_all() {
  local kind="$1"
  local state="$2"
  local fields="$3"
  local output="$4"
  local page=1
  local tmp

  tmp="$(mktemp)"
  printf '[]\n' > "$tmp"

  while true; do
    local batch
    if [[ "$kind" == "issues" ]]; then
      batch="$(gh api "repos/$repo/issues?state=$state&per_page=100&page=$page&direction=asc" \
        --jq '[.[] | select(.pull_request == null) | {number, title, body, state, labels, assignees, milestone, created_at, updated_at, comments, html_url}]')"
    else
      batch="$(gh api "repos/$repo/pulls?state=$state&per_page=100&page=$page&direction=asc" \
        --jq "[.[] | {$fields}]")"
    fi

    if [[ "$(jq length <<<"$batch")" -eq 0 ]]; then
      break
    fi

    jq -s '.[0] + .[1]' "$tmp" <(printf '%s\n' "$batch") > "${tmp}.next"
    mv "${tmp}.next" "$tmp"
    page=$((page + 1))
  done

  mv "$tmp" "$output"
}

fetch_all issues open '' "$out_dir/open-issues.json"
fetch_all pulls open 'number, title, body, state, draft, merged_at, created_at, updated_at, head: .head.ref, base: .base.ref, labels, html_url' "$out_dir/open-prs.json"
fetch_all pulls closed 'number, title, body, state, draft, merged_at, created_at, updated_at, head: .head.ref, base: .base.ref, labels, html_url' "$out_dir/all-closed-prs.json"

jq '[.[] | select(.merged_at != null)]' "$out_dir/all-closed-prs.json" > "$out_dir/merged-prs.json"
jq '[.[] | select(.merged_at == null)]' "$out_dir/all-closed-prs.json" > "$out_dir/closed-prs.json"
rm -f "$out_dir/all-closed-prs.json"

gh api "repos/$repo" > "$out_dir/repo.json"
gh label list --repo "$repo" --limit 500 --json name,description,color > "$out_dir/labels.json"

{
  echo "repo=$repo"
  echo "out_dir=$out_dir"
  echo "open_issues=$(jq length "$out_dir/open-issues.json")"
  echo "open_prs=$(jq length "$out_dir/open-prs.json")"
  echo "merged_prs=$(jq length "$out_dir/merged-prs.json")"
  echo "closed_unmerged_prs=$(jq length "$out_dir/closed-prs.json")"
} > "$out_dir/summary.txt"

echo "$out_dir"