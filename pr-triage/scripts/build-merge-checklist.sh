#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 BUNDLE_DIR [OUT_PREFIX]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

bundle_dir="$1"
out_prefix="${2:-$bundle_dir/merge-checklist}"
out_json="${out_prefix}.json"
out_md="${out_prefix}.md"
focus_files_out="${bundle_dir}/review-focus-files.txt"

for req in pr.json checks.json unresolved_threads.json files.json; do
  if [[ ! -f "$bundle_dir/$req" ]]; then
    echo "missing required file: $bundle_dir/$req" >&2
    exit 1
  fi
done

json_array_from_lines() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s '.'
}

failing_checks=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  failing_checks+=("$line")
done < <(
  jq -r '
    .[]
    | ((.state // "") | ascii_upcase) as $state
    | select($state == "FAILURE" or $state == "ERROR" or $state == "TIMED_OUT" or $state == "CANCELLED" or $state == "ACTION_REQUIRED")
    | (.name // .workflow // "unknown-check")
  ' "$bundle_dir/checks.json"
)

pending_checks=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pending_checks+=("$line")
done < <(
  jq -r '
    .[]
    | ((.state // "") | ascii_upcase) as $state
    | select($state == "PENDING" or $state == "QUEUED" or $state == "IN_PROGRESS" or $state == "WAITING" or $state == "REQUESTED")
    | (.name // .workflow // "unknown-check")
  ' "$bundle_dir/checks.json"
)

focus_files=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  focus_files+=("$line")
done < <(
  jq -r -n \
    --slurpfile unresolved "$bundle_dir/unresolved_threads.json" \
    --slurpfile review_comments "$bundle_dir/review_comments.json" \
    --slurpfile files "$bundle_dir/files.json" \
    '
    def clean: map(select(type == "string" and length > 0));
    (
      (($unresolved[0] // []) | map(.path // "") | clean) +
      (($review_comments[0] // []) | map(.path // "") | clean) +
      (($files[0] // []) | sort_by(-((.additions // 0) + (.deletions // 0))) | map(.filename // "") | clean)
    ) as $paths
    | reduce $paths[] as $p ([]; if index($p) then . else . + [$p] end)
    | .[:40]
    | .[]
    '
)

: > "$focus_files_out"
if [[ "${#focus_files[@]}" -gt 0 ]]; then
  printf '%s\n' "${focus_files[@]}" > "$focus_files_out"
fi

unresolved_threads="$(jq 'length' "$bundle_dir/unresolved_threads.json")"
checks_failing="${#failing_checks[@]}"
checks_pending="${#pending_checks[@]}"
checks_total="$(jq 'length' "$bundle_dir/checks.json")"

pr_state="$(jq -r '(.state // "UNKNOWN") | ascii_upcase' "$bundle_dir/pr.json")"
is_draft="$(jq -r '.isDraft // false' "$bundle_dir/pr.json")"
mergeable_state="$(jq -r '(.mergeable // "UNKNOWN") | ascii_upcase' "$bundle_dir/pr.json")"

has_merge_conflict="false"
if [[ "$mergeable_state" == "CONFLICTING" ]]; then
  has_merge_conflict="true"
fi

blockers=()
if [[ "$pr_state" != "OPEN" ]]; then
  blockers+=("pr-not-open")
fi
if [[ "$is_draft" == "true" ]]; then
  blockers+=("draft-pr")
fi
if [[ "$has_merge_conflict" == "true" ]]; then
  blockers+=("merge-conflict")
fi
if [[ "$unresolved_threads" -gt 0 ]]; then
  blockers+=("unaddressed-comments")
fi
if [[ "$checks_failing" -gt 0 ]]; then
  blockers+=("failing-checks")
fi
if [[ "$checks_pending" -gt 0 ]]; then
  blockers+=("pending-checks")
fi

merge_ready="true"
if [[ "${#blockers[@]}" -gt 0 ]]; then
  merge_ready="false"
fi

failing_checks_json="$(json_array_from_lines "${failing_checks[@]}")"
pending_checks_json="$(json_array_from_lines "${pending_checks[@]}")"
focus_files_json="$(json_array_from_lines "${focus_files[@]}")"
blockers_json="$(json_array_from_lines "${blockers[@]}")"

jq -n \
  --arg pr_state "$pr_state" \
  --arg mergeable_state "$mergeable_state" \
  --argjson is_draft "$is_draft" \
  --argjson has_merge_conflict "$has_merge_conflict" \
  --argjson unresolved_threads "$unresolved_threads" \
  --argjson checks_total "$checks_total" \
  --argjson checks_failing "$checks_failing" \
  --argjson checks_pending "$checks_pending" \
  --argjson merge_ready "$merge_ready" \
  --argjson blockers "$blockers_json" \
  --argjson failing_checks "$failing_checks_json" \
  --argjson pending_checks "$pending_checks_json" \
  --argjson review_focus_files "$focus_files_json" \
  '
  {
    merge_ready: $merge_ready,
    blockers: $blockers,
    checklist: {
      unaddressed_comments: $unresolved_threads,
      checks_failing: $checks_failing,
      checks_pending: $checks_pending,
      merge_conflict: $has_merge_conflict,
      draft_pr: $is_draft
    },
    pr_state: $pr_state,
    mergeable_state: $mergeable_state,
    checks_total: $checks_total,
    failing_checks: $failing_checks,
    pending_checks: $pending_checks,
    review_focus_files: $review_focus_files
  }
  ' > "$out_json"

{
  echo "# PR Merge Checklist"
  echo
  if [[ "$merge_ready" == "true" ]]; then
    echo "Mergeable: no blocking conditions detected."
  else
    echo "Blocked: merge-preventing conditions detected."
  fi
  echo
  echo "- [$( [[ "$unresolved_threads" -eq 0 ]] && echo 'x' || echo ' ' )] Unaddressed Comments: $unresolved_threads"
  echo "- [$( [[ "$checks_failing" -eq 0 ]] && echo 'x' || echo ' ' )] Checks Failing: $checks_failing"
  echo "- [$( [[ "$checks_pending" -eq 0 ]] && echo 'x' || echo ' ' )] Checks Pending: $checks_pending"
  echo "- [$( [[ "$has_merge_conflict" == "false" ]] && echo 'x' || echo ' ' )] Merge Conflict: $has_merge_conflict"
  echo "- [$( [[ "$is_draft" == "false" ]] && echo 'x' || echo ' ' )] Draft PR: $is_draft"
  echo
  if [[ "${#blockers[@]}" -gt 0 ]]; then
    echo "## Blocking Reasons"
    echo
    for b in "${blockers[@]}"; do
      echo "- $b"
    done
    echo
  fi

  if [[ "${#failing_checks[@]}" -gt 0 ]]; then
    echo "## Failing Checks"
    echo
    for c in "${failing_checks[@]}"; do
      echo "- $c"
    done
    echo
  fi

  if [[ "${#pending_checks[@]}" -gt 0 ]]; then
    echo "## Pending Checks"
    echo
    for c in "${pending_checks[@]}"; do
      echo "- $c"
    done
    echo
  fi

  echo "## Review Focus Files"
  echo
  if [[ "${#focus_files[@]}" -eq 0 ]]; then
    echo "- (none found)"
  else
    for f in "${focus_files[@]}"; do
      echo "- $f"
    done
  fi
} > "$out_md"

echo "$out_json"
echo "$out_md"
echo "$focus_files_out"
