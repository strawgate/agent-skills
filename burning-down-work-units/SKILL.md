---
name: burning-down-work-units
description: Continuously burn down a GitHub work-unit backlog by refreshing repo state, researching unclear issues, grouping or closing stale items, assigning Codex Cloud tasks, fanning in results, promoting ready work to PRs, and fixing PR feedback/CI in a loop.
argument-hint: "[owner/repo and optional scope e.g. 'strawgate/fastforward output sinks', 'current repo next wave']"
user-invocable: true
disable-model-invocation: false
---

# Burning Down Work Units

Run the continuous backlog execution loop for `$ARGUMENTS`.

Use this skill when the user wants ongoing progress across GitHub issues, work-unit issues, Codex Cloud assignments, fan-in results, PR creation, PR feedback, stale issue cleanup, and next-wave planning.

This is an execution workflow, not a reporting workflow. Keep moving until the user stops you or the next action is genuinely blocked.

## Operating Model

The loop has four queues:

- **Backlog readiness:** issues and work units that need research, body rewrites, grouping, stale checks, or clearer acceptance criteria.
- **Assigned cloud work:** Codex Cloud tasks that need launch, fan-in collection, quality review, or re-assignment.
- **PR-ready artifacts:** cloud or local results that are ready to apply, verify, push, and open as PRs.
- **Open PRs:** PRs that need CI, review feedback, branch refresh, issue-body updates, or follow-up issue creation.

Do not treat these queues as separate phases. Work whichever queue has the highest-leverage unblocked next action.

## Core Rules

- Update issue bodies as the source of truth. Avoid adding comments that conflict with the body.
- Before assigning work, confirm it is necessary, aligned with current repo goals, scoped, low-conflict, and testable.
- Prefer closing or narrowing stale issues over carrying zombie work forward.
- Work units are scheduling artifacts. Leaf issues remain the product/source-of-truth issues.
- Assign implementation only when the issue body is explicit enough for a strong agent to succeed from the committed repo and prompt text alone.
- Every cloud prompt must be self-contained. Do not rely on chat history or local uncommitted files.
- Fan-in every cloud result before opening a PR. Review diffs and artifacts; do not blindly promote them.
- When a cloud result is close but flawed, integrate and fix it locally before PR.
- Every PR needs meaningful verification. For code PRs, run focused tests first, then the repo's CI-equivalent command when feasible.
- When CI fails on a PR you opened or modified, inspect logs and fix the branch before assigning unrelated new work, unless the failure is clearly external/non-code.
- Never merge PRs without explicit user permission.

## Step 0: Refresh State

Determine the repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

Snapshot:

```bash
git status --short --branch
git fetch origin --quiet
gh issue list --repo OWNER/REPO --state open --label work-unit --limit 100
gh pr list --repo OWNER/REPO --state open --limit 100
```

If the repo has issue/work-unit organizer scripts, use them:

```bash
~/.Codex/skills/organize-work-items/scripts/fetch-repo-data.sh OWNER/REPO
~/.Codex/skills/organize-work-items/scripts/summarize-meta-structure.sh OWNER/REPO
~/.Codex/skills/organize-work-items/scripts/summarize-work-unit-structure.sh OWNER/REPO
```

Read:

- `/tmp/issue-organizer/OWNER__REPO/summary.txt`
- `/tmp/issue-organizer/OWNER__REPO/work-unit-summary.md`
- `/tmp/issue-organizer/OWNER__REPO/meta-summary.md`
- open PR records for likely conflicts
- issue records for orphan/stale candidate clusters

## Step 1: Triage Open PRs

For PRs you opened or recently touched:

```bash
gh pr checks PR --repo OWNER/REPO --watch=false
```

If checks fail:

1. Inspect the failing job logs with `gh run view`.
2. Identify whether the failure is code, test flake, infrastructure, external provider, or housekeeping automation.
3. Fix code failures on the PR branch.
4. Re-run the tightest local command that covers the failure.
5. Push and update the PR body if the verification story changed.

Also read review bodies and bot summaries, not only unresolved threads. CodeRabbit/Macroscope/etc. can leave top-level findings without unresolved inline threads.

## Step 2: Fan-In Cloud Work

For every active fanout manifest:

```bash
python3 ~/.Codex/skills/assign-codex-fanin/scripts/collect-cloud-artifacts.py PATH/TO/fanout-manifest.json
```

For each task:

