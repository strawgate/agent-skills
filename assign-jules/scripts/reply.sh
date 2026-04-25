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
source "$SCRIPT_DIR/../../_shared/jules-api/jules-lib.sh"

# Use provided message or default self-review prompt
if [ -n "${2:-}" ]; then
    MESSAGE="$2"
else
    MESSAGE=$(cat "$SCRIPT_DIR/self-review-prompt.txt")
fi

jules_require_key

# Check session state
echo "Fetching session ${SESSION_ID}..."
STATE=$(jules_get_state "$SESSION_ID")

echo "Session state: ${STATE}"

# Send message
echo "Sending message..."
RESPONSE=$(jules_send_message "$SESSION_ID" "$MESSAGE")

NEW_STATE=$(echo "$RESPONSE" | jq -r '.state // "UNKNOWN"')
echo "Message sent. New state: ${NEW_STATE}"
echo "URL: https://jules.google.com/session/${SESSION_ID}"
