#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 OWNER/REPO PR_NUMBER [OUT_DIR]" >&2
  exit 1
fi

repo="$1"
pr_number="$2"
out_dir="${3:-/tmp/pr-context/${repo//\//__}/pr-${pr_number}}"

codex_home="${CODEX_HOME:-$HOME/.codex}"
shared="$codex_home/skills/_shared/github-pr-context/scripts/fetch-pr-context.sh"

if [[ ! -x "$shared" ]]; then
  echo "shared script not found or not executable: $shared" >&2
  exit 1
fi

exec "$shared" "$repo" "$pr_number" "$out_dir"
