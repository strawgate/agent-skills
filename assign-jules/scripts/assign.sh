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

## CRITICAL — Ship Real Behavior, Not Scaffolding

Your PR must contain WORKING production code with real behavior wired end-to-end. Do NOT submit scaffolding, stubs, todo placeholders, unimplemented!() calls, or partial type skeletons. Every struct, trait impl, function, and code path you introduce must be fully connected to callers, exercised by tests, and demonstrably functional.

Before calling your PR ready, verify:
1. Every new function is called from real production code (not just tests).
2. Every new type/struct is actually used in the data flow, not just defined.
3. Every code path you added can be triggered and has at least one test proving it works.
4. You ran the tests and they pass. At minimum run the crate-level tests covering your change. Run \`just ci\` before final handoff if scope permits; if not, report exactly what you ran.

If you find yourself writing skeleton types or placeholder logic, STOP and implement the real thing. A smaller PR with fully working code is always better than a larger PR with half-wired scaffolding.

## Context and Approach

- Start from the repository default branch (${DEFAULT_BRANCH}), not any local developer branch.
- Before resuming after delays or review feedback, refresh against latest ${DEFAULT_BRANCH}.
- Your visible world is only: the default-branch repo on GitHub, the issue body, and this prompt. You cannot see local worktrees, unpushed commits, or chat context outside this prompt.
- If the issue depends on context not present on default branch, ask a focused question instead of guessing.

## Required Reading (before coding)

Read AGENTS.md first, then the issue carefully, then the most relevant docs:
- README.md, DEVELOPING.md
- dev-docs/ARCHITECTURE.md, dev-docs/DESIGN.md
- dev-docs/VERIFICATION.md, dev-docs/CHANGE_MAP.md
- dev-docs/ADAPTER_CONTRACT.md and dev-docs/SCANNER_CONTRACT.md (when touching input/output/runtime semantics)

## Scope and Quality

- Treat the issue body as the primary task definition. If stale or under-specified relative to current main, ask a focused question instead of guessing.
- Keep the PR tightly scoped to this issue. Do not bundle unrelated cleanup.
- Before coding, inspect nearby tests and recent related code so your fix matches current architecture.
- Use confidence discipline: confirmed issues only in the PR. Speculative concerns go in a separate comment, not in the code.

## Testing and Verification

- Add or update regression tests that would fail before the fix and pass after it.
- Update docs, Kani proofs, TLA specs, or proptests when the changed behavior or contract requires it.
- Investigate until remaining new findings are likely low-value noise. Do not stop after the first plausible fix if a deeper pass would uncover related correctness issues within scope.

## PR Readiness

- If review feedback arrives, fetch latest ${DEFAULT_BRANCH}, address the concrete feedback, and re-check CI before marking ready. Do not call a PR merge-ready while requested changes or failing critical checks remain.
- Before final handoff: thorough self-review, trim unrelated changes, verify the PR description matches the actual code and tests.
- In the PR body, explain: the problem, root cause, exact behavioral change, tests/proofs/docs updated, and any residual risks.

## Pre-Push Checklist (MANDATORY)

Before pushing or creating the PR, run these commands in order and fix any failures:

1. **Delete non-source files from the repo root.** Remove ALL .py, .sh, .txt, .diff, .md (except repo docs), and scratch/test files you created during development. Run: \`git status\` and \`git clean -fd\` to verify nothing extra is staged. Check: \`find . -maxdepth 1 -name '*.py' -o -name '*.sh' -o -name '*.diff' -o -name 'scratch*' -o -name 'bench_out*' -o -name 'plan.md' -o -name 'req_plan*' | xargs rm -f\`
2. **Format all code:** \`cargo fmt\`
3. **Lint:** \`cargo clippy -- -D warnings\`
4. **Test changed crates:** \`cargo test -p <crate-you-changed>\`

Do NOT skip step 1. Every previous PR from this system shipped with leftover Python scripts and scratch files that had to be manually removed. This wastes reviewer time and blocks CI."

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
