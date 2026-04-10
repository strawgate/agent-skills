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
    ISSUE_LABELS=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json labels -q '[.labels[].name] | join(", ")')
    ISSUE_URL="https://github.com/${REPO}/issues/${ISSUE_NUM}"

    PROMPT="Fix GitHub issue #${ISSUE_NUM}: ${ISSUE_TITLE}

${ISSUE_BODY}

Repository: ${REPO}
Issue URL: ${ISSUE_URL}
Issue labels: ${ISSUE_LABELS}

Instructions:
- Start from the repository default branch (${DEFAULT_BRANCH}), not any local developer branch.
- Before you resume work after delays, review feedback, or a stale branch window, fetch or otherwise refresh against the latest ${DEFAULT_BRANCH} so you are not coding against an old base.
- Treat your visible world as only: the default-branch repository on GitHub, the GitHub issue body, and this prompt text.
- You cannot see local worktrees, unpushed commits, unstaged files, branch-only memos, or chat context outside this prompt and the GitHub issue. Do not assume hidden local context exists.
- If the issue depends on context that is not clearly present on default branch, ask a focused question instead of guessing.
- Read AGENTS.md first when present, then read the issue carefully, then consult the most relevant repo docs before changing code:
  - README.md
  - DEVELOPING.md or CONTRIBUTING.md
  - architecture docs
  - verification docs
  - adapter or protocol contracts when the issue touches runtime or I/O semantics
- Treat the issue body as the primary task definition. If the issue appears stale, contradictory, or under-specified relative to current main, investigate carefully and ask a focused question in the Jules session instead of guessing.
- Keep the PR tightly scoped to this issue. Do not opportunistically bundle unrelated cleanup.
- Minimize unrelated file churn. If you touch extra files outside the obvious issue footprint, either remove those changes or be prepared to justify exactly why they are required.
- Do not commit one-off helper scripts, scratch files, or mechanical rewrite utilities unless the issue explicitly calls for shipping them in the repository.
- Before coding, inspect nearby tests and recent related code so the fix matches current architecture rather than an older plan.
- Add or update regression tests that would fail before the fix and pass after it.
- Update docs, proofs, or property tests when the changed behavior or contract requires it.
- Prefer behavior-preserving seam extraction over large rewrites unless the issue explicitly asks for a redesign.
- Do not stop at scaffolding. If you introduce models, helpers, reducers, or other structure, make sure the real behavior is wired through and exercised by tests before you ask for review.
- Run the narrowest meaningful verification first, then broader verification as warranted. At minimum, run the tests most directly covering your change. If broader CI-equivalent verification is realistic, run it; otherwise report exactly what you ran and why.
- If a PR already exists or review feedback arrives, fetch latest ${DEFAULT_BRANCH}, address the concrete feedback, re-check critical CI statuses, and only then say the PR is ready. Do not call a PR merge-ready while requested changes, unresolved correctness concerns, or failing critical checks remain.
- Before final handoff, do a thorough self-review, trim unrelated changes, and verify the PR description matches the actual code and tests.
- In the PR body, explain the problem, the root cause, the exact behavioral change, the tests/docs/proofs updated, and any residual risks or follow-up work."

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
