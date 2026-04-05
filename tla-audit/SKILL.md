---
name: tla-audit
description: Audit TLA+ / TLC specifications for correctness, completeness, and real-world fidelity. Checks variable priming, property strength, fairness, state space coverage, abstraction gaps, and liveness. Use when the user says "TLA audit", "check my TLA spec", "TLC audit", "audit the spec", or "tla-audit".
argument-hint: [path to .tla file or directory, optional focus e.g. "liveness only", "compare to code"]
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch
effort: thorough
---

# TLA+ Specification Audit

Audit a TLA+ specification for correctness, completeness, and fidelity to the real system it models.

## Principles

1. **A spec that passes TLC proves nothing if the properties are too weak.** The most common TLA+ mistake is writing invariants that are trivially true. Always check whether a property could be strengthened.
2. **A spec that abstracts away the bug cannot find the bug.** Every abstraction choice hides something. Document what each abstraction hides and assess whether it could mask a real failure.
3. **Liveness properties are fragile.** CONSTRAINT bounds silently break liveness by cutting off behaviors before convergence. Fairness on environment actions can make properties vacuously true. Both are common mistakes.
4. **Small model constants find small bugs.** If your safety config has MaxX=2, you cannot find bugs that require 3 of X. Always assess whether the constants are large enough.
5. **The spec must be maintained alongside code.** A correct spec for a system that no longer exists is worthless. Check that the spec matches the current implementation.

## Phase 1: Structural Completeness

### Variable priming check

For EVERY action in the `Next` relation, verify that all state variables are either primed or listed in `UNCHANGED`. This is the #1 source of TLC false positives — a missing variable in `UNCHANGED` lets TLC assign it any value, silently weakening the spec.

```bash
# Find all actions
grep -n '==' spec.tla | grep -v '\\*'

# Find all variables
grep -n 'VARIABLES\|VARIABLE' spec.tla

# For each action, check that every variable appears as either:
#   var' = ...    or    UNCHANGED <<..., var, ...>>
```

For each action, produce a verdict: PASS (all vars accounted for) or FAIL (missing var + which one).

### Init completeness

Verify `Init` assigns every variable. Uninitialized variables are set to an arbitrary value by TLC, which can mask bugs or produce false counterexamples.

### Type invariant coverage

Check that `TypeOK` / `TypeInvariant` constrains every state variable. Variables missing from the type invariant won't be caught if they take unexpected values.

### Next disjunction completeness

Verify that `Next` includes all actions, including stuttering if intended. Missing an action from `Next` means that transition can never fire.

## Phase 2: Property Strength

For each safety invariant, ask:

### Does it check what it claims?

Read the property name and compare it to what the formula actually asserts. Common gaps:

- **"NoCorruption"** that only checks values are in range, not ordering or completeness
- **"NoDataLoss"** that only checks the current state, not that lost data was ever recoverable
- **"Consistency"** that checks a snapshot but not the transition that created it

### Could it be strengthened?

For each property, propose a stronger version and explain why the current version might pass when the spec is wrong:

- Does it check **ordering** of emitted/processed items?
- Does it check **completeness** (all items eventually appear)?
- Does it check **no duplicates** (each item appears at most once)?
- Does it check **monotonicity** (counters/offsets never decrease)?
- Does it check the **relationship between variables** (e.g., committed ≤ processed ≤ read)?

### Ghost variables

If the spec uses ghost/auxiliary variables for verification, check that they are truly decoupled from the real state. A ghost variable that affects real transitions is a modeling error.

## Phase 3: Liveness Analysis

Liveness properties are the hardest to get right. Check each one systematically.

### Fairness audit

| Question | Why it matters |
|----------|---------------|
| Which actions have WF (weak fairness)? | WF means "if continuously enabled, eventually fires" — appropriate for internal/system actions |
| Which actions have SF (strong fairness)? | SF means "if repeatedly enabled, eventually fires" — needed for actions that toggle enable/disable |
| Which actions have NO fairness? | Environment actions (external inputs, crashes) should NOT have fairness — the environment is not obligated to cooperate |
| Are environment actions forced to cooperate? | If `AppendLine` has WF, the spec assumes the environment always writes. This makes liveness vacuously true. |

### CONSTRAINT vs model constants

**Critical:** `CONSTRAINT` bounds state space by cutting off behaviors at the constraint boundary. For safety, this is fine. For liveness, this silently breaks the proof — behaviors are truncated before they can converge.

Check: Are liveness properties checked with `CONSTRAINT` active? If so, the liveness proof is UNSOUND. Use smaller model constants instead.

### Vacuity check

For each liveness property of the form `P ~> Q` (P leads to Q):
1. Can `P` ever be true in a reachable state? If not, the property is vacuously true.
2. Is `P` dependent on an environment action with no fairness? If so, the property only holds when the environment cooperates.
3. Does the antecedent (`P`) reference state that changes after evaluation? If so, the property may be checking a different state than intended.

### Temporal property patterns

| Pattern | Correct form | Common mistake |
|---------|-------------|----------------|
| "Eventually always P" | `<>[]P` | `[]<>P` (infinitely often) is weaker |
| "P leads to Q" | `P ~> Q` (= `[](P => <>Q)`) | Checking a single state rather than all behaviors |
| "Once P, always P" | `[](P => []P)` | Missing the inner `[]` |
| "Never P after Q" | `[](Q => []~P)` | Only checking immediate next state |
| "Every X eventually completes" | `\A x: InFlight(x) ~> Completed(x)` | Checking set emptiness instead |

## Phase 4: Abstraction Fidelity

This is where TLA+ audits find real bugs: the spec abstracts away a detail that matters.

### For each action, compare to the real code:

