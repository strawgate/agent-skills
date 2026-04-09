---
name: bug-hunt
description: Systematic bug hunting — find 10 high-severity correctness bugs, file issues, then fix all 10 in one PR with regression tests
---

# Bug Hunt Skill

You are doing a competitive bug hunt on a Rust codebase. Your goal is to find **10 real, high-severity correctness bugs** that affect actual users, file GitHub issues for each, then submit **1 PR fixing all 10 with regression tests**.

## Philosophy

- **Deep analysis** (~10 min per bug). Read the actual code, trace the data flow, confirm the trigger condition. No guessing.
- **High severity only**. Data loss, wrong data, crashes, silent misconfiguration. Not style issues, not hypothetical concerns.
- **Dedup against open issues** before filing. Multiple agents may be hunting simultaneously.
- **Regression tests first**. Every fix must include a test that FAILS without the fix and PASSES with it.
- **Batch fixes into PRs of 10**. One PR per batch keeps review manageable and shows impact.

## Process

### Phase 1: Reconnaissance (5 min)
1. `git fetch origin && git log --oneline origin/main -20` — understand recent changes
2. `gh issue list --state open --label bug --limit 30` — know what's already filed
3. `gh pr list --state merged --limit 10` — see what was recently fixed (avoid re-finding)
4. Identify high-value hunting areas: output sinks, type dispatch, config validation gaps, new code

### Phase 2: Hunt (10 min per bug, parallel agents)
Launch 2-3 Explore agents targeting different areas:

**Bug patterns to hunt for:**
- Type dispatch gaps: `match DataType` with `_ =>` catch-all that drops data or panics
- Utf8 vs Utf8View: UDFs/sinks that only accept Utf8 but scanner produces Utf8View
- Null handling: `.value(row)` without `.is_null(row)` check
- Timestamp column name mismatches: code checking only some canonical variants
- Config validation gaps: accepted by validation, panics at runtime
- Silent data loss: catch-all arms that return empty string or default value
- Integer truncation: `as u64` / `as i64` on user data without bounds check

**While agents run, deep-dive manually** into areas agents aren't covering.

### Phase 3: Dedup & File (2 min per bug)
1. Check `gh issue list` for each finding — skip if already filed
2. File with: root cause (file:line), trigger input, user-visible effect, fix approach
3. Use `--label bug` on all issues

### Phase 4: Fix & Test (5-10 min per fix)
1. Create a worktree: `EnterWorktree`
2. For each bug: write the regression test FIRST, verify it fails, implement fix, verify it passes
3. `cargo fmt && cargo clippy -- -D warnings` before committing
4. Single commit per batch with all fixes

### Phase 5: PR
1. Push and create PR with summary table of all 10 bugs
2. Reference all filed issues
3. Include test plan with per-crate test commands

## Quality Bar

A bug is worth filing if:
- A real user running a real config would hit it
- The effect is data loss, wrong data, crash, or silent misconfiguration
- The fix is clear and the regression test is straightforward
- The maintainers would say "good catch" not "who cares"

Do NOT file:
- Test-only code issues
- Hypothetical concerns ("what if someone passes i64::MAX")
- Style/naming issues
- Missing features disguised as bugs
- Anything already tracked in open issues
