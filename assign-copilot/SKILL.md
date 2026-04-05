---
name: assign-copilot
description: Assign GitHub issues to Copilot coding agent with Claude Opus 4.6 and a custom agent. Use when the user says "assign to copilot", "give to copilot", "copilot this issue", or "assign-copilot".
argument-hint: [owner/repo #issue1 #issue2 ... or just issue numbers if repo is obvious]
allowed-tools: Bash
---

# Assign Issues to Copilot

Assign one or more GitHub issues to the Copilot coding agent using Claude Opus 4.6 and the repo's custom agent (if one exists).

## Step 0: Determine Repo and Issues

Parse `$ARGUMENTS` for:
- **owner/repo** — e.g., `strawgate/memagent`. If not provided and we're in a git repo, detect from `gh repo view --json nameWithOwner -q .nameWithOwner`. Otherwise ask.
- **Issue numbers** — e.g., `#242 #243` or `242 243`. If not provided, ask.

## Step 1: Get Repo and Bot IDs

```bash
# Get repo ID and Copilot bot ID
gh api graphql \
  -H "GraphQL-Features: issues_copilot_assignment_api_support" \
  -f query='{
    repository(owner: "OWNER", name: "REPO") {
      id
      suggestedActors(loginNames: "copilot", capabilities: [CAN_BE_ASSIGNED], first: 1) {
        nodes {
          login
          ... on Bot { id }
        }
      }
    }
  }'
```

Store the `repository.id` and `suggestedActors.nodes[0].id` values.

## Step 2: Detect Custom Agent

Check if the repo has a custom agent defined:
```bash
gh api repos/OWNER/REPO/contents/.github/agents --jq '.[].name' 2>/dev/null
```

If agents exist, use the first `.agent.md` file's name (without the extension) as the `customAgent` value. If none exist, omit the `customAgent` field.

## Step 3: Get Issue GraphQL IDs

For each issue number:
```bash
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    issue(number: ISSUE_NUM) { id title }
  }
}'
```

## Step 4: Assign Each Issue

For each issue, run the assignment mutation:
```bash
gh api graphql \
  -H "GraphQL-Features: issues_copilot_assignment_api_support" \
  -H "GraphQL-Features: coding_agent_model_selection" \
  -f query='mutation {
    updateIssue(input: {
      id: "ISSUE_GRAPHQL_ID"
      assigneeIds: ["COPILOT_BOT_ID"]
      agentAssignment: {
        targetRepositoryId: "REPO_ID"
        customAgent: "AGENT_NAME"
        model: "claude-opus-4.6"
      }
    }) {
      issue {
        title
        assignees(first: 5) { nodes { login } }
      }
    }
  }'
```

**Required headers** — both `GraphQL-Features` headers are mandatory:
- `issues_copilot_assignment_api_support`
- `coding_agent_model_selection`

**Model** — defaults to `claude-opus-4.6`. If the user specifies a different model, use that instead.

## Step 5: Confirm

Print a summary:

| Issue | Title | Agent | Model |
|-------|-------|-------|-------|
| #242 | Add metrics | issue-worker | claude-opus-4.6 |

## Notes

- The `model` field is a string, not an enum (e.g., `"claude-opus-4.6"`, `"gpt-4o"`, `"claude-sonnet-4.6"`)
- If the repo has no custom agents, omit the `customAgent` field entirely
- The REST API (`gh api --method PATCH /repos/OWNER/REPO/issues/NUM -f assignees[]=copilot-swe-agent[bot]`) works for simple assignment but does NOT support model or custom agent selection
