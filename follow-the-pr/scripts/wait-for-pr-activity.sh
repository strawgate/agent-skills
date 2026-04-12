#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<USAGE >&2
usage: $0 OWNER/REPO PR_NUMBER [--interval SECONDS] [--state-dir DIR] [--timeout SECONDS] [--once]
       $0 PR_URL [--interval SECONDS] [--state-dir DIR] [--timeout SECONDS] [--once]

Poll a PR until actionable activity occurs, then emit a JSON summary.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

parse_target() {
  local first="$1"
  if [[ "$first" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)$ ]]; then
    TARGET_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    TARGET_PR="${BASH_REMATCH[3]}"
    return
  fi

  if [[ $# -lt 2 ]]; then
    usage
    exit 1
  fi

  TARGET_REPO="$1"
  TARGET_PR="$2"
}

normalize_check_rollup() {
  jq -c '
    def norm_check:
      if .__typename == "CheckRun" then
        {
          kind: "check",
          name: (.name // ""),
          workflowName: (.workflowName // ""),
          status: (.status // ""),
          conclusion: (.conclusion // "")
        }
      else
        {
          kind: "status",
          name: (.context // ""),
          workflowName: "",
          status: "COMPLETED",
          conclusion: (.state // "")
        }
      end;
    [.[]? | norm_check] | sort_by(.name, .workflowName, .kind)
  '
}

collect_snapshot() {
  local repo="$1"
  local pr="$2"
  local owner="${repo%/*}"
  local repo_name="${repo#*/}"

  local pr_json comments_json reviews_json threads_json checks_json
  pr_json="$(gh pr view "$pr" --repo "$repo" --json number,title,url,state,isDraft,mergeable,reviewDecision,baseRefName,headRefName,headRefOid,statusCheckRollup)"
  comments_json="$(gh api "repos/$repo/issues/$pr/comments" --paginate | jq -s 'add // [] | map({id, author: .user.login, createdAt: .created_at, updatedAt: .updated_at})')"
  reviews_json="$(gh api "repos/$repo/pulls/$pr/reviews" --paginate | jq -s 'add // [] | map({id, author: .user.login, state, submittedAt: .submitted_at, commitId: .commit_id})')"
  threads_json="$(gh api graphql --paginate \
    -f query='query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              isOutdated
              path
              line
              comments(first: 1) {
                nodes {
                  author { login }
                  body
                }
              }
            }
          }
        }
      }
    }' \
    -F owner="$owner" -F repo="$repo_name" -F number="$pr" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes' | jq -s 'add // [] | map({id, isResolved, isOutdated, path: (.path // ""), line: (.line // 0), author: (.comments.nodes[0].author.login // ""), body: (.comments.nodes[0].body // "")})')"
  checks_json="$(jq -c '.statusCheckRollup // []' <<<"$pr_json" | normalize_check_rollup)"

  jq -n \
    --arg repo "$repo" \
    --argjson pr "$pr_json" \
    --argjson comments "$comments_json" \
    --argjson reviews "$reviews_json" \
    --argjson threads "$threads_json" \
    --argjson checks "$checks_json" \
    --argjson nonblocking "$NONBLOCKING_CHECKS_JSON" '
      def upper: ascii_upcase;
      def is_nonblocking($names; $name): any($names[]; . == $name);
      def is_blocking_failure($names):
        if is_nonblocking($names; .name) then false
        elif .kind == "check" then (.conclusion | upper | IN("FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "CANCELLED"))
        else (.conclusion | upper | IN("ERROR", "FAILURE"))
        end;
      def is_blocking_pending($names):
        if is_nonblocking($names; .name) then false
        elif .kind == "check" then (.status | upper) != "COMPLETED"
        else (.conclusion | upper | IN("EXPECTED", "PENDING"))
        end;
      ($threads | map(select(.isResolved | not)) | sort_by(.id)) as $unresolved
      | ($checks | map(select(is_blocking_failure($nonblocking)))) as $blocking_failures
      | ($checks | map(select(is_blocking_pending($nonblocking)))) as $blocking_pending
      | {
          repo: $repo,
          pr: {
            number: $pr.number,
            title: $pr.title,
            url: $pr.url,
            state: $pr.state,
            isDraft: $pr.isDraft,
            mergeable: $pr.mergeable,
            reviewDecision: ($pr.reviewDecision // ""),
            baseRefName: $pr.baseRefName,
            headRefName: $pr.headRefName,
            headRefOid: $pr.headRefOid
          },
          comments: {
            count: ($comments | length),
            latestId: (($comments | map(.id) | max) // 0),
            ids: ($comments | map(.id) | sort)
          },
          reviews: {
            count: ($reviews | length),
            latestId: (($reviews | map(.id) | max) // 0),
            ids: ($reviews | map(.id) | sort),
            latestStates: ($reviews | map(.state) | unique | sort)
          },
          unresolvedThreads: {
            count: ($unresolved | length),
            ids: ($unresolved | map(.id)),
            items: $unresolved
          },
          checks: {
            items: $checks,
            blockingFailures: $blocking_failures,
            blockingPending: $blocking_pending,
            nonblockingIssues: ($checks | map(select(is_nonblocking($nonblocking; .name) and ((.kind == "check" and ((.status | upper) != "COMPLETED" or (.conclusion | upper) != "SUCCESS")) or (.kind == "status" and (.conclusion | upper) != "SUCCESS")))))
          },
          mergeReadyRelaxed: (
            $pr.state == "OPEN"
            and ($pr.mergeable == "MERGEABLE")
            and (($unresolved | length) == 0)
            and (($blocking_failures | length) == 0)
            and (($blocking_pending | length) == 0)
          )
        }
    '
}

json_array_from_csv() {
  local csv="$1"
  python3 - <<'PY' "$csv"
import json, sys
items = [item.strip() for item in sys.argv[1].split(',') if item.strip()]
print(json.dumps(items))
PY
}

emit_summary() {
  local activation="$1"
  local reasons_json="$2"
  local snapshot_file="$3"
  local state_dir="$4"
  local context_dir="$5"

  jq -n \
    --argjson activation "$activation" \
    --argjson reasons "$reasons_json" \
    --arg state_dir "$state_dir" \
    --arg context_dir "$context_dir" \
    --slurpfile snapshot "$snapshot_file" '
      {
        activation: $activation,
        reasons: $reasons,
        stateDir: $state_dir,
        contextDir: $context_dir,
        pr: $snapshot[0].pr,
        unresolvedThreads: $snapshot[0].unresolvedThreads,
        checks: $snapshot[0].checks,
        mergeReadyRelaxed: $snapshot[0].mergeReadyRelaxed
      }
    '
}

maybe_refresh_context() {
  local repo="$1"
  local pr="$2"
  local context_dir="$3"
  local script_dir fetch_script
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fetch_script="$script_dir/../../pr-triage/scripts/fetch-pr-context.sh"

  if [[ -x "$fetch_script" ]]; then
    mkdir -p "$context_dir"
    "$fetch_script" "$repo" "$pr" "$context_dir" >/dev/null
  fi
}

compare_snapshots() {
  local previous="$1"
  local current="$2"
  local reasons=()

  local prev_state cur_state prev_head cur_head prev_comments cur_comments prev_reviews cur_reviews prev_threads cur_threads prev_merge_ready cur_merge_ready prev_review_decision cur_review_decision prev_checks cur_checks
  prev_state="$(jq -r '.pr.state' "$previous")"
  cur_state="$(jq -r '.pr.state' "$current")"
  prev_head="$(jq -r '.pr.headRefOid' "$previous")"
  cur_head="$(jq -r '.pr.headRefOid' "$current")"
  prev_comments="$(jq -c '.comments.ids' "$previous")"
  cur_comments="$(jq -c '.comments.ids' "$current")"
  prev_reviews="$(jq -c '.reviews.ids' "$previous")"
  cur_reviews="$(jq -c '.reviews.ids' "$current")"
  prev_threads="$(jq -c '.unresolvedThreads.ids' "$previous")"
  cur_threads="$(jq -c '.unresolvedThreads.ids' "$current")"
  prev_merge_ready="$(jq -r '.mergeReadyRelaxed' "$previous")"
  cur_merge_ready="$(jq -r '.mergeReadyRelaxed' "$current")"
  prev_review_decision="$(jq -r '.pr.reviewDecision' "$previous")"
  cur_review_decision="$(jq -r '.pr.reviewDecision' "$current")"
  prev_checks="$(jq -c '.checks.items' "$previous")"
  cur_checks="$(jq -c '.checks.items' "$current")"

  if [[ "$cur_state" != "OPEN" ]]; then
    reasons+=("pr_closed")
  else
    if [[ "$prev_head" != "$cur_head" ]]; then
      reasons+=("head_changed")
    fi
    if [[ "$prev_comments" != "$cur_comments" ]]; then
      reasons+=("new_comment")
    fi
    if [[ "$prev_reviews" != "$cur_reviews" ]]; then
      reasons+=("new_review")
    fi
    if [[ "$prev_threads" != "$cur_threads" ]]; then
      reasons+=("unresolved_threads_changed")
    fi
    if [[ "$prev_review_decision" != "$cur_review_decision" && "$cur_review_decision" == "CHANGES_REQUESTED" ]]; then
      reasons+=("review_requested")
    fi
    if [[ "$prev_merge_ready" != "true" && "$cur_merge_ready" == "true" ]]; then
      reasons+=("merge_ready")
    fi

    local cur_blocking_failures prev_blocking_failures
    prev_blocking_failures="$(jq -c '.checks.blockingFailures' "$previous")"
    cur_blocking_failures="$(jq -c '.checks.blockingFailures' "$current")"
    if [[ "$prev_blocking_failures" != "$cur_blocking_failures" && "$cur_blocking_failures" != '[]' ]]; then
      reasons+=("blocking_checks_changed")
    fi

    if [[ ${#reasons[@]} -eq 0 && "$prev_checks" != "$cur_checks" ]]; then
      reasons+=("checks_changed")
    fi
  fi

  printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .
}

initial_activation_reasons() {
  local current="$1"
  local reasons=()

  if [[ "$(jq -r '.pr.state' "$current")" != "OPEN" ]]; then
    reasons+=("pr_closed")
  else
    if [[ "$(jq -r '.mergeReadyRelaxed' "$current")" == "true" ]]; then
      reasons+=("merge_ready")
    fi
    if [[ "$(jq -r '.pr.reviewDecision' "$current")" == "CHANGES_REQUESTED" ]]; then
      reasons+=("review_requested")
    fi
    if [[ "$(jq -r '.unresolvedThreads.count' "$current")" != "0" ]]; then
      reasons+=("unresolved_threads_changed")
    fi
    if [[ "$(jq -c '.checks.blockingFailures' "$current")" != '[]' ]]; then
      reasons+=("blocking_checks_changed")
    fi
  fi

  printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .
}

require_cmd gh
require_cmd jq
require_cmd python3

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TARGET_REPO=""
TARGET_PR=""
INTERVAL="${FOLLOW_PR_POLL_SECONDS:-300}"
STATE_DIR=""
TIMEOUT="0"
ONCE=0

first_arg="$1"
if [[ "$first_arg" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+$ ]]; then
  parse_target "$first_arg"
  shift 1
else
  if [[ $# -lt 2 ]]; then
    usage
    exit 1
  fi
  parse_target "$1" "$2"
  shift 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --once)
      ONCE=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

STATE_DIR="${STATE_DIR:-/tmp/follow-pr/${TARGET_REPO//\//__}/pr-${TARGET_PR}}"
CONTEXT_DIR="$STATE_DIR/context"
SNAPSHOT_FILE="$STATE_DIR/snapshot.json"
mkdir -p "$STATE_DIR"

NONBLOCKING_CHECKS_JSON="$(json_array_from_csv "${FOLLOW_PR_NONBLOCKING_CHECKS:-Code Coverage,Kani proofs}")"

start_ts="$(date +%s)"

echo "follow-the-pr: watching $TARGET_REPO#$TARGET_PR every ${INTERVAL}s" >&2

tmp_current="$(mktemp)"
trap 'rm -f "$tmp_current"' EXIT
collect_snapshot "$TARGET_REPO" "$TARGET_PR" > "$tmp_current"

if [[ ! -f "$SNAPSHOT_FILE" ]]; then
  mv "$tmp_current" "$SNAPSHOT_FILE"
  tmp_current="$(mktemp)"
  initial_reasons="$(initial_activation_reasons "$SNAPSHOT_FILE")"
  if [[ "$initial_reasons" != '[]' ]]; then
    maybe_refresh_context "$TARGET_REPO" "$TARGET_PR" "$CONTEXT_DIR"
    emit_summary true "$initial_reasons" "$SNAPSHOT_FILE" "$STATE_DIR" "$CONTEXT_DIR"
    exit 0
  fi
  if [[ "$ONCE" -eq 1 ]]; then
    emit_summary false '[]' "$SNAPSHOT_FILE" "$STATE_DIR" "$CONTEXT_DIR"
    exit 0
  fi
else
  if [[ "$ONCE" -eq 1 ]]; then
    mv "$tmp_current" "$SNAPSHOT_FILE"
    emit_summary false '[]' "$SNAPSHOT_FILE" "$STATE_DIR" "$CONTEXT_DIR"
    exit 0
  fi
fi

while true; do
  if [[ "$TIMEOUT" != "0" ]]; then
    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= TIMEOUT )); then
      emit_summary false '[]' "$SNAPSHOT_FILE" "$STATE_DIR" "$CONTEXT_DIR"
      exit 2
    fi
  fi

  sleep "$INTERVAL"
  collect_snapshot "$TARGET_REPO" "$TARGET_PR" > "$tmp_current"
  reasons_json="$(compare_snapshots "$SNAPSHOT_FILE" "$tmp_current")"
  if [[ "$reasons_json" != '[]' ]]; then
    mv "$tmp_current" "$SNAPSHOT_FILE"
    tmp_current="$(mktemp)"
    maybe_refresh_context "$TARGET_REPO" "$TARGET_PR" "$CONTEXT_DIR"
    echo "follow-the-pr: activation for $TARGET_REPO#$TARGET_PR: $(jq -r 'join(",")' <<<"$reasons_json")" >&2
    emit_summary true "$reasons_json" "$SNAPSHOT_FILE" "$STATE_DIR" "$CONTEXT_DIR"
    exit 0
  fi
  echo "follow-the-pr: no change for $TARGET_REPO#$TARGET_PR" >&2

done
