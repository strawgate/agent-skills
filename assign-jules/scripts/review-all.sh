#!/usr/bin/env bash
#
# Find completed Jules sessions with OPEN pull requests that haven't been
# self-reviewed yet, and send the self-review prompt to each one.
#
# Usage: review-all.sh [OWNER/REPO]
#
# Only reviews sessions that:
#   1. Are in COMPLETED state
#   2. Have a pull request URL in their output
#   3. That PR is still OPEN (not merged or closed)
#   4. Haven't already been sent the self-review prompt
#
# Requires JULES_API_KEY environment variable.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../_shared/jules-api/jules-lib.sh"

REVIEW_PROMPT=$(cat "$SCRIPT_DIR/self-review-prompt.txt")
TRACKED_FILE="$SCRIPT_DIR/.reviewed-sessions"
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")}"

jules_require_key

touch "$TRACKED_FILE"

echo "Fetching sessions..."
ALL_SESSIONS=$(jules_list_all_sessions 100)

# Extract completed sessions with their details
COMPLETED=$(echo "$ALL_SESSIONS" | jq -r '.[]? | select(.state == "COMPLETED") | .name' 2>/dev/null)

if [ -z "$COMPLETED" ]; then
    echo "No completed sessions found."
    exit 0
fi

SKIPPED_REVIEWED=0
SKIPPED_NO_PR=0
SKIPPED_PR_NOT_OPEN=0
SENT=0

for SESSION_NAME in $COMPLETED; do
    SESSION_ID=$(echo "$SESSION_NAME" | sed 's|sessions/||')

    # Skip if already reviewed
    if grep -q "^${SESSION_ID}$" "$TRACKED_FILE" 2>/dev/null; then
        SKIPPED_REVIEWED=$((SKIPPED_REVIEWED + 1))
        continue
    fi

    TITLE=$(echo "$ALL_SESSIONS" | jq -r --arg name "$SESSION_NAME" \
        '.[]? | select(.name == $name) | .title // "untitled"' 2>/dev/null)

    # Get session details to find the PR URL
    SESSION_DETAIL=$(jules_get_session "$SESSION_ID")

    PR_URL=$(jules_extract_pr_url "$SESSION_DETAIL")

    if [ -z "$PR_URL" ]; then
        SKIPPED_NO_PR=$((SKIPPED_NO_PR + 1))
        continue
    fi

    # Check if the PR is still open using gh
    PR_NUMBER=$(echo "$PR_URL" | grep -o '[0-9]*$')
    PR_REPO=$(echo "$PR_URL" | sed 's|https://github.com/||;s|/pull/.*||')

    PR_STATE=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")

    if [ "$PR_STATE" != "OPEN" ]; then
        # PR is merged, closed, or we can't check — skip and track so we don't retry
        echo "  Skipping #${SESSION_ID} (PR $PR_URL is ${PR_STATE})"
        echo "$SESSION_ID" >> "$TRACKED_FILE"
        SKIPPED_PR_NOT_OPEN=$((SKIPPED_PR_NOT_OPEN + 1))
        continue
    fi

    echo ""
    echo "=== Session ${SESSION_ID} ==="
    echo "  Title: ${TITLE}"
    echo "  PR: ${PR_URL} (OPEN)"
    echo "  Sending self-review prompt..."

    RESPONSE=$(jules_send_message "$SESSION_ID" "$REVIEW_PROMPT")

    echo "  Sent. URL: https://jules.google.com/session/${SESSION_ID}"

    echo "$SESSION_ID" >> "$TRACKED_FILE"
    SENT=$((SENT + 1))
done

echo ""
echo "Done. Sent: ${SENT}, Already reviewed: ${SKIPPED_REVIEWED}, No PR: ${SKIPPED_NO_PR}, PR not open: ${SKIPPED_PR_NOT_OPEN}"