- **READY + strong implementation:** apply to a fresh branch from `origin/main`, review, fix issues, run tests, open PR.
- **READY + research memo:** update issue bodies, create/split work units, or assign the next executable slice.
- **READY + flawed diff:** salvage locally only if the fix is bounded and obvious; otherwise update the issue with findings and reassign with a sharper prompt.
- **PENDING with no diff:** do not wait forever. If the work is urgent and locally clear, proceed locally or launch a replacement task.
- **FAILED:** extract useful findings if any, update the issue, and decide whether to re-prompt or close/narrow.

## Step 3: Research And Clean Issues

For each candidate work item, answer:

- Is the issue still necessary on current `main`?
- Is it already fixed by a merged PR?
- Is it duplicated or superseded?
- Is it aligned with the project plan and current goals?
- Is the file/crate footprint narrow enough for one agent run?
- Does it conflict with active PRs or assigned tasks?
- Are acceptance criteria observable and testable?
- Are non-goals explicit?
- Is verification realistic in cloud?

Then update the issue body:

- Add a dated status section.
- Link relevant PRs/tasks.
- Replace stale claims with current evidence.
- Split broad issues into work units when needed.
- Close completed/stale issues with `state_reason=completed` or `not_planned`.
- Keep leaf issues discoverable; use work-unit issues for scheduling.

## Step 4: Create Or Refine Work Units

Create a work unit when it is:

- one coherent file/crate/subsystem slice
- low discretion
- low conflict with open PRs
- clear enough for a cloud agent
- testable end to end

Use this issue body shape:

```markdown
## Parent

...

## Purpose

...

## Status

Issue-ready / assigned / PR opened / blocked, with links.

## Repo footprint

- `path`

## Scope

- [ ] ...

## Test matrix

- ...

## Non-goals

- ...

## Done when

- [ ] ...
```

Every issue needs labels: type, priority, and component labels. Use `work-unit` for scheduling issues.

## Step 5: Assign Codex Cloud Work

Write prompts under a repo-local research directory, for example:

```text
dev-docs/research/codex-cloud-wave-YYYY-MM-DD/<issue>-<slug>.prompt.md
```

Prompt requirements:

- Include issue URL and exact objective.
- Restate all necessary prior research and current status.
- List files to inspect.
- Define scope, non-goals, test matrix, and quality bar.
- Tell the agent to make code changes directly when implementation is wanted.
- Require focused tests and `just ci` or a documented blocker.
- Ask for final files changed, behavior, verification, and follow-ups.

Launch:

```bash
python3 ~/.Codex/skills/assign-codex-fanout/scripts/launch-cloud-fanout.py \
  --cwd "$PWD" \
  --prompt PATH/TO/prompt.md \
  --branch main \
  --env ENV_ID \
  --attempts 1 \
  --manifest PATH/TO/fanout-manifest-ISSUE.json
```

Use multiple attempts for high-stakes design or ambiguous implementation. Use one attempt for clear execution slices.

Update the issue body with the task URL immediately after launch.

## Step 6: Promote Results To PRs

When a result is PR-ready:

1. Start from a fresh branch based on `origin/main`.
2. Apply the cloud diff or implement locally.
3. Review the diff for repo consistency, generated-file rules, docs/test requirements, and CI guardrails.
4. Run focused verification.
5. Run `just ci` when feasible.
6. Commit, push, open PR.
7. Update linked issue bodies with the PR number.

PR body minimum:

```markdown
## Summary

- ...

## Issue notes

Addresses #...

## Verification

- `command` - result
```

## Step 7: Track Residual Work

After every PR or fan-in:

- Close stale leaf issues if the PR fully addresses them.
- Narrow partially addressed issues.
- Create follow-up work units only when there is real remaining work.
- Mark blocked work clearly with the dependency PR/issue.
- Avoid duplicate assignments against active PR branches.

## Step 8: Report A Compact Queue

When stopping or handing off, report:

- PRs opened or updated.
- Issues updated/closed/created.
- Cloud tasks launched and their status.
- Blocked items and dependencies.
- The next 3-5 actions.

Keep it short and operational. The user needs to know what can be merged, what is assigned, and what should be prepared next.

## Useful Commands

```bash
gh issue view ISSUE --repo OWNER/REPO --json number,title,body,labels,state
gh issue edit ISSUE --repo OWNER/REPO --body-file /tmp/body.md
gh pr view PR --repo OWNER/REPO --json number,title,body,headRefName,headRefOid,url
gh pr checks PR --repo OWNER/REPO --watch=false
gh run view RUN_ID --job JOB_ID --repo OWNER/REPO --log-failed
python3 scripts/check_max_source_lines.py
just fmt
just ci
```

## Stop Conditions

Stop only when:

- The user asks to stop.
- All unblocked queues are empty.
- The next action requires a human decision.
- A destructive operation would be needed.
- GitHub/cloud access is unavailable and no local progress is possible.
