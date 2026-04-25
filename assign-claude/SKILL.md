---
name: assign-claude
description: Launch Claude Code cloud sessions for prompt files, GitHub issues, or ad-hoc tasks via `claude --remote`. Supports single runs and fanout across multiple prompts. Use when the user says "assign to claude", "cloud session", "assign-claude", "claude fanout", or "launch cloud".
argument-hint: "[prompt files/dir, issue numbers, or task description] [--model opus|sonnet] [--dry-run]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Write, Edit, Agent
---

# Assign Claude — Launch Cloud Sessions

Launch one or more Claude Code cloud sessions for `$ARGUMENTS`.

Uses `claude --remote "prompt"` which creates autonomous cloud sessions on claude.ai infrastructure. Each session clones the repo from GitHub at the current branch and runs independently.

## Step 0: Parse Arguments

Parse `$ARGUMENTS` for:

- **Prompt files** — paths ending in `.md` or `.prompt.md`, or a directory containing them.
- **Issue numbers** — e.g., `#242 #243` or `242 243`.
- **Inline task** — a plain string describing the task.
- **--model MODEL** — model override. Accepts aliases: `opus` -> `claude-opus-4-6`, `sonnet` -> `claude-sonnet-4-6`.
- **--pattern GLOB** — glob pattern for prompt files in a directory. Defaults to `*.prompt.md`.
- **--dry-run** — show what would be launched without actually launching.

## Step 1: Verify Prerequisites

```bash
# Verify claude CLI is available
claude --version 2>&1

# Verify we're in a git repo
git rev-parse --show-toplevel 2>&1
```

## Step 2: Check Unpushed State

```bash
git fetch origin --quiet 2>&1
git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null
```

If there are unpushed commits, **warn the user loudly**: cloud sessions clone from GitHub and won't see local changes. Suggest pushing first. If the user wants to proceed anyway, `claude --remote` can also bundle the local repo when GitHub isn't configured, but when GitHub IS configured it clones from there.

To force bundling local state: `CCR_FORCE_BUNDLE=1 claude --remote "prompt"`.

## Step 3: Gather Prompts

### Prompt files mode

If arguments include `.md` files or a directory:
- Discover files matching the pattern (default `*.prompt.md`).
- Read each prompt file.
- Use the first `#` heading as the task name, falling back to the filename stem.

### Issue mode

For each issue number, use the shared issue-to-prompt builder:
```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROMPT=$("$SKILL_DIR/../_shared/github-issue-prompt/scripts/build-issue-prompt.sh" \
  OWNER/REPO ISSUE_NUM --agent-name claude)
```

Optional flags: `--plan` for plan-only, `--branch BRANCH`, `--custom-instructions "extra text"`.

### Inline task mode

Use the argument directly as the prompt.

## Step 4: Launch Cloud Sessions

For each task, run:

```bash
claude --remote "FULL_PROMPT_TEXT"
```

With optional model override:

```bash
claude --model claude-sonnet-4-6 --remote "FULL_PROMPT_TEXT"
```

**IMPORTANT**: `claude --remote` returns quickly after dispatching to the cloud. Each invocation creates an independent cloud session. Run them sequentially (each returns fast).

Capture stdout/stderr from each launch for the manifest.

## Step 5: Write Manifest (multi-task launches)

When multiple prompts are launched, write a JSON manifest:

```json
{
  "created_at": "<ISO timestamp>",
  "tool": "assign-claude",
  "repo": "<owner/repo>",
  "branch": "<current branch>",
  "model": "<model or default>",
  "local_head": "<git rev-parse HEAD>",
  "remote_head": "<git rev-parse origin/branch>",
  "tasks": [
    {
      "name": "<task name from heading>",
      "prompt_file": "<path or null>",
      "issue": "<number or null>",
      "stdout": "<claude --remote output>",
      "status": "launched"
    }
  ]
}
```

Write it to the prompt directory if one was provided, otherwise to the current directory.

## Step 6: Report

Print a summary table:

| # | Name | Source | Status |
|---|------|--------|--------|
| 1 | Callback Policy Drift | 01-callback-policy-drift.prompt.md | Launched |
| 2 | Host File Ingress | 02-host-file-ingress.prompt.md | Launched |

Then remind the user:
- Use `/tasks` in the CLI to check progress
- Visit https://claude.ai/code to see active sessions and interact
- Use `claude --teleport` to pull a completed session back to terminal
- Each session creates its own `claude/` branch for changes

## Operational Rules

- **Push first, launch second.** Cloud sessions clone from GitHub. Unpushed local state is invisible unless `CCR_FORCE_BUNDLE=1` is set.
- **Prompt self-containment.** Every prompt must include enough context to succeed from the committed repo alone. Don't assume the cloud session can see local files, prior session history, or uncommitted diffs.
- **Manifest is the handoff.** Write a manifest for multi-task launches.
- **One session per prompt.** Each `claude --remote` creates one independent session.
- **Parallel execution.** Multiple `--remote` calls run in parallel automatically in the cloud.

## Fanout Example

```
/assign-claude hackmonty/prompts/sandbox-wave28-claude-host-secret/ --model sonnet
```

Discovers all `*.prompt.md` files, launches a cloud session per prompt, writes a manifest.

## Single Issue Example

```
/assign-claude #242 --model opus
```

## Inline Task Example

```
/assign-claude "Review all open TODOs in src/ and create issues for each"
```

## Notes

- `claude --remote` creates cloud sessions on Anthropic infrastructure (4 vCPU, 16 GB RAM, 30 GB disk)
- Sessions persist even if you close the terminal
- Cloud sessions share rate limits with your normal Claude usage
- Requires a claude.ai Pro, Max, Team, or Enterprise subscription
- Use `claude --teleport` or `/teleport` to pull sessions back to terminal
- The cloud session can read its own ID from `CLAUDE_CODE_REMOTE_SESSION_ID` env var
