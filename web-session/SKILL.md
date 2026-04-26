---
name: web-session
description: Start Codex web sessions for GitHub issues. Fetches issue context, crafts a prompt, and launches a cloud session via `Codex --remote`. Use when the user says "web session", "cloud session", "remote session", "send to web", "send to cloud", or "web-session".
argument-hint: "[owner/repo] #issue1 #issue2 ... [--branch <branch>] [--plan] [--autofix]"
allowed-tools: Bash
---

# Start Codex Web Sessions for GitHub Issues

Launch one or more Codex cloud sessions (Codex.ai/code) from GitHub issues.
Each issue gets its own independent web session that runs in parallel.

## Step 0: Parse Arguments

Parse `$ARGUMENTS` for:
- **owner/repo** — e.g., `strawgate/fastforward`. If not provided and we're in a git repo, detect from `gh repo view --json nameWithOwner -q .nameWithOwner`. Otherwise ask.
- **Issue numbers** — e.g., `#242 #243` or `242 243`. If not provided, ask.
- **--branch <name>** — optional branch to use (defaults to the repo's default branch).
- **--plan** — if present, start the session in plan-only mode (research and plan, don't edit code).
- **--autofix** — if present, include instructions to create a PR and enable auto-fix.

## Step 1: Verify Prerequisites

```bash
# Verify gh CLI is authenticated
gh auth status 2>&1

# Verify Codex CLI is available
Codex --version 2>&1
```

If either fails, tell the user what's missing and stop.

## Step 2: Fetch Issue Details

For each issue, fetch full context:

```bash
gh issue view ISSUE_NUM --repo OWNER/REPO --json number,title,body,labels,assignees,comments,milestone
```

Collect all issue details. If an issue doesn't exist, warn and skip it.

## Step 3: Craft the Prompt

For each issue, build a prompt following this template:

```
Fix GitHub issue OWNER/REPO#NUMBER: TITLE

## Issue Description
<issue body, trimmed to first 2000 chars if very long>

## Labels
<comma-separated labels>

## Key Comments
<last 3 comments if any, each trimmed to 500 chars>

## Instructions
- Read the repo's AGENTS.md and dev-docs/ for project conventions before starting.
- Work on a new branch named `fix/issue-NUMBER` (or `feat/issue-NUMBER` for enhancements).
- Write tests that cover the change.
- Run the project's lint and test commands to verify your changes.
- Create a PR referencing the issue (e.g., "Fixes #NUMBER") when done.
- Link back to this session in the PR body using the CLAUDE_CODE_REMOTE_SESSION_ID env var.
```

If **--plan** was specified, replace the Instructions section with:
```
## Instructions
- Read the repo's AGENTS.md and dev-docs/ for project conventions.
- Research the codebase to understand the relevant code paths.
- Produce a detailed implementation plan with specific files, functions, and changes needed.
- Do NOT edit any source code. Only research and plan.
- Save the plan as a markdown file in the repo.
```

If **--autofix** was specified, append to Instructions:
```
- After creating the PR, enable auto-fix to watch for CI failures and review comments.
```

## Step 4: Launch Cloud Sessions

For each issue, launch a cloud session. Ensure you are on the correct branch first if --branch was specified.

```bash
Codex --remote "CRAFTED_PROMPT"
```

If launching multiple issues, run each `Codex --remote` command sequentially (each returns quickly after dispatching to the cloud).

**Important**: `--remote` requires the current directory to be a git repo with a GitHub remote. The cloud VM clones from GitHub, so any unpushed local commits won't be available. Warn the user if `git status` shows unpushed commits on the current branch.

## Step 5: Report

Print a summary table:

| Issue | Title | Session | Branch |
|-------|-------|---------|--------|
| #242 | Fix auth bug | Launched | fix/issue-242 |
| #243 | Add metrics | Launched | feat/issue-243 |

Then remind the user:
- Use `/tasks` in the CLI to check progress
- Open Codex.ai/code to interact with sessions directly
- Use `Codex --teleport` to pull a completed session back to the terminal

## Notes

- `Codex --remote` creates a new cloud session on Codex.ai infrastructure
- Each session gets its own isolated VM with the repo cloned
- Sessions persist even if you close your browser/terminal
- The cloud VM has ~4 vCPU, 16 GB RAM, 30 GB disk
- Cloud sessions share rate limits with your normal Codex usage
- Multiple `--remote` sessions run in parallel independently
- Requires a Codex.ai Pro, Max, Team, or Enterprise subscription
