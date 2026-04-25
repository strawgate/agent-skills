#!/usr/bin/env bash
#
# List Jules sessions waiting on user feedback so we can respond before
# launching more work or wondering why a task is stalled.
#
# Usage: check-questions.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../_shared/jules-api/jules-lib.sh"

jules_require_key

echo "Fetching sessions..."
SESSIONS=$(jules_list_sessions 100)

COUNT=$(echo "$SESSIONS" | jq '[.sessions[]? | select(.state == "AWAITING_USER_FEEDBACK")] | length' 2>/dev/null)

if [ "${COUNT:-0}" = "0" ]; then
    echo "No Jules sessions are waiting on user feedback."
    exit 0
fi

echo "Jules sessions waiting on user feedback:"
echo ""

echo "$SESSIONS" | jq -r '
    .sessions[]?
    | select(.state == "AWAITING_USER_FEEDBACK")
    | [.id, .title, (.updateTime // ""), (.url // ("https://jules.google.com/session/" + .id))]
    | @tsv
' 2>/dev/null | while IFS=$'\t' read -r SESSION_ID TITLE UPDATE_TIME SESSION_URL; do
    echo "  ${SESSION_ID}"
    echo "    Title: ${TITLE}"
    echo "    Updated: ${UPDATE_TIME}"
    echo "    URL: ${SESSION_URL}"

    ACTIVITIES=$(jules_get_activities "$SESSION_ID" 20)

    LATEST_AGENT_MESSAGE=$(echo "$ACTIVITIES" | jq -r '
        [
          .activities[]?
          | select(.originator == "agent")
          | .agentMessaged.agentMessage?
          | select(. != null and . != "")
        ]
        | last // ""
    ' 2>/dev/null)

    if [ -n "$LATEST_AGENT_MESSAGE" ]; then
        echo "    Latest agent message:"
        echo "$LATEST_AGENT_MESSAGE" | sed 's/^/      /'
    else
        echo "    Latest agent message: <none found in recent activities>"
    fi

    echo ""
done

echo "Open the Jules URL to inspect full activity history and answer directly."
