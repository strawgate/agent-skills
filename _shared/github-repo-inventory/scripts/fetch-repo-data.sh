#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 OWNER/REPO [OUT_DIR]" >&2
  exit 1
fi

repo="$1"
out_dir="${2:-/tmp/issue-organizer/${repo//\//__}}"

mkdir -p "$out_dir"

write_record_files() {
  local input_json="$1"
  local kind="$2"
  local state="$3"
  local records_dir="$4"
  local index_file="$5"

  mkdir -p "$records_dir"

  python - "$input_json" "$kind" "$state" "$records_dir" "$index_file" <<'PY'
import json
import re
import sys
from pathlib import Path

input_json, kind, state, records_dir, index_file = sys.argv[1:]
records = json.loads(Path(input_json).read_text())
records_path = Path(records_dir)
records_path.mkdir(parents=True, exist_ok=True)

def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    slug = re.sub(r"-+", "-", slug)
    slug = slug[:80].rstrip("-")
    return slug or "untitled"

index_lines = []
for record in sorted(records, key=lambda item: int(item["number"])):
    number = int(record["number"])
    title = (record.get("title") or "").strip()
    index_prefix = f"[{state}] " if kind == "pr" else ""
    index_lines.append(f"{index_prefix}#{number} {title}".rstrip())

    output = records_path / f"{number:05d}-{slugify(title)}.txt"
    labels = ", ".join(
        label.get("name", "")
        for label in record.get("labels", [])
        if isinstance(label, dict) and label.get("name")
    )
    assignees = ", ".join(
        assignee.get("login", "")
        for assignee in record.get("assignees", [])
        if isinstance(assignee, dict) and assignee.get("login")
    )
    milestone = record.get("milestone")

    lines = [
        f"kind: {kind}",
        f"state: {state}",
        f"number: {number}",
        f"title: {title}",
        f"url: {record.get('html_url', '')}",
    ]

    if record.get("created_at"):
        lines.append(f"created_at: {record['created_at']}")
    if record.get("updated_at"):
        lines.append(f"updated_at: {record['updated_at']}")
    if "draft" in record:
        lines.append(f"draft: {record.get('draft')}")
    if record.get("merged_at"):
        lines.append(f"merged_at: {record['merged_at']}")
    if labels:
        lines.append(f"labels: {labels}")
    if assignees:
        lines.append(f"assignees: {assignees}")
    if isinstance(milestone, dict) and milestone.get("title"):
        lines.append(f"milestone: {milestone['title']}")
    if record.get("head"):
        lines.append(f"head: {record['head']}")
    if record.get("base"):
        lines.append(f"base: {record['base']}")

    lines.append("")
    lines.append("body:")
    body = record.get("body") or ""
    if body:
        lines.extend(body.splitlines())
    else:
        lines.append("<empty>")
    lines.append("")

    output.write_text("\n".join(lines) + "\n")

Path(index_file).write_text("\n".join(index_lines) + ("\n" if index_lines else ""))
PY
}

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

rm -rf "$out_dir/issues" "$out_dir/prs"
mkdir -p "$out_dir/issues/open" "$out_dir/prs/open" "$out_dir/prs/merged" "$out_dir/prs/closed"

write_record_files "$out_dir/open-issues.json" issue open "$out_dir/issues/open" "$out_dir/issue-titles.txt"
write_record_files "$out_dir/open-prs.json" pr open "$out_dir/prs/open" "$out_dir/pr-titles-open.txt"
write_record_files "$out_dir/merged-prs.json" pr merged "$out_dir/prs/merged" "$out_dir/pr-titles-merged.txt"
write_record_files "$out_dir/closed-prs.json" pr closed "$out_dir/prs/closed" "$out_dir/pr-titles-closed.txt"

cat \
  "$out_dir/pr-titles-open.txt" \
  "$out_dir/pr-titles-merged.txt" \
  "$out_dir/pr-titles-closed.txt" \
  > "$out_dir/pr-titles.txt"

gh api "repos/$repo" > "$out_dir/repo.json"
gh label list --repo "$repo" --limit 500 --json name,description,color > "$out_dir/labels.json"

{
  echo "repo=$repo"
  echo "out_dir=$out_dir"
  echo "open_issues=$(jq length "$out_dir/open-issues.json")"
  echo "open_prs=$(jq length "$out_dir/open-prs.json")"
  echo "merged_prs=$(jq length "$out_dir/merged-prs.json")"
  echo "closed_unmerged_prs=$(jq length "$out_dir/closed-prs.json")"
  echo "issue_titles=$out_dir/issue-titles.txt"
  echo "pr_titles=$out_dir/pr-titles.txt"
  echo "issue_files=$out_dir/issues/open"
  echo "pr_files_open=$out_dir/prs/open"
  echo "pr_files_merged=$out_dir/prs/merged"
  echo "pr_files_closed=$out_dir/prs/closed"
} > "$out_dir/summary.txt"

echo "$out_dir"
