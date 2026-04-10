#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/pr-eyes-lib.sh"

usage() {
  cat <<'EOF'
Usage: unmark-pr-in-progress.sh OWNER/REPO PR_NUMBER

Removes all :eyes: reactions added by the authenticated user on a PR.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

repo="$1"
pr_number="$2"
require_numeric_pr "$pr_number"
login="$(gh_login)"

reaction_ids=()
while IFS= read -r rid; do
  [[ -z "$rid" ]] && continue
  reaction_ids+=("$rid")
done < <(
  my_eyes_reaction_ids "$(fetch_issue_reactions "$repo" "$pr_number")" "$login"
)

if [[ ${#reaction_ids[@]} -eq 0 ]]; then
  echo "already unmarked: $repo#$pr_number by @$login (no :eyes: reactions found)"
  exit 0
fi

for reaction_id in "${reaction_ids[@]}"; do
  gh api --method DELETE "repos/$repo/issues/$pr_number/reactions/$reaction_id" >/dev/null
done

echo "unmarked: $repo#$pr_number by @$login (removed ${#reaction_ids[@]} :eyes: reaction(s))"
