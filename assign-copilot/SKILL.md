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

## Step 1: Run the assignment script

```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
"$SKILL_DIR/scripts/assign-to-copilot.sh" OWNER/REPO ISSUE_NUM1 ISSUE_NUM2 ...
```

Optional flags:
- `--agent AGENT_NAME` — override the auto-detected custom agent
- `--model MODEL` — override the default model (default: `claude-opus-4.6`)

The script:
1. Gets the repo `node_id` via **REST** (saves a GraphQL call)
2. Gets the Copilot bot ID via GraphQL (no REST equivalent)
3. Auto-detects custom agents from `.github/agents/` via **REST**
4. Gets each issue's `node_id` via **REST** (saves 1 GraphQL call per issue)
5. Assigns via the `updateIssue` GraphQL mutation (no REST equivalent for `agentAssignment`)

**Net result**: Only 2 GraphQL calls total (1 for bot ID + 1 per issue for assignment), down from 3+N.

## Step 2: Confirm

The script prints a summary table:

| Issue | Title | Agent | Model |
|-------|-------|-------|-------|
| #242 | Add metrics | issue-worker | claude-opus-4.6 |

## Notes

- The `model` field is a string, not an enum (e.g., `"claude-opus-4.6"`, `"gpt-4o"`, `"claude-sonnet-4.6"`)
- If the repo has no custom agents, omit the `customAgent` field entirely
- The REST API (`gh api --method PATCH /repos/OWNER/REPO/issues/NUM -f assignees[]=copilot-swe-agent[bot]`) works for simple assignment but does NOT support model or custom agent selection
