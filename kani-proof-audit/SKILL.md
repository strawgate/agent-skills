---
name: kani-proof-audit
description: Become an expert in the logfwd repository, then audit all Kani formal verification proofs. Reads project docs, understands architecture, catalogs every proof, identifies gaps, and produces an actionable audit report. Use when the user says "proof audit", "kani audit", "verify proofs", "audit proofs", or "kani-proof-audit".
argument-hint: [optional scope e.g. "otlp.rs only", "new proofs since last audit", "focus on gaps"]
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch
context: fork
agent: general-purpose
effort: thorough
---

# Kani Proof Audit

Audit all Kani formal verification proofs in the logfwd repository. Produce an expert-level report of what's proven, what's not, and what to do about it.

## Phase 1: Become an Expert

Read these docs **in full** before examining any code. Do not skip or skim.

### Required reading (in order):
1. `README.md` — what logfwd does, performance targets
2. `DEVELOPING.md` — workspace layout, build/test/bench, hard-won lessons
3. `AGENTS.md` — project conventions, code quality rules
4. `docs/ARCHITECTURE.md` — data flow, scanner architecture, crate map, design constraints
5. `dev-docs/PROVEN_CORE.md` — verification tiers (Tier 1-4), what belongs in the proven core, how to add proofs
6. `dev-docs/PROOF_AUDIT.md` — previous audit results, known gaps, gap classification
7. `dev-docs/DECISIONS.md` — architecture decisions (especially: no_std, FieldSink trait, Kani vs proptest split, TLA+ for liveness)
8. `dev-docs/CRATE_RULES.md` — per-crate rules (logfwd-core must be no_std, forbid unsafe, every public fn needs proof)
9. `docs/references/kani-verification.md` — Kani API reference: proof harnesses, kani::any(), unwind bounds, function contracts, solver selection, Bolero integration

### Understanding the verification architecture:
- **logfwd-core** = proven crate. Pure logic, no IO, no unsafe. Kani proofs live here.
- **logfwd-arrow** = SIMD backends. proptest verifies SIMD == scalar. No Kani.
- **Kani proves small fixed-width functions** exhaustively (all u64 inputs, all ≤32 byte buffers)
- **proptest proves unbounded functions** statistically (large inputs, random sequences)
- **Function contracts** (`kani::requires`/`kani::ensures`/`stub_verified`) enable compositional verification

## Phase 2: Catalog Every Proof

Search the entire codebase for Kani proofs:

```bash
# Find all Kani proof functions
grep -rn '#\[kani::proof\]' crates/ --include="*.rs"

# Find all Kani function contracts
grep -rn 'kani::requires\|kani::ensures\|stub_verified' crates/ --include="*.rs"

# Find all cfg(kani) modules
grep -rn '#\[cfg(kani)\]' crates/ --include="*.rs"

# Find all bolero harnesses (unified test/fuzz/proof)
grep -rn 'bolero::check' crates/ --include="*.rs"
```

For EACH proof found, record:
1. **File and function name** — e.g., `otlp.rs::verify_varint_roundtrip`
2. **What it proves** — read the proof body and any comments
3. **Input space** — what does `kani::any()` generate? How bounded?
4. **Assertions** — what properties are checked?
5. **Solver** — does it specify `#[kani::solver(kissat)]` or default?
6. **Unwind bound** — is there a `#[kani::unwind(N)]`? What N?
7. **Verification tier** — Tier 1 (exhaustive), Tier 2 (bounded), or Tier 3 (proptest companion)

## Phase 3: Catalog Every Public Function

For the proven core crate (`logfwd-core`), list every `pub fn` and `pub trait` method:

```bash
# All public functions in logfwd-core
grep -rn 'pub fn\|pub async fn' crates/logfwd-core/src/ --include="*.rs"

# All public trait methods
grep -rn 'fn .*(&' crates/logfwd-core/src/ --include="*.rs" | grep -v '//'
```

Cross-reference with the proof catalog from Phase 2. Identify:
- **Proven functions** — have a Kani proof or proptest
- **Unproven functions** — public API with no verification
- **Partially proven** — proof exists but doesn't cover all properties (e.g., no-panic only, no correctness oracle)

## Phase 4: Analyze Gaps

For each gap, classify it:

### Gap severity levels:
- **CRITICAL** — function handles untrusted input, silent data corruption possible (e.g., scanner parsing, OTLP encoding)
- **HIGH** — function is in hot path, correctness failure would be hard to detect (e.g., bitmask operations, field resolution)
- **MEDIUM** — function has correctness risk but failures would surface as visible errors (e.g., config parsing)
- **LOW** — function is simple/trivial or tested by integration tests

### For each proof, check:
1. **Does the input space cover real usage?** A proof over 8-byte inputs when real input is 4MB is bounded — note the gap.
2. **Does it prove correctness or just crash-freedom?** A no-panic proof is weaker than an oracle proof.
3. **Are there composition gaps?** Functions proven individually but not in combination (e.g., ChunkIndex multi-block chaining).
4. **Is the oracle independent?** The reference implementation should be obviously correct (not the same algorithm rewritten).
5. **Are there carry/state gaps?** Functions with state that persists across calls (carry bits, partial buffers) need multi-call proofs.

## Phase 5: Check Against Previous Audit

Compare findings against `dev-docs/PROOF_AUDIT.md`:
- Are the previously identified gaps still open?
- Have new proofs been added since the last audit?
- Have any proofs been removed or weakened?
- Did any claimed "GAPS THAT DON'T MATTER" turn out to matter?

## Phase 6: Produce the Report

### Report structure:

#### Executive Summary
- Total proofs: N (Tier 1: X, Tier 2: Y, Tier 3: Z)
- Public functions: N (proven: X, unproven: Y)
- Coverage: X% of public API has some verification
- Critical gaps: N
- Changes since last audit: +N new proofs, -N removed, N modified

#### Proof Inventory Table

| Module | Function | Proof | Tier | Input Space | Properties Verified | Gap |
|--------|----------|-------|------|-------------|--------------------|----|
| otlp.rs | encode_varint | verify_varint_roundtrip | 1 | all u64 | format + roundtrip | None |
| scanner.rs | scan_line | (none) | — | — | — | CRITICAL |

#### Gap Analysis

For each gap, ordered by severity:
1. **What's missing** — specific function or property
2. **Why it matters** — what could go wrong
3. **Recommended proof** — sketch of what the proof should look like
4. **Estimated complexity** — can Kani handle it? Need proptest instead?
5. **Issue reference** — link to existing GitHub issue if any

#### Recommendations

Prioritized list of:
- Proofs to add (with sketched harnesses)
- Proofs to strengthen (e.g., no-panic → oracle)
- Composition proofs to add
- Properties that need TLA+ instead of Kani

#### Update to PROOF_AUDIT.md

If findings differ from `dev-docs/PROOF_AUDIT.md`, produce an updated version of that file.

## Guidelines

- **Read the actual proof code.** Don't just count `#[kani::proof]` annotations — understand what each proof verifies and what it DOESN'T verify.
- **Check solver timeouts.** If a proof uses `#[kani::unwind(N)]` with small N, it may be under-approximating. Note this.
- **Verify oracle independence.** If a proof compares function output against an oracle, the oracle must use a different algorithm. Same-algorithm comparison proves nothing.
- **Think about adversarial inputs.** The scanner processes untrusted data. Proofs must consider malicious JSON, not just well-formed input.
- **Check for `kani::assume`.** Every assumption narrows the input space. Document assumptions and assess whether they're justified.
- **Note CI integration.** Are proofs running in CI? How often? With what timeout?
