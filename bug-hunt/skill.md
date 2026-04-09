---
name: bug-hunt
description: Systematic bug hunting for logfwd — builds the binary, crafts adversarial configs and CLI sequences, runs them, files high-severity bugs, and periodically PRs regression tests with fixes. Use when the user says "bug hunt", "find bugs", "hunt bugs", or "bug-hunt".
argument-hint: "[optional: focus area e.g. 'config validation', 'OTLP output', 'file tailing', 'SQL transforms']"
allowed-tools: Read, Grep, Glob, Bash, Agent, WebSearch, WebFetch, TaskCreate, TaskUpdate, Edit, Write
context: fork
effort: high
---

# Bug Hunt

Find real, high-severity bugs in logfwd that affect users in production. File them as GitHub issues and periodically submit PRs with regression tests and fixes.

**Quality bar**: Every bug must be something a real user could hit. Panics, data loss, silent misconfiguration, incorrect output, hangs, resource leaks. NOT: cosmetic issues, doc typos, style nits, theoretical edge cases that require malicious input. We are being watched — silly bugs get ignored, serious bugs get promoted.

**Goal**: Find 50 bugs, file 5 PRs (each fixing ~10 bugs with regression tests).

## Phase 0: Setup

1. Detect repo: `gh repo view --json nameWithOwner -q .nameWithOwner`
2. Build a release binary: `just build` (or `cargo build --release -p logfwd`)
3. Note the binary path: `target/release/logfwd`
4. Create a scratch directory for test configs and data: `mkdir -p /tmp/logfwd-bug-hunt`
5. Generate test data:
   ```bash
   ./target/release/logfwd generate-json 10000 /tmp/logfwd-bug-hunt/logs.json
   ```
6. Create additional test data files:
   - A valid CRI log file (Kubernetes format)
   - A malformed JSON file (truncated lines, invalid UTF-8, mixed encodings)
   - An empty file
   - A file with only newlines
   - A very long single line (>1MB)
   - A file with Windows line endings (\r\n)
   - A file that grows while being read (use a background writer)

## Phase 1: Fetch Open Issues (do this FIRST and every 10 bugs)

```bash
gh issue list --repo OWNER/REPO --state open --limit 200 --json number,title,labels,body
```

Build a dedup index: title keywords + labels. Before filing any bug, search this list. Multiple agents are bug-hunting simultaneously — duplicates waste everyone's time.

Also check recently closed issues to avoid re-filing known-fixed bugs:
```bash
gh issue list --repo OWNER/REPO --state closed --limit 100 --json number,title,labels
```

## Phase 2: Systematic Bug Hunting

Work through each category below. For each test:
1. Write the config YAML to a temp file
2. Run `./target/release/logfwd validate --config <file>` — check if validation catches the issue or silently accepts bad config
3. Run `./target/release/logfwd run --config <file>` with a 30-second timeout — watch for panics, hangs, incorrect output, memory issues
4. Run `./target/release/logfwd effective-config --config <file>` — check for inconsistencies
5. Capture stdout, stderr, and exit code

### Category A: Config Edge Cases (validation gaps)

Test configs that SHOULD be rejected but might slip through, and configs that SHOULD work but might fail:

1. **Type coercion traps**: YAML `true`/`false`/`null`/numbers where strings expected
   ```yaml
   input:
     type: file
     path: true          # boolean where string expected
     format: json
   output:
     type: stdout
   ```

2. **Integer overflow / boundary**: batch_target_bytes, workers, timeouts at MAX, 0, negative, float
   ```yaml
   input:
     type: file
     path: /tmp/logfwd-bug-hunt/logs.json
     format: json
   output:
     type: otlp
     endpoint: https://localhost:4318
   pipelines:  # Try both simple and advanced forms
     test:
       inputs: [...]
       outputs: [...]
       workers: 999999999999
       batch_target_bytes: -1
       batch_timeout_ms: 0.5
   ```

