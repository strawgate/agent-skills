---
name: formal-coverage-audit
description: Run a rigorous, codebase-wide audit of formal and property verification coverage (TLA+/TLC, Kani, proptest), build an implementation-to-spec traceability matrix, and produce a prioritized execution plan to maximize verified coverage with minimal proof debt.
argument-hint: [optional scope, e.g. "pipeline only", "crate logfwd-io", "new code since PR #1600", "full repo"]
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit, Write, WebFetch
context: fork
agent: general-purpose
effort: thorough
---

# Formal Coverage Audit (TLA+ / Kani / proptest)

Perform a deep audit to answer three questions:
1. What behavior is currently proven, and how strongly?
2. What implementation behavior is not yet modeled or proven?
3. What is the highest-leverage path to near-total verification coverage?

## Audit principles

1. Count proofs only when properties are meaningful and non-vacuous.
2. Prefer traceability over raw proof counts: code path -> property -> harness/spec.
3. Treat state machines and untrusted-input parsing as highest priority.
4. Separate safety claims (Kani/proptest) from temporal claims (TLA+/TLC).
5. For mixed async/runtime logic, extract a pure reducer where feasible, then prove reducer behavior.

## Phase 0: Scope and baseline

- Determine scope: full repo, crate, module, or changed files.
- Capture current branch, diff vs `main`, and whether this is:
  - point-in-time audit, or
  - pre-merge gate for a PR.

## Phase 1: Read project verification contract

Read these first:
- `AGENTS.md`
- `README.md`
- `DEVELOPING.md`
- `dev-docs/ARCHITECTURE.md`
- `dev-docs/VERIFICATION.md`
- `dev-docs/CHANGE_MAP.md` if present
- `tla/README.md`
- any module-specific verification docs under `dev-docs/verification/`

Goal: align to project rules before scoring gaps.

## Phase 2: Build a complete inventory

Run inventory discovery:

```bash
rg -n "#\\[kani::proof\\]|kani::requires|kani::ensures|kani::cover!|kani::assume" crates --glob "*.rs"
rg -n "proptest!|prop_assert|proptest_state_machine|proptest::" crates --glob "*.rs"
rg -n "\\.tla$|\\.cfg$" tla
rg -n "pub fn|pub async fn|pub\\(crate\\) fn|pub\\(crate\\) async fn" crates --glob "*.rs"
```

For each proof/spec artifact, record:
- file + symbol
- property intent (safety, liveness, refinement, crash-freedom, oracle equivalence)
- input space and bounds
- assumptions and vacuity guards
- where it runs (CI job / local-only / dormant)

## Phase 3: Traceability matrix

Create a matrix that maps each critical implementation behavior to verification evidence:

| Implementation unit | Behavior/property | TLA action/property | Kani harness(es) | proptest(s) | Status |
|---|---|---|---|---|---|

Status values:
- `covered-strong`: independent oracle or temporal proof plus implementation checks
- `covered-partial`: some checks exist but important dimensions are missing
- `uncovered`: no meaningful proof/test artifact
- `stale`: docs/spec claim coverage but code drifted

Focus first on:
- protocol state machines
- parser and wire-format code
- checkpoint, ordering, and ack semantics
- failure-handling and shutdown behavior
- any unsafe or perf-sensitive primitives

## Phase 4: Gap analysis and scoring

For each gap, score:
- **Impact**: data loss/corruption, protocol violation, availability, diagnosability
- **Exploitability/reachability**: realistic or edge-only
- **Proofability**: easy in Kani, better in proptest, needs TLA, or needs decomposition
- **Effort**: S/M/L

Severity classes:
- `critical`: can violate core correctness/safety guarantees
- `high`: likely correctness regression under real workloads
- `medium`: bounded risk, weaker guarantees than desired
- `low`: cleanup or hardening

## Phase 5: Recommended fixes

For each high or critical gap, propose:
1. Exact target file, function, or action.
2. Verification method split:
   - TLA+/TLC for temporal or design properties,
   - Kani for pure bounded invariants/contracts,
   - proptest for async, stateful, or heap-heavy behaviors.
3. Required refactor seam if code is not proof-friendly yet.
4. Minimal harness/spec skeleton and acceptance criteria.
5. CI integration updates (new jobs, gates, or required checks).

## Phase 6: Optional execution mode

If asked to implement:
- land the highest-leverage non-controversial proofs first
- keep behavior-preserving refactors separate from proof additions when practical
- add vacuity guards (`kani::cover!`, TLA reachability assertions)
- run relevant verification commands locally before proposing a PR

## Output format

Return:
1. **Executive summary**: current coverage posture plus largest risks.
2. **Traceability matrix** (or a scoped subset with explicit rationale).
3. **Prioritized gap backlog** with concrete issue-ready tasks.
4. **30/60/90 execution plan**:
   - 30: fastest high-signal wins
   - 60: reducer extraction plus cross-layer proof alignment
   - 90: deeper temporal and refinement hardening

## Quality bar

- Do not claim coverage without naming exact artifacts.
- Mark assumptions explicitly when inferring intent from code or docs.
- Prefer smaller, compositional proofs over monolithic harnesses.
- Flag stale or misleading verification docs as first-class findings.
