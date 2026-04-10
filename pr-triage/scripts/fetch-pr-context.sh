#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 OWNER/REPO PR_NUMBER [OUT_DIR]" >&2
  exit 1
fi

repo="$1"
pr_number="$2"
out_dir="${3:-/tmp/pr-context/${repo//\//__}/pr-${pr_number}}"
script_dir="$(cd "$(dirname "$0")" && pwd)"

shared="$script_dir/../../_shared/github-pr-context/scripts/fetch-pr-context.sh"
checklist_builder="$script_dir/build-merge-checklist.sh"

if [[ ! -x "$shared" ]]; then
  echo "shared script not found or not executable: $shared" >&2
  exit 1
fi

bundle_dir="$("$shared" "$repo" "$pr_number" "$out_dir")"

if [[ -x "$checklist_builder" ]]; then
  "$checklist_builder" "$bundle_dir" >/dev/null
fi

echo "$bundle_dir"
