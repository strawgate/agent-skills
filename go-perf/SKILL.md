---
name: go-perf
description: Go performance optimization workflow — profile, identify allocation/clone hotspots, benchmark changes, isolate each optimization's contribution, and format results for PR bodies. Use when working on Go performance, profiling, pprof, benchmarks, allocation reduction, or Clone() elimination.
argument-hint: [focus e.g. "dissect processor", "mapstr.Clone", "event pipeline", or a package path]
allowed-tools: Read, Grep, Glob, Bash, Agent, WebSearch, WebFetch
effort: high
---

# Go Performance Optimization

Systematic workflow for finding and proving Go performance improvements.

## Principles (learned the hard way)

1. **Profile first, optimize second.** Don't guess where time is spent.
2. **Behavior must be identical.** Zero tolerance for behavior changes in hot-path optimizations. If you can't prove equivalence, don't ship it.
3. **Smallest diff wins.** Maintainers reject large refactors. Find the minimal change that captures the win.
4. **Isolate each change.** Benchmark each optimization independently — don't bundle 5 changes and claim "3x faster" without knowing which one matters.
5. **Benchmark skeptically.** Run both orderings. Vary CPU limits. Use realistic event sizes. If a result seems too good, it probably is.
6. **Clone() is almost always the enemy.** In event pipeline code, `event.Clone()` / `mapstr.Clone()` deep-copies the entire event. Eliminating unnecessary clones is often the single biggest win.

## Phase 1: Profile

### CPU profile
```bash
# For a running Go binary (e.g., filebeat)
curl -o cpu.pprof http://localhost:5066/debug/pprof/profile?seconds=30

# Or via go test
go test -bench=BenchmarkX -cpuprofile=cpu.pprof ./...

# Analyze
go tool pprof -http=:8080 cpu.pprof
```

### Memory/allocation profile
```bash
go test -bench=BenchmarkX -memprofile=mem.pprof -benchmem ./...
go tool pprof -http=:8080 -alloc_objects mem.pprof
```

### Key things to look for
- `runtime.growslice` — slice reallocation, consider pre-sizing
- `runtime.mapassign` — map growth, consider pre-sizing or avoiding maps
- `runtime.newobject` — heap escapes, check with `go build -gcflags='-m'`
- `runtime.typedmemmove` / `runtime.memmove` — deep copies (Clone!)
- `runtime.mallocgc` — raw allocation pressure, drives GC frequency
- Any function > 5% of CPU that isn't doing "real work"

### Escape analysis
```bash
go build -gcflags='-m -m' ./path/to/package 2>&1 | grep "escapes to heap"
```

## Phase 2: Identify Optimization Targets

### Common Go performance antipatterns

**Unnecessary Clone/DeepCopy:**
```go
// BAD: clones entire event just to read one field
clone := event.Clone()
val, _ := clone.GetValue("field")

// GOOD: read without cloning
val, _ := event.GetValue("field")
```

**Allocation in hot loops:**
```go
// BAD: allocates error on every call
func HasKey(m mapstr.M, key string) (bool, error) { ... }

// GOOD: bool-only fast path
func HasKey(m mapstr.M, key string) bool { ... }
```

**Repeated string splitting:**
```go
// BAD: splits "a.b.c" on every access
event.GetValue("a.b.c")  // splits every time
event.HasKey("a.b.c")    // splits again

// GOOD: split once, reuse path
parts := strings.Split(key, ".")
// use parts for both operations
```

**Defensive clones for rollback:**
```go
// BAD: clone before mutation in case of error
backup := event.Clone()
if err := mutate(event); err != nil {
    *event = *backup  // rollback
}

// GOOD: check preconditions first, mutate only if safe
if !canMutate(event) { return err }
mutate(event)  // no rollback needed
```

**Map allocation for existence checks:**
```go
// BAD: GetValue allocates a map to return
val, err := event.GetValue(key)
if err != nil { /* not found */ }

// GOOD: HasKey checks without allocating
if event.HasKey(key) { ... }
```

## Phase 3: Benchmark

### Write focused benchmarks
```go
func BenchmarkProcessorRun(b *testing.B) {
    p := newProcessor(config)
    event := makeRealisticEvent()  // Use realistic size!
    b.ResetTimer()
    b.ReportAllocs()
    for i := 0; i < b.N; i++ {
        p.Run(&event)
    }
}
```

