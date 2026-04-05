---
name: bench-compare
description: Run benchmarks, compare against a baseline (branch/commit/previous run), and format results for PR bodies. Use when the user says "benchmark", "bench", "compare performance", "how fast is it", or "bench-compare".
argument-hint: [optional baseline e.g. "main", "HEAD~1", or benchmark filter]
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Benchmark Compare

Run benchmarks on the current branch and optionally compare against a baseline.

## Step 0: Detect Build System

```bash
# Find the benchmark runner
if [ -f justfile ] || [ -f Justfile ]; then
  echo "just bench"
elif [ -f Cargo.toml ]; then
  echo "cargo bench"
elif [ -f package.json ]; then
  echo "npm run bench"
elif [ -f go.mod ]; then
  echo "go test -bench=."
fi
```

## Step 1: Determine Baseline

If `$ARGUMENTS` contains a branch name or commit, use that as baseline. Common patterns:
- `main` / `master` — compare against default branch
- `HEAD~1` — compare against previous commit
- No argument — just run current benchmarks, no comparison

## Step 2: Run Current Benchmarks

Run benchmarks on the current branch and capture output:
```bash
# Rust (Criterion)
cargo bench 2>&1 | tee /tmp/bench-current.txt

# Or with just
just bench 2>&1 | tee /tmp/bench-current.txt
```

If there's a benchmark filter in `$ARGUMENTS`, pass it through (e.g., `cargo bench -- scanner`).

## Step 3: Run Baseline (if requested)

```bash
# Stash current changes if needed
git stash --include-untracked

# Checkout baseline
git checkout $BASELINE

# Run same benchmarks
cargo bench 2>&1 | tee /tmp/bench-baseline.txt

# Return to original branch
git checkout -
git stash pop 2>/dev/null
```

## Step 4: Compare and Format

Parse the benchmark output and present:

### If Criterion (Rust):
Look for lines like `time: [X.XXX µs X.XXX µs X.XXX µs]` and `change: [-X.XX% +X.XX% +X.XX%]`.

### Format as a table:

| Benchmark | Baseline | Current | Change |
|-----------|----------|---------|--------|
| scan_10k | 1.23 ms | 1.05 ms | -14.6% |

### Highlight:
- Improvements (>5% faster) in green context
- Regressions (>5% slower) as warnings
- Within noise (<5%) as neutral

## Step 5: PR Body Snippet

If the user is preparing a PR, format the results as a markdown snippet ready to paste:

```markdown
## Benchmark Results

Compared against `main` at `abc1234`:

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| ... | ... | ... | ... |

Environment: [arch], [OS], [CPU]
```

Include the environment info:
```bash
uname -m && uname -s && sysctl -n machdep.cpu.brand_string 2>/dev/null || cat /proc/cpuinfo | grep "model name" | head -1
```
