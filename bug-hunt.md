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
```bash
git fetch origin && git log --oneline origin/main -20
gh issue list --state open --label bug --limit 30 --json number,title
gh pr list --state merged --limit 10 --json number,title,mergedAt
```
Identify high-value hunting areas: output sinks, type dispatch, config validation gaps, new code.

### Phase 2: Hunt (10 min per bug, parallel agents)
Launch 2-3 Explore agents targeting different non-overlapping areas. While agents run, deep-dive manually into areas they aren't covering.

**Proven high-yield bug patterns (from batch 1):**

1. **Utf8 vs Utf8View mismatch**: Scanner produces Utf8View but UDFs/sinks only accept Utf8. Check `TypeSignature::Exact` in all UDFs — if it only lists `DataType::Utf8`, the UDF is broken for scanner-produced columns. Also check `array.as_string::<i32>()` calls (panic on Utf8View).

2. **`str_value()` panic on non-string types**: Any code calling `str_value(col, row)` where `col` might not be Utf8/Utf8View/LargeUtf8 will hit `unreachable!()`. Check console format, label extraction, any catch-all `_ =>` that delegates to `str_value`.

3. **Timestamp column name mismatches**: Code checking only `_timestamp`/`@timestamp` but not the full canonical list (`timestamp`, `time`, `ts`). Check `find_col`, `position()`, `matches_any()` usage in all sinks.

4. **`DataType::Timestamp` not handled in type dispatch**: Sinks that handle `Int64`/`UInt64`/`Utf8` timestamps but fall through to a default for `DataType::Timestamp(unit, _)`. The OTLP sink handles it correctly — others may not.

5. **Silent compression no-op**: Compression enum match arms that treat Gzip same as None. Config validation may accept the config but the sink ignores it.

6. **Star schema / OTAP column gaps**: `_scope_*` prefix columns not handled, bytes columns not extracted in roundtrip, attribute type dispatch `_ => {}` silently dropping data.

7. **Config validation vs runtime gap**: Config accepts a value but runtime panics on it. Check for `.expect("validated at config time")` — these should be `.map_err()`.

**Lower-yield patterns (from batch 1 experience):**
- Background agent false positives on code that was already fixed (they read partial functions). Always verify findings manually.
- CRI truncation at max_message_size is by-design, not a bug.
- `unreachable!()` in test-only code is not a production bug.
- Edge cases requiring `i64::MAX` inputs are not real-user scenarios.

### Phase 3: Dedup & File (2 min per bug)
1. `gh issue list --state open --label bug` — check each finding
2. `gh issue list --state closed --limit 50` — check recently closed
3. File with: root cause (file:line), trigger input, user-visible effect, fix approach
4. Use `--label bug`

### Phase 4: Fix & Test (5-10 min per fix)
1. Create a worktree: `EnterWorktree`
2. For each bug: implement the fix, write the regression test
3. `cargo fmt && cargo clippy -- -D warnings` before committing
4. Delegate regression test writing to a background agent while you keep hunting
5. Single commit per batch with all fixes, separate commit for tests

### Phase 5: PR
```bash
gh pr create --title "fix: N correctness bugs — ..." --body "$(cat <<'EOF'
## Summary
| # | Issue | Severity | Description |
...
## Test plan
- [ ] cargo test -p ... — N tests pass
- [ ] cargo clippy -- -D warnings — clean
EOF
)"
```

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
- Things that are "by design" (e.g., CRI truncation with warning log)
