#!/usr/bin/env bash
#
# Archive (delete) completed Jules sessions whose PRs are merged or closed.
# Also archives FAILED and COMPLETED sessions with no PR that are older than
# the specified number of days (default: 7).
#
# Usage: archive.sh [--dry-run] [--no-pr-days N]
#
# Options:
#   --dry-run        Show what would be archived without actually deleting
#   --no-pr-days N   Archive sessions with no PR older than N days (default: 7)
#
# Only deletes sessions where:
#   1. State is COMPLETED or FAILED
#   2. Either: the PR is MERGED or CLOSED
#      Or:     there is no PR and the session is older than --no-pr-days days
#
# Requires JULES_API_KEY environment variable.
#
set -euo pipefail

DRY_RUN=false
NO_PR_DAYS=7

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --no-pr-days) NO_PR_DAYS="${2:?--no-pr-days requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "${JULES_API_KEY:-}" ]; then
    echo "Error: JULES_API_KEY not set. Get your key from https://jules.google.com/settings#api"
    exit 1
fi

BASE_URL="https://jules.googleapis.com/v1alpha"

if $DRY_RUN; then
    echo "[DRY RUN] No sessions will actually be deleted."
fi

echo "Fetching sessions..."
SESSIONS=$(curl -s \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${BASE_URL}/sessions?pageSize=100")

ARCHIVABLE=$(echo "$SESSIONS" | jq -r '
    .sessions[]?
    | select(.state == "COMPLETED" or .state == "FAILED")
    | .name' 2>/dev/null)

if [ -z "$ARCHIVABLE" ]; then
    echo "No completed/failed sessions found."
    exit 0
fi

ARCHIVED=0
SKIPPED_OPEN=0
SKIPPED_UNKNOWN=0
SKIPPED_RECENT=0

NOW=$(date +%s)
CUTOFF_SECONDS=$((NO_PR_DAYS * 86400))

for SESSION_NAME in $ARCHIVABLE; do
    SESSION_ID=$(echo "$SESSION_NAME" | sed 's|sessions/||')

    TITLE=$(echo "$SESSIONS" | jq -r --arg name "$SESSION_NAME" \
        '.sessions[]? | select(.name == $name) | .title // "untitled"' 2>/dev/null)
    STATE=$(echo "$SESSIONS" | jq -r --arg name "$SESSION_NAME" \
        '.sessions[]? | select(.name == $name) | .state' 2>/dev/null)
    UPDATE_TIME=$(echo "$SESSIONS" | jq -r --arg name "$SESSION_NAME" \
        '.sessions[]? | select(.name == $name) | .updateTime // ""' 2>/dev/null)

    # Get session details to find the PR URL
    SESSION_DETAIL=$(curl -s \
        -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
        "${BASE_URL}/sessions/${SESSION_ID}")

    PR_URL=$(echo "$SESSION_DETAIL" | jq -r \
        '.outputs[]?.pullRequest?.url // empty' 2>/dev/null | head -1)

    if [ -n "$PR_URL" ]; then
        PR_NUMBER=$(echo "$PR_URL" | grep -o '[0-9]*$')
        PR_REPO=$(echo "$PR_URL" | sed 's|https://github.com/||;s|/pull/.*||')

        PR_STATE=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")

        if [ "$PR_STATE" = "OPEN" ]; then
            SKIPPED_OPEN=$((SKIPPED_OPEN + 1))
            continue
        fi

        if [ "$PR_STATE" = "UNKNOWN" ]; then
            echo "  Skipping #${SESSION_ID}: cannot determine PR state for $PR_URL"
            SKIPPED_UNKNOWN=$((SKIPPED_UNKNOWN + 1))
            continue
        fi

        echo "  Archiving [${STATE}] ${SESSION_ID}: ${TITLE}"
        echo "    PR: ${PR_URL} (${PR_STATE})"
    else
        # No PR — only archive if old enough
        if [ -n "$UPDATE_TIME" ]; then
            # Parse ISO 8601 timestamp
            UPDATE_EPOCH=$(date -d "$UPDATE_TIME" +%s 2>/dev/null || \
                           date -j -f "%Y-%m-%dT%H:%M:%S" "${UPDATE_TIME%%.*}" +%s 2>/dev/null || echo "0")
            AGE_SECONDS=$(( NOW - UPDATE_EPOCH ))
            if [ "$AGE_SECONDS" -lt "$CUTOFF_SECONDS" ]; then
                SKIPPED_RECENT=$((SKIPPED_RECENT + 1))
                continue
            fi
        fi
        echo "  Archiving [${STATE}] ${SESSION_ID}: ${TITLE} (no PR, age threshold met)"
    fi

    if $DRY_RUN; then
        echo "    [DRY RUN] Would delete session ${SESSION_ID}"
    else
        curl -s -X DELETE \
            -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
            "${BASE_URL}/sessions/${SESSION_ID}" > /dev/null
        echo "    Deleted."
    fi

    ARCHIVED=$((ARCHIVED + 1))
done

echo ""
echo "Done. Archived: ${ARCHIVED}, Skipped (PR open): ${SKIPPED_OPEN}, Skipped (unknown PR state): ${SKIPPED_UNKNOWN}, Skipped (no PR, recent): ${SKIPPED_RECENT}"