3. **Path traversal / special paths**: symlinks, /dev/null, /proc/self/fd/0, named pipes, device files
4. **Unicode / encoding**: config file in UTF-16, emoji in pipeline names, null bytes in paths
5. **Duplicate keys**: YAML allows duplicate keys — which one wins?
6. **Anchor/alias abuse**: YAML anchors creating circular references or deeply nested structures
7. **Very large config**: 1000 pipelines, 1000 inputs per pipeline
8. **Empty/whitespace variants**: empty string vs missing vs null vs whitespace-only for every field
9. **Mixed simple/advanced with subtle violations**: top-level `input` with `pipelines` that has only `outputs`
10. **Environment variable edge cases**: `${UNSET}`, `${=bad}`, `${}`, `${PATH}` (huge value), nested `${${VAR}}`

### Category B: Runtime Behavior

11. **File disappears mid-read**: tail a file, then delete it
12. **File replaced mid-read**: tail a file, then replace it with a different file (same name)
13. **Glob pattern matches thousands of files**: does it OOM or handle gracefully?
14. **Symlink loops in glob paths**: `/tmp/a -> /tmp/b -> /tmp/a`
15. **Permission denied on log file**: readable initially, then chmod 000
16. **Disk full during checkpoint write**: fill /tmp, see what happens to checkpointing
17. **OTLP endpoint unreachable**: what's the retry behavior? Does it block? Backpressure?
18. **OTLP endpoint returns 500/429/503**: does it retry? Exponential backoff?
19. **Elasticsearch endpoint returns malformed response**: garbled JSON
20. **Very fast input**: generator at max speed — does memory grow unboundedly?
21. **Signal handling**: SIGTERM during flush, SIGHUP, SIGUSR1/2, double SIGTERM
22. **Multiple instances with same checkpoint dir**: data corruption? Lock contention?

### Category C: Data Handling

23. **JSON with deeply nested objects**: 100+ levels
24. **JSON with very large arrays**: 10K elements in a single field
25. **JSON with duplicate keys**: `{"level": "info", "level": "error"}`
26. **JSON with non-string message field**: `{"message": 42}`, `{"message": null}`, `{"message": [1,2,3]}`
27. **CRI log with corrupted timestamp**: invalid date, epoch 0, far future
28. **CRI log with extremely long partial lines**: 100MB partial that never completes
29. **Log line exactly at buffer boundary**: lines that are exactly 4096, 8192, 65536 bytes
30. **Binary data in log file**: what happens with null bytes, control characters?
31. **Mixed formats in one file**: some lines JSON, some CRI, some raw — with format: auto

### Category D: SQL Transform

32. **SQL injection-style queries**: `DROP TABLE`, `CREATE TABLE`, subqueries
33. **SQL referencing non-existent columns**: `SELECT nonexistent FROM logs`
34. **SQL with aggregations**: `SELECT COUNT(*) FROM logs GROUP BY level` — does this work or silently drop?
35. **SQL with JOINs**: `SELECT * FROM logs a JOIN logs b ON a.level = b.level`
36. **SQL producing empty result set**: `SELECT * FROM logs WHERE 1=0` — does the pipeline stall?
37. **Very complex SQL**: deeply nested CASE/WHEN, many UDFs, regex on every field
38. **SQL with UDF edge cases**: `regexp_extract(NULL, '.*')`, `grok(message, '%{INVALID_PATTERN}')`, `int('not_a_number')`
39. **SQL that changes column types**: `SELECT CAST(level AS INTEGER) FROM logs`
40. **SQL with window functions**: `SELECT *, ROW_NUMBER() OVER (ORDER BY timestamp) FROM logs`

### Category E: Output Sinks

41. **Stdout with pipe closed**: `logfwd run ... | head -1` — does EPIPE cause panic?
42. **File output to read-only path**: `/etc/logfwd-output.json`
43. **File output path is a directory**: output path is `/tmp/`
44. **Elasticsearch with invalid index name**: special characters, very long name
45. **Loki with very long label values**: 10KB label value
46. **OTLP with enormous batch**: batch_target_bytes set to 1GB
47. **Multiple outputs, one fails**: does the healthy output continue?
48. **TCP/UDP output to endpoint that resets**: connection reset mid-write
49. **Null output with transform**: does it still execute the SQL? (performance trap)

### Category F: CLI Sequences

