#!/usr/bin/env bash
#
# Assign GitHub issues to Jules via the REST API.
# Uses the API (not CLI) so we can set automationMode=AUTO_CREATE_PR.
#
# Usage: assign.sh OWNER/REPO ISSUE_NUMBER [ISSUE_NUMBER...]
#
# Requires JULES_API_KEY environment variable.
# Never falls back to the CLI path because that does not enable AUTO_CREATE_PR.
#
set -euo pipefail

REPO="${1:?Usage: assign.sh OWNER/REPO ISSUE_NUMBER [ISSUE_NUMBER...]}"
shift

BASE_URL="https://jules.googleapis.com/v1alpha"

if [ -z "${JULES_API_KEY:-}" ]; then
    echo "Error: JULES_API_KEY is required for Jules assignment." >&2
    echo "Refusing to use the CLI fallback because it cannot auto-create a PR." >&2
    exit 1
fi

# Resolve the repository's default branch so sessions clone correctly.
DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH="main"
fi

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
            --arg startingBranch "$DEFAULT_BRANCH" \
            '{
                prompt: $prompt,
                title: $title,
                sourceContext: {
                    source: $source,
                    githubRepoContext: {
                        startingBranch: $startingBranch
                    }
                },
                automationMode: "AUTO_CREATE_PR",
                requirePlanApproval: false
            }')")

    ERROR_STATUS=$(echo "$RESPONSE" | jq -r '.error.status // empty')
    if [ -n "$ERROR_STATUS" ]; then
        ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.error.message // "Unknown error"')
        ERROR_CODE=$(echo "$RESPONSE" | jq -r '.error.code // "n/a"')
        echo "  Error: ${ERROR_STATUS} (${ERROR_CODE})"
        echo "  Message: ${ERROR_MESSAGE}"
        echo ""
        continue
    fi

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
    echo ""
done
