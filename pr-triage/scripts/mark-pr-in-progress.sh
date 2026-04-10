#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/pr-eyes-lib.sh"

usage() {
  cat <<'EOF'
Usage: mark-pr-in-progress.sh [--allow-shared] OWNER/REPO PR_NUMBER

Adds :eyes: reaction for the authenticated user on a PR to mark active ownership.

By default, exits non-zero if someone else already marked the PR with :eyes:.
Use --allow-shared to mark anyway.
EOF
}

allow_shared="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --allow-shared)
      allow_shared="true"
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

repo="$1"
pr_number="$2"
require_numeric_pr "$pr_number"

login="$(gh_login)"
reactions_json="$(fetch_issue_reactions "$repo" "$pr_number")"

existing_id="$(my_eyes_reaction_ids "$reactions_json" "$login" | head -n1 || true)"

if [[ -n "$existing_id" ]]; then
  echo "already marked: $repo#$pr_number by @$login (:eyes: reaction id $existing_id)"
  exit 0
fi

other_markers=()
while IFS= read -r marker; do
  [[ -z "$marker" ]] && continue
  other_markers+=("$marker")
done < <(
  other_human_eyes_markers "$reactions_json" "$login"
)

if [[ ${#other_markers[@]} -gt 0 && "$allow_shared" != "true" ]]; then
  echo "warning: $repo#$pr_number already marked by: ${other_markers[*]}" >&2
  echo "hint: rerun with --allow-shared if you intentionally want shared ownership." >&2
  exit 2
fi

if [[ ${#other_markers[@]} -gt 0 ]]; then
  echo "warning: $repo#$pr_number already marked by: ${other_markers[*]} (continuing due to --allow-shared)" >&2
fi

gh api --method POST "repos/$repo/issues/$pr_number/reactions" -f content='eyes' >/dev/null
echo "marked: $repo#$pr_number by @$login (:eyes: added)"
