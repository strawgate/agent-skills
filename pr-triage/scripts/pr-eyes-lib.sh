#!/usr/bin/env bash

set -euo pipefail

require_numeric_pr() {
  local pr_number="$1"
  if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "error: PR_NUMBER must be numeric (got '$pr_number')" >&2
    exit 1
  fi
}

gh_login() {
  gh api user --jq '.login'
}

fetch_issue_reactions() {
  local repo="$1"
  local pr_number="$2"
  gh api "repos/$repo/issues/$pr_number/reactions" --paginate
}

my_eyes_reaction_ids() {
  local reactions_json="$1"
  local login="$2"
  printf '%s\n' "$reactions_json" | jq -r \
    --arg login "$login" \
    '.[] | select(.user.login == $login and .content == "eyes") | .id'
}

other_human_eyes_markers() {
  local reactions_json="$1"
  local login="$2"
  printf '%s\n' "$reactions_json" | jq -r \
    --arg login "$login" \
    '.[] | select(.user.login != $login and .content == "eyes" and (.user.login | endswith("[bot]") | not)) | .user.login' \
    | sort -u
}
