#!/usr/bin/env bash
# Build a structured agent prompt from a GitHub issue.
# Shared by assign-claude, web-session, and assign-jules.
#
# Usage: build-issue-prompt.sh OWNER/REPO ISSUE_NUMBER [OPTIONS]
#
# Options:
#   --branch BRANCH       Branch name to reference (default: repo's default branch)
#   --max-body CHARS      Max issue body chars (default: 4000)
#   --max-comments N      Max recent comments to include (default: 3)
#   --plan                Generate plan-only instructions (no code edits)
#   --agent-name NAME     Name of the agent (for branch naming: claude, jules, copilot)
#   --custom-instructions TEXT  Append extra instructions
#
# Outputs a structured prompt to stdout.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: build-issue-prompt.sh OWNER/REPO ISSUE_NUMBER [OPTIONS]

Options:
  --branch BRANCH           Branch to reference (default: repo default branch)
  --max-body CHARS          Max issue body chars (default: 4000)
  --max-comments N          Max recent comments (default: 3)
  --plan                    Plan-only mode (research, no code edits)
  --agent-name NAME         Agent name for branch prefix (default: agent)
  --custom-instructions TXT Extra instructions to append
EOF
  exit 1
}

[[ $# -lt 2 ]] && usage

REPO="$1"; shift
ISSUE_NUM="$1"; shift

BRANCH=""
MAX_BODY=4000
MAX_COMMENTS=3
PLAN_ONLY=false
AGENT_NAME="agent"
CUSTOM_INSTRUCTIONS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --max-body) MAX_BODY="$2"; shift 2 ;;
    --max-comments) MAX_COMMENTS="$2"; shift 2 ;;
    --plan) PLAN_ONLY=true; shift ;;
    --agent-name) AGENT_NAME="$2"; shift 2 ;;
    --custom-instructions) CUSTOM_INSTRUCTIONS="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ── Fetch issue data (single REST call via gh) ─────────────────────────────

ISSUE_JSON="$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json number,title,body,labels,comments)"
ISSUE_TITLE="$(jq -r '.title' <<<"$ISSUE_JSON")"
ISSUE_BODY="$(jq -r '.body // ""' <<<"$ISSUE_JSON")"
ISSUE_LABELS="$(jq -r '[.labels[].name] | join(", ")' <<<"$ISSUE_JSON")"

# Trim body if too long
if [[ ${#ISSUE_BODY} -gt $MAX_BODY ]]; then
  ISSUE_BODY="${ISSUE_BODY:0:$MAX_BODY}..."
fi

# Extract recent comments
COMMENTS="$(jq -r --argjson max "$MAX_COMMENTS" '
  [.comments[-$max:][]? | "**" + .author.login + "** (" + .createdAt + "):\n" + (.body[:500])]
  | join("\n\n")
' <<<"$ISSUE_JSON")"

# ── Resolve branch ─────────────────────────────────────────────────────────

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")"
fi

# ── Build prompt ───────────────────────────────────────────────────────────

cat <<PROMPT
Fix GitHub issue ${REPO}#${ISSUE_NUM}: ${ISSUE_TITLE}

## Issue Description
${ISSUE_BODY}

## Labels
${ISSUE_LABELS:-"(none)"}
PROMPT

if [[ -n "$COMMENTS" ]]; then
  cat <<PROMPT

## Key Comments
${COMMENTS}
PROMPT
fi

if [[ "$PLAN_ONLY" == "true" ]]; then
  cat <<'PROMPT'

## Instructions
- Read the repo's CLAUDE.md and dev-docs/ for project conventions.
- Research the codebase to understand the relevant code paths.
- Produce a detailed implementation plan with specific files, functions, and changes needed.
- Do NOT edit any source code. Only research and plan.
- Save the plan as a markdown file in the repo.
PROMPT
else
  cat <<PROMPT

## Instructions
- Start from the repository default branch (${BRANCH}), not any local developer branch.
- Before you resume work after delays, review feedback, or a stale branch window, fetch or otherwise refresh against the latest ${BRANCH} so you are not coding against an old base.
- Treat your visible world as only: the default-branch repository on GitHub, the GitHub issue body, and this prompt text.
- You cannot see local worktrees, unpushed commits, unstaged files, branch-only memos, or chat context outside this prompt and the GitHub issue. Do not assume hidden local context exists.
- Read AGENTS.md first when present, then read the issue carefully, then consult the most relevant repo docs before changing code (README.md, DEVELOPING.md/CONTRIBUTING.md, architecture docs).
- Treat the issue body as the primary task definition.
- Work on a new branch named \`${AGENT_NAME}/issue-${ISSUE_NUM}\`.
- Keep the PR tightly scoped to this issue. Do not opportunistically bundle unrelated cleanup.
- Add or update regression tests that would fail before the fix and pass after it.
- Update docs, proofs, or property tests when the changed behavior or contract requires it.
- Run the narrowest meaningful verification first, then broader verification as warranted.
- Before final handoff, do a thorough self-review, trim unrelated changes, and verify the PR description matches the actual code and tests.
- Create a PR referencing the issue (e.g., "Fixes #${ISSUE_NUM}") when done.
PROMPT
fi

if [[ -n "$CUSTOM_INSTRUCTIONS" ]]; then
  cat <<PROMPT
${CUSTOM_INSTRUCTIONS}
PROMPT
fi
