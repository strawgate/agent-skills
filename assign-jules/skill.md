---
name: assign-jules
description: Assign GitHub issues to Jules (Google's coding agent), send self-review prompts to completed sessions, or archive sessions with merged/closed PRs. Use when the user says "assign to jules", "give to jules", "jules this issue", "assign-jules", "review ready", "archive jules sessions", or "clean up jules". For issue assignment, require the API-key flow so Jules can auto-create a PR; never use the CLI fallback that requires manual PR publishing.
argument-hint: "[issue numbers] or [review ready] or [review SESSION_ID] or [reply SESSION_ID message] or [archive] or [archive --dry-run]"
allowed-tools: Bash
---

## Assign issues

Before assigning issues, ensure `JULES_API_KEY` is set in the environment.
If it is missing, stop and tell the user to configure it first.
Do **not** use any fallback path that creates a Jules session without
`automationMode: AUTO_CREATE_PR`.

Parse issue numbers from arguments, detect repo, and run:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
bash ${CLAUDE_SKILL_DIR}/scripts/assign.sh $REPO ISSUE_NUMBERS
```

Expected behavior:

- use the Jules REST API
- set `automationMode: AUTO_CREATE_PR`
- report the Jules session URL(s) back to the user
- if `JULES_API_KEY` is not configured, fail fast instead of creating a
  non-auto-PR session

## Review all completed sessions

When the user says "review ready" or "review all", find all completed sessions that haven't been self-reviewed yet and send the review prompt:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/review-all.sh
```

Tracks which sessions have been reviewed in `.reviewed-sessions` so it never double-sends.

## Review a specific session

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/reply.sh SESSION_ID
```

## Reply with custom message

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/reply.sh SESSION_ID "custom message"
```

Report session URLs back to the user.

## Archive completed sessions

When the user says "archive jules sessions", "clean up jules", or "archive completed sessions", delete sessions whose PRs are merged or closed:

```bash
# Dry-run first to preview
bash ${CLAUDE_SKILL_DIR}/scripts/archive.sh --dry-run

# Then archive for real
bash ${CLAUDE_SKILL_DIR}/scripts/archive.sh
```

Options:
- `--dry-run` — preview what would be deleted without actually deleting
- `--no-pr-days N` — also archive sessions with no PR older than N days (default: 7)

Only deletes sessions that are COMPLETED or FAILED and whose PR is MERGED or CLOSED. Never deletes sessions with open PRs.

**Always run with `--dry-run` first and show the user the output before running without it.**
