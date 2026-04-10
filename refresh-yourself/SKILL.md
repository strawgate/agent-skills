---
name: refresh-yourself
description: Rebuild context after time away by snapshotting recent PRs/issues, default-branch commits, and local file layout, then investigating likely drift before coding. Use when the user says "refresh yourself", "come back up to speed", "what changed", or "catch up after a break".
argument-hint: [optional: --commit-limit 80 --pr-limit 50 --issue-limit 50]
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# Refresh Yourself

Use this when returning to a repo after time away.

## Step 1: Generate Snapshot

Run the snapshot script from the repo (or pass `--cwd`):

```bash
${CLAUDE_SKILL_DIR}/scripts/refresh_snapshot.sh $ARGUMENTS
```

If no output path is provided, it writes to:

```text
<repo>/.codex/refresh/refresh-YYYYMMDD-HHMMSS.md
```

## Step 2: Read and Classify

Read the snapshot and classify signals into:
1. Likely stale assumptions
2. Likely unchanged assumptions
3. Needs deeper verification

## Step 3: Investigate High-Risk Drift

Prioritize in order:
1. Recent default-branch commit file list touching architecture/contracts/runtime/CI/Cargo.
2. Open PRs that may alter behavior soon.
3. Open issues indicating active breakage or policy change.

Follow-up commands:

```bash
git show <commit>
git log -- <path>
rg "contract|invariant|TODO|FIXME" -n dev-docs crates

gh pr view <number> --comments
gh issue view <number> --comments
```

## Step 4: Return a Refresh Memo

Provide a concise memo with:
1. What changed
2. What appears stable
3. What is uncertain and needs more checks
4. Recommended next actions before implementation

## Notes

- The snapshot script is read-only.
- If `gh` is unavailable or unauthenticated, local git/filesystem context is still captured.
