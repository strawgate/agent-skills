#!/usr/bin/env bash
#
# Assign GitHub issues to Jules via the REST API.
# Uses the API (not CLI) so we can set automationMode=AUTO_CREATE_PR.
#
# Usage: assign.sh OWNER/REPO ISSUE_NUMBER [ISSUE_NUMBER...]
#
# Requires JULES_API_KEY environment variable.
# Falls back to CLI if JULES_API_KEY is not set.
#
set -euo pipefail

REPO="${1:?Usage: assign.sh OWNER/REPO ISSUE_NUMBER [ISSUE_NUMBER...]}"
shift

BASE_URL="https://jules.googleapis.com/v1alpha"

for ISSUE_NUM in "$@"; do
    ISSUE_TITLE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title -q '.title')
    ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json body -q '.body')

    PROMPT="Fix GitHub issue #${ISSUE_NUM}: ${ISSUE_TITLE}

${ISSUE_BODY}

Repository: ${REPO}
Issue URL: https://github.com/${REPO}/issues/${ISSUE_NUM}

Instructions:
- Read CLAUDE.md for project conventions
- Run just ci before submitting to verify all checks pass
- Create a focused PR that addresses only this issue"

    echo "=== Assigning #${ISSUE_NUM}: ${ISSUE_TITLE} ==="

    if [ -n "${JULES_API_KEY:-}" ]; then
        # Use REST API — enables AUTO_CREATE_PR
        OWNER=$(echo "$REPO" | cut -d/ -f1)
        REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

        RESPONSE=$(curl -s \
            -X POST \
            -H "Content-Type: application/json" \
            -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
            "${BASE_URL}/sessions" \
            -d "$(jq -n \
                --arg prompt "$PROMPT" \
                --arg title "Fix #${ISSUE_NUM}: ${ISSUE_TITLE}" \
                --arg source "sources/github/${OWNER}/${REPO_NAME}" \
                '{
                    prompt: $prompt,
                    title: $title,
                    sourceContext: {
                        source: $source,
                        githubRepoContext: {
                            startingBranch: "master"
                        }
                    },
                    automationMode: "AUTO_CREATE_PR",
                    requirePlanApproval: false
                }')")

        SESSION_ID=$(echo "$RESPONSE" | jq -r '.id // "unknown"')
        SESSION_URL=$(echo "$RESPONSE" | jq -r '.url // empty')
        STATE=$(echo "$RESPONSE" | jq -r '.state // "QUEUED"')

        if [ -z "$SESSION_URL" ]; then
            SESSION_URL="https://jules.google.com/session/${SESSION_ID}"
        fi

        echo "  Session: ${SESSION_ID}"
        echo "  State: ${STATE}"
        echo "  URL: ${SESSION_URL}"
        echo "  Auto-PR: enabled"
    else
        # Fallback to CLI (no auto-PR)
        echo "  (No JULES_API_KEY — using CLI, PR must be published manually)"
        jules remote new --repo "$REPO" --session "$PROMPT"
    fi
    echo ""
done
