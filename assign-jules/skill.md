---
name: assign-jules
description: Assign GitHub issues to Jules (Google's coding agent) or send self-review prompts to completed sessions. Use when the user says "assign to jules", "give to jules", "jules this issue", or "assign-jules".
argument-hint: "[issue numbers] or [review ready] or [review SESSION_ID] or [reply SESSION_ID message]"
allowed-tools: Bash
---

## Assign issues

Parse issue numbers from arguments, detect repo, and run:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
bash ${CLAUDE_SKILL_DIR}/scripts/assign.sh $REPO ISSUE_NUMBERS
```

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
