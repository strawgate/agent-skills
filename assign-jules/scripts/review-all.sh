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
REVIEW_PROMPT=$(cat "$SCRIPT_DIR/self-review-prompt.txt")
TRACKED_FILE="$SCRIPT_DIR/.reviewed-sessions"
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")}"

if [ -z "${JULES_API_KEY:-}" ]; then
    echo "Error: JULES_API_KEY not set. Get your key from https://jules.google.com/settings#api"
    exit 1
fi

BASE_URL="https://jules.googleapis.com/v1alpha"

touch "$TRACKED_FILE"

echo "Fetching sessions..."
SESSIONS=$(curl -s \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${BASE_URL}/sessions?pageSize=50")

# Extract completed sessions with their details
COMPLETED=$(echo "$SESSIONS" | jq -r '.sessions[]? | select(.state == "COMPLETED") | .name' 2>/dev/null)

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

    TITLE=$(echo "$SESSIONS" | jq -r --arg name "$SESSION_NAME" \
        '.sessions[]? | select(.name == $name) | .title // "untitled"' 2>/dev/null)

    # Get session details to find the PR URL
    SESSION_DETAIL=$(curl -s \
        -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
        "${BASE_URL}/sessions/${SESSION_ID}")

    PR_URL=$(echo "$SESSION_DETAIL" | jq -r \
        '.outputs[]?.pullRequest?.url // empty' 2>/dev/null | head -1)

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

    RESPONSE=$(curl -s \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
        "${BASE_URL}/sessions/${SESSION_ID}:sendMessage" \
        -d "$(jq -n --arg msg "$REVIEW_PROMPT" '{prompt: $msg}')")

    echo "  Sent. URL: https://jules.google.com/session/${SESSION_ID}"

    echo "$SESSION_ID" >> "$TRACKED_FILE"
    SENT=$((SENT + 1))
done

echo ""
echo "Done. Sent: ${SENT}, Already reviewed: ${SKIPPED_REVIEWED}, No PR: ${SKIPPED_NO_PR}, PR not open: ${SKIPPED_PR_NOT_OPEN}"
