#!/usr/bin/env bash
#
# Send a message to a Jules session via REST API.
# Usage: reply.sh SESSION_ID ["message"]
#
# If message is omitted, sends the default self-review prompt.
# Requires JULES_API_KEY environment variable.
#
set -euo pipefail

SESSION_ID="${1:?Usage: reply.sh SESSION_ID [\"message\"]}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use provided message or default self-review prompt
if [ -n "${2:-}" ]; then
    MESSAGE="$2"
else
    MESSAGE=$(cat "$SCRIPT_DIR/self-review-prompt.txt")
fi

if [ -z "${JULES_API_KEY:-}" ]; then
    echo "Error: JULES_API_KEY not set. Get your key from https://jules.google.com/settings#api"
    exit 1
fi

BASE_URL="https://jules.googleapis.com/v1alpha"

# Check session state
echo "Fetching session ${SESSION_ID}..."
STATE=$(curl -s \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${BASE_URL}/sessions/${SESSION_ID}" \
    | jq -r '.state // "UNKNOWN"')

echo "Session state: ${STATE}"

# Send message
echo "Sending message..."
RESPONSE=$(curl -s \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${BASE_URL}/sessions/${SESSION_ID}:sendMessage" \
    -d "$(jq -n --arg msg "$MESSAGE" '{prompt: $msg}')")

NEW_STATE=$(echo "$RESPONSE" | jq -r '.state // "UNKNOWN"')
echo "Message sent. New state: ${NEW_STATE}"
echo "URL: https://jules.google.com/session/${SESSION_ID}"