1. **Atomicity.** Does the action do multiple things that are NOT atomic in the real code? If TailerRead atomically reads ALL available data but the real code reads in chunks, the spec hides partial-read bugs.

2. **Nondeterminism.** Does the real code have choices the spec doesn't model? If the spec always reads all data but the real code can return partial reads, the spec is missing interleavings.

3. **State that doesn't exist in the model.** Buffers, caches, queues between components — if the real system has an intermediate buffer that the spec skips, bugs in that buffer are invisible.

4. **State that exists in the model but not in reality.** Variables the spec tracks that don't correspond to anything in the code are suspicious.

### Common abstraction gaps from real projects:

- **Partial reads**: Spec reads atomically, real code reads in chunks. Hides bugs where checkpoint offset races ahead of data actually processed.
- **Single-entity models**: Spec models one file/connection/partition. Real system has multiple. Interactions between entities (resource contention, ordering across entities) are invisible.
- **No byte-level modeling**: Spec models "messages" or "lines" as atomic. Real code splits bytes across buffers. Hides framing bugs.
- **Deletion not modeled**: Spec models create but not delete. File deletion, connection close, partition removal — all create edge cases that absent actions cannot find.
- **Identity reuse**: Spec gives monotonically increasing IDs. Real system reuses inode numbers, connection IDs, etc. Collision bugs are invisible.
- **Crash recovery simplification**: Spec "loses volatile state" on crash. Real recovery is more complex — stale file handles, half-written data, corrupted buffers.

## Phase 5: State Space Assessment

### Model constant analysis

For each model constant:
1. What is its value in the safety config?
2. What scenarios require a LARGER value?
3. Is there a "stress config" that exercises multi-instance interactions?

### Common too-small constants:

| Constant | Minimum for interesting bugs |
|----------|------------------------------|
| MaxEntities (files, connections) | ≥ 2 (to find inter-entity bugs) |
| MaxCrashes | ≥ 2 (to find crash-restart-crash bugs) |
| MaxRotations/deletions | ≥ 2 (to find double-rotation before drain) |
| MaxItems per entity | ≥ 3 (to find off-by-one in batch boundaries) |
| BatchSize | Should vary: test with 1 AND with MaxItems |

### State space size guidelines

| States | Acceptable? |
|--------|-------------|
| < 100K | Definitely explore larger constants |
| 100K–1M | Sweet spot for safety |
| 1M–10M | Still tractable, good for stress configs |
| > 10M | May need symmetry sets or constraint heuristics |
| > 100M | Needs decomposition or abstraction |

### Symmetry sets

Are interchangeable values (e.g., source IDs, reader IDs) declared as symmetry sets? Missing symmetry makes state space unnecessarily large. Adding incorrect symmetry (values that are NOT interchangeable) makes results unsound.

## Phase 6: Cross-Layer Verification

### Code-to-spec mapping

For each state variable in the spec, identify the corresponding code construct. For each action, identify the corresponding function or code path. Document gaps.

### Refinement mapping

If there are multiple specs at different abstraction levels:
- Does the lower-level spec refine the higher-level one?
- Is there a documented refinement mapping (which variable maps to which)?
- Has the refinement been mechanically checked with TLC?

### Verification layer gaps

If the project also uses implementation-level verification (Kani, proptest, etc.):
- Are there properties proven in TLA+ but NOT verified at the code level?
- Are there code paths verified by Kani/proptest but NOT modeled in TLA+?
- Is there a "bridge" (refinement mapping, equivalence test) connecting the layers?

## Phase 7: Report

### Structure:

#### Executive Summary
- Spec: filename, line count, state variables, actions, properties
- TLC results: safety (states, depth, time), liveness (states, depth, time)
- Findings: N critical, N high, N medium, N low

#### Structural Audit Table

| # | Action | All vars primed/UNCHANGED? | Verdict |
|---|--------|---------------------------|---------|
| 1 | ActionName | Details | PASS/FAIL |

#### Property Strength Assessment

| Property | Type | What it claims | What it actually checks | Gap |
|----------|------|---------------|------------------------|-----|
| ... | Safety/Liveness | ... | ... | ... |

#### Liveness Analysis

| Property | Fairness dependency | Vacuity risk | CONSTRAINT interaction | Verdict |
|----------|--------------------|--------------|-----------------------|---------|

#### Abstraction Gap Analysis

| Gap | What the spec abstracts | What the real code does | Could it hide a bug? | Priority |
|-----|------------------------|------------------------|---------------------|----------|

#### State Space Assessment

| Config | Constants | States | Depth | Missing scenarios |
|--------|-----------|--------|-------|-------------------|
| Safety | ... | ... | ... | ... |
| Liveness | ... | ... | ... | ... |

#### Recommendations (prioritized)

1. Properties to strengthen (with proposed formulas)
2. Actions to add (with sketched TLA+)
3. Constants to increase (with expected state space impact)
4. Abstraction gaps to close (with modeling suggestions)
5. Cross-layer verification to add

## Guidelines

- **Read the actual TLA+ source.** Don't just check structure — understand what each action models and whether it faithfully represents reality.
- **Run TLC yourself** if possible. Don't trust "it passed" without knowing the constants and config.
- **Check every `ASSUME`.** Each assumption narrows what the spec verifies. Document whether each assumption holds in the real world.
- **Check for TLC-specific operators** (`Print`, `Assert`, `JavaTime`). These don't verify anything formally — they're debug aids.
- **Look for commented properties.** Specs evolve. A property that was commented out is often a property that failed and was deferred. Flag these.
- **Check `CONSTANT` usage in properties.** If an invariant references a model constant in a way that makes it trivially true for that constant value, the invariant is model-dependent.