50. **validate then run same config**: does validate leave state that affects run?
51. **dry-run on config that references missing enrichment files**: crash or clean error?
52. **effective-config with env vars that contain YAML metacharacters**: `ENDPOINT="http://host:port # comment"`
53. **wizard on non-interactive terminal**: pipe stdin, does it hang or error?
54. **completions for all shells**: do they all generate valid output?
55. **blackhole receiver**: start it, send garbage data, does it crash?
56. **generate-json with 0 lines**: `logfwd generate-json 0 out.json`
57. **generate-json to /dev/null**: does it work?
58. **generate-json to stdout** (no file argument): is the error good?
59. **run with --config pointing to directory**: is the error good?
60. **run with --config pointing to binary file**: is the error good?

### Category G: Concurrency & Resource

61. **Rapid config file changes with inotify**: touch config repeatedly during run
62. **Many concurrent connections to diagnostics endpoint**: 1000 parallel curl requests
63. **Diagnostics endpoint with malformed HTTP**: raw TCP garbage
64. **Memory under pressure**: ulimit -v, run with large input
65. **File descriptor exhaustion**: ulimit -n 16, run with glob matching many files
66. **CPU starvation**: nice -n 19, run with complex SQL on fast input

## Phase 3: Filing Bugs

For each confirmed bug, file a GitHub issue:

```bash
gh issue create --repo OWNER/REPO \
  --title "type: concise description" \
  --label "bug" \
  --body "$(cat <<'EOF'
## Summary
One sentence: what happens, when, and why it matters to users.

## Reproduction
\`\`\`yaml
# Exact config that triggers the bug
\`\`\`

\`\`\`bash
# Exact commands to reproduce
\`\`\`

## Expected Behavior
What should happen.

## Actual Behavior
What actually happens. Include the exact error/panic/output.

## Impact
Who hits this and how badly. Is data lost? Does the process crash? Does it silently produce wrong output?

## Environment
- logfwd version: (from --version)
- OS: (uname -a)
- Rust: (rustc --version)
EOF
)"
```

**Labels**: Always `bug`. Add severity:
- `P0` — crash, data loss, silent corruption
- `P1` — incorrect behavior, resource leak, hang
- `P2` — poor error message, confusing behavior

**Title format**: `bug: [component] description` — e.g., `bug: [config] YAML boolean coercion silently accepts path: true`

## Phase 4: Fix & PR (every 10 bugs)

After every 10 bugs filed, create a PR that:

1. **Branch**: `fix/bug-hunt-batch-N` from latest `origin/main`
2. **For each bug**:
   - Add a regression test that reproduces the bug (fails without fix, passes with fix)
   - Implement the minimal fix
   - Reference the issue number in the test name and commit
3. **Run**: `just ci` (must pass)
4. **PR body**: list all bugs fixed with issue links, describe the pattern of bugs found
5. **PR title**: `fix: bug hunt batch N — [brief theme]`

Structure commits as one-per-bug for easy review:
```
fix(config): reject boolean values in path fields (#NNN)
fix(runtime): handle file deletion during tail (#NNN)
...
```

## Tracking

Maintain a running tally using tasks:
- Bugs found: N/50
- Bugs filed: N/50
- PRs submitted: N/5
- Current focus area: [category]

After each bug, update the tally. After each PR, update the tally.

## Priority Order

Start with categories most likely to yield high-severity bugs:
1. **C (Data Handling)** — silent data corruption is worst
2. **B (Runtime)** — crashes and hangs are next worst
3. **E (Output Sinks)** — wrong data shipped to users' backends
4. **D (SQL Transform)** — unexpected query behavior
5. **A (Config Edge Cases)** — bad configs accepted silently
6. **F (CLI Sequences)** — UX issues
7. **G (Concurrency)** — harder to reproduce but high impact

## Focus Area

If `$ARGUMENTS` specifies a focus area, prioritize that category but still check others. If no focus area, work through the priority order above.

## Rules

- **Never file a duplicate**. Check open AND recent closed issues before every filing.
- **Never file cosmetic bugs**. If the maintainers would say "who cares?", don't file it.
- **Always include reproduction steps**. If you can't reproduce it reliably, note that.
- **Prefer bugs that affect default/common configurations**. An edge case in a rarely-used feature is lower priority than a bug in the happy path.
- **Test on the actual release binary**, not debug builds (behavior differs — optimizations, overflow checks, etc.)
- **Capture exact output**. Don't paraphrase error messages.
- **Check if a bug is already fixed on main** before filing. Pull latest, rebuild, retest.