### Run with allocation counts
```bash
go test -bench=BenchmarkX -benchmem -count=5 ./...
```

### Compare against baseline
```bash
# Install benchstat
go install golang.org/x/perf/cmd/benchstat@latest

# Run baseline
git checkout main
go test -bench=. -benchmem -count=10 ./... > baseline.txt

# Run optimized
git checkout my-branch
go test -bench=. -benchmem -count=10 ./... > optimized.txt

# Compare
benchstat baseline.txt optimized.txt
```

### Benchmark validation checklist
- [ ] Run both orderings (baseline first, then optimized first)
- [ ] Use realistic event sizes (not tiny synthetic ones)
- [ ] Test with CPU throttling (`cgroup` or `taskset`) for consistency
- [ ] Test with memory limits to surface GC pressure differences
- [ ] Verify `bytes/op` and `allocs/op` not just `ns/op`
- [ ] Run at least 5-10 iterations per benchmark

## Phase 4: Isolate Each Change

**Critical:** If you have multiple optimizations, benchmark each one independently.

```bash
# main (baseline)
git checkout main && go test -bench=. -benchmem -count=10 > base.txt

# optimization A only
git checkout main && git cherry-pick COMMIT_A
go test -bench=. -benchmem -count=10 > opt_a.txt

# optimization B only
git checkout main && git cherry-pick COMMIT_B
go test -bench=. -benchmem -count=10 > opt_b.txt

# all optimizations
git checkout my-branch
go test -bench=. -benchmem -count=10 > all.txt

# Compare each
benchstat base.txt opt_a.txt
benchstat base.txt opt_b.txt
benchstat base.txt all.txt
```

Present as a table showing each optimization's individual contribution.

## Phase 5: End-to-End Validation

Microbenchmarks prove the optimization works. E2E proves users will feel it.

### Run a realistic pipeline
```bash
# Build optimized binary
go build -o bin/filebeat-opt ./filebeat

# Build baseline
git stash && go build -o bin/filebeat-base ./filebeat && git stash pop

# Run each with profiling, constrained to 1 CPU
# Use a real pipeline config with multiple processors
taskset -c 0 ./bin/filebeat-base -e -c pipeline.yml &
# ... collect EPS, CPU%, RSS, pprof ...

taskset -c 0 ./bin/filebeat-opt -e -c pipeline.yml &
# ... collect same metrics ...
```

### Metrics to compare
- **EPS** (events per second) — throughput
- **CPU %** — efficiency
- **RSS / heap** — memory
- **allocs/s** — GC pressure
- **pprof diff** — where time shifted

### pprof diff
```bash
go tool pprof -base cpu-baseline.pprof cpu-optimized.pprof
# Shows only the delta — what changed
```

## Phase 6: Impact Analysis

Before making a PR, quantify the real-world impact:

### Check usage in the ecosystem
```bash
# How many integrations/configs use this processor?
grep -r "processor_name" integrations-repo/ --include="*.yml" | wc -l

# Which ones benefit most? (large events, many processors)
grep -rl "processor_name" integrations-repo/ --include="*.yml" | head -20
```

### Format for PR body

```markdown
## Performance

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| ns/op | X | Y | -Z% |
| allocs/op | X | Y | -Z% |
| B/op | X | Y | -Z% |

### E2E (filebeat, 1 CPU, realistic pipeline)
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| EPS | X | Y | +Z% |
| CPU% | X | Y | -Z% |

### Isolation (each change independently)
| Change | ns/op delta | Why |
|--------|-------------|-----|
| Remove Clone() | -X% | Eliminated deep copy of N-field event |
| Preallocate map | -Y% | Avoided runtime.growslice |

### Impact
- N integrations use this processor
- Top affected: [list]

Environment: [arch, CPU, Go version]
```

## Common Go Performance Wins (ranked by typical impact)

1. **Eliminate unnecessary Clone()/DeepCopy** — often 2-10x for large events
2. **Remove allocations from hot loops** — error objects, temporary maps, string building
3. **Preallocate slices/maps** with known capacity
4. **Avoid interface boxing** in tight loops (causes heap escape)
5. **Use strings.Builder** instead of `fmt.Sprintf` in loops
6. **Check before mutate** instead of clone-mutate-rollback
7. **Pool objects** with `sync.Pool` for high-frequency short-lived allocations
8. **Batch operations** instead of per-event overhead
