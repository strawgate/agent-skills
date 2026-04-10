---
name: assign-jules
description: Assign GitHub issues to Jules (Google's coding agent), check for Jules sessions awaiting user feedback, send self-review prompts to completed sessions, or archive sessions with merged/closed PRs. Use when the user says "assign to jules", "give to jules", "jules this issue", "assign-jules", "review ready", "archive jules sessions", "clean up jules", or "check jules questions". For issue assignment, require the API-key flow so Jules can auto-create a PR; never use the CLI fallback that requires manual PR publishing.
argument-hint: "[issue numbers] or [questions] or [review ready] or [review SESSION_ID] or [reply SESSION_ID message] or [archive] or [archive --dry-run]"
allowed-tools: Bash
---

## Assign issues

Before assigning issues, ensure `JULES_API_KEY` is set in the environment.
If it is missing, stop and tell the user to configure it first.
Do **not** use any fallback path that creates a Jules session without
`automationMode: AUTO_CREATE_PR`.

Before assigning new work, check whether any Jules sessions are blocked
waiting for us:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-questions.sh
```

If there are `AWAITING_USER_FEEDBACK` sessions, surface them to the user and
either answer those questions first or explicitly confirm we still want to fan
out more work.

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
- send a prompt that clearly states Jules only sees the default-branch repo,
  the GitHub issue, and the prompt text we provide
- tell Jules to refresh against the latest default branch before resuming after
  delays or review feedback
- tell Jules to keep PRs tightly scoped and avoid shipping helper scripts or
  partial scaffolding

## Review all completed sessions

When the user says "review ready" or "review all", find all completed sessions that haven't been self-reviewed yet and send the review prompt:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/review-all.sh
```

Tracks which sessions have been reviewed in `.reviewed-sessions` so it never double-sends.

Before doing this, also run:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-questions.sh
```

and tell the user if there are blocked sessions that need answers.

## Review a specific session

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/reply.sh SESSION_ID
```

## Reply with custom message

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/reply.sh SESSION_ID "custom message"
```

Report session URLs back to the user.

## Check sessions waiting on us

When the user says "check jules questions", "blocked jules sessions", or
"what is Jules waiting for", run:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-questions.sh
```

This reports every session in `AWAITING_USER_FEEDBACK` with the Jules URL so we
can open it and answer the question directly in Jules.

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
