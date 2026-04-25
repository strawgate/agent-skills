#!/usr/bin/env bash
# Assign GitHub issues to Copilot coding agent.
#
# Uses REST API for repo/issue ID lookups to reduce GraphQL rate limit pressure.
# Only uses GraphQL for operations that have no REST equivalent:
#   - suggestedActors (Copilot bot ID lookup)
#   - updateIssue with agentAssignment (assignment mutation)
#
# Usage: assign-to-copilot.sh OWNER/REPO ISSUE_NUMBER [ISSUE_NUMBER...]
#        assign-to-copilot.sh OWNER/REPO ISSUE_NUMBER --agent AGENT_NAME --model MODEL
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: assign-to-copilot.sh OWNER/REPO ISSUE_NUMBER [ISSUE_NUMBER...]
       assign-to-copilot.sh OWNER/REPO ISSUE_NUMBER --agent AGENT_NAME --model MODEL

Options:
  --agent NAME   Custom agent file name (without .agent.md extension)
  --model MODEL  Model to use (default: claude-opus-4.6)
EOF
  exit 1
}

[[ $# -lt 2 ]] && usage

REPO="$1"; shift
OWNER="${REPO%/*}"
REPO_NAME="${REPO#*/}"
AGENT=""
MODEL="claude-opus-4.6"
ISSUES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)
      # Strip leading # from issue numbers
      ISSUES+=("${1#\#}")
      shift
      ;;
  esac
done

[[ ${#ISSUES[@]} -eq 0 ]] && usage

# ── Step 1: Get repo node_id via REST (saves 1 GraphQL call) ───────────────

REPO_ID="$(gh api "repos/${OWNER}/${REPO_NAME}" --jq '.node_id')"
echo "Repo: ${REPO} (${REPO_ID})"

# ── Step 2: Get Copilot bot ID via GraphQL (no REST equivalent) ────────────

COPILOT_ID="$(gh api graphql \
  -H "GraphQL-Features: issues_copilot_assignment_api_support" \
  -f query="{ repository(owner: \"${OWNER}\", name: \"${REPO_NAME}\") {
    suggestedActors(loginNames: \"copilot\", capabilities: [CAN_BE_ASSIGNED], first: 1) {
      nodes { login ... on Bot { id } }
    }
  }}" \
  --jq '.data.repository.suggestedActors.nodes[0].id')"

if [[ -z "$COPILOT_ID" || "$COPILOT_ID" == "null" ]]; then
  echo "Error: Could not find Copilot bot for ${REPO}. Is Copilot enabled?" >&2
  exit 1
fi
echo "Copilot bot ID: ${COPILOT_ID}"

# ── Step 3: Auto-detect custom agent if not specified ──────────────────────

if [[ -z "$AGENT" ]]; then
  AGENTS="$(gh api "repos/${OWNER}/${REPO_NAME}/contents/.github/agents" --jq '.[].name' 2>/dev/null || true)"
  if [[ -n "$AGENTS" ]]; then
    AGENT="$(echo "$AGENTS" | head -1 | sed 's/\.agent\.md$//')"
    echo "Auto-detected agent: ${AGENT}"
  fi
fi

# ── Step 4: Assign each issue ─────────────────────────────────────────────

echo ""
printf '| %-7s | %-50s | %-15s | %-20s |\n' "Issue" "Title" "Agent" "Model"
printf '| %-7s | %-50s | %-15s | %-20s |\n' "-------" "--------------------------------------------------" "---------------" "--------------------"

for ISSUE_NUM in "${ISSUES[@]}"; do
  # Get issue node_id via REST (saves 1 GraphQL call per issue)
  ISSUE_JSON="$(gh api "repos/${OWNER}/${REPO_NAME}/issues/${ISSUE_NUM}" --jq '{node_id, title}')"
  ISSUE_ID="$(jq -r '.node_id' <<<"$ISSUE_JSON")"
  ISSUE_TITLE="$(jq -r '.title' <<<"$ISSUE_JSON")"

  # Build the agentAssignment block
  AGENT_ASSIGNMENT=""
  if [[ -n "$AGENT" ]]; then
    AGENT_ASSIGNMENT="customAgent: \"${AGENT}\","
  fi

  # Assign via GraphQL (no REST equivalent for agentAssignment)
  RESULT="$(gh api graphql \
    -H "GraphQL-Features: issues_copilot_assignment_api_support" \
    -H "GraphQL-Features: coding_agent_model_selection" \
    -f query="mutation {
      updateIssue(input: {
        id: \"${ISSUE_ID}\"
        assigneeIds: [\"${COPILOT_ID}\"]
        agentAssignment: {
          targetRepositoryId: \"${REPO_ID}\"
          ${AGENT_ASSIGNMENT}
          model: \"${MODEL}\"
        }
      }) {
        issue { title assignees(first: 5) { nodes { login } } }
      }
    }" --jq '.data.updateIssue.issue.title' 2>&1)" || true

  if [[ -n "$RESULT" && "$RESULT" != "null" ]]; then
    printf '| #%-6s | %-50s | %-15s | %-20s |\n' "$ISSUE_NUM" "${ISSUE_TITLE:0:50}" "${AGENT:-"(default)"}" "$MODEL"
  else
    echo "Error assigning #${ISSUE_NUM}: ${RESULT}" >&2
  fi
done
