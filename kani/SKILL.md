---
name: kani
description: Write and audit Kani proof harnesses for Rust. Covers exhaustive vs bounded proofs, function contracts, compositional verification, solver selection, vacuity detection, and integration with proptest/bolero. Use when the user says "kani", "kani proof", "formal verification", "bounded model check", "write a proof", or "verify this function".
argument-hint: [function to verify, module path, or "audit" to audit existing proofs]
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit, Write
effort: high
---

# Kani Verification for Rust

Write and audit Kani proof harnesses that provide mathematical guarantees, not just test coverage.

## Principles

1. **`kani::any()` is a universal quantifier, not random sampling.** The SAT solver considers ALL possible values simultaneously. A passing proof is a mathematical proof that no input causes failure.
2. **Vacuous proofs prove nothing.** If `kani::assume()` eliminates all interesting inputs, the proof succeeds trivially. Always add `kani::cover!()` to guard against this.
3. **Compositional proofs scale; monolithic proofs don't.** For deep call chains, use function contracts (`requires`/`ensures`) to decompose into per-function proofs, then compose with `stub_verified`.
4. **Under-unwinding is caught; over-unwinding wastes time.** If unwind is too low, Kani reports an unwinding assertion failure (sound). If too high, verification takes longer but remains correct.
5. **Different solvers have dramatically different performance.** The default (cadical) is fine for most proofs. Switch to kissat for byte-processing proofs, z3 for arithmetic-heavy ones.

## When to Use Kani vs. Alternatives

| Scenario | Use | Why |
|----------|-----|-----|
| Pure function, small fixed-width inputs (u8, u16, u32, u64) | **Kani** | Exhaustive — covers ALL values |
| Byte-slice parsing, ≤32 bytes | **Kani** (bounded) | SAT solver handles byte operations well |
| State machine, ≤8 transitions | **Kani** | Exhaustive over all state×event pairs |
| Large/variable-size inputs | **proptest** | Kani scales poorly on heap collections |
| Async code | **proptest** | Kani doesn't support async |
| SIMD correctness vs scalar | **proptest** | Compare two implementations on random inputs |
| Protocol liveness / temporal properties | **TLA+** | Kani cannot express "eventually" or "always" |
| Unsafe pointer arithmetic | **Kani + Miri** | Kani proves bounds, Miri detects UB at runtime |

## Writing Proof Harnesses

### Basic structure

```rust
#[cfg(kani)]
mod verification {
    use super::*;

    #[kani::proof]
    fn verify_function_property() {
        // 1. Generate symbolic inputs
        let input: u64 = kani::any();

        // 2. Constrain inputs (preconditions)
        kani::assume(input < 4096);

        // 3. Call function under test
        let result = my_function(input);

        // 4. Assert postconditions
        assert!(result <= input);

        // 5. Guard against vacuity
        kani::cover!(result > 0, "non-trivial case");
        kani::cover!(result == 0, "zero case");
    }
}
```

### Naming convention

`verify_<function>_<property>`

Examples:
- `verify_parse_varint_roundtrip`
- `verify_scan_line_no_panic`
- `verify_state_machine_invariant`
- `verify_encode_field_size_bound`

### Proof categories

#### 1. Crash-freedom (no panic)

The minimum proof — function doesn't panic on any valid input:

```rust
#[kani::proof]
fn verify_parse_never_panics() {
    let buf: [u8; 16] = kani::any();
    let len: usize = kani::any_where(|&l| l <= 16);
    let _ = parse(&buf[..len]);
    // Kani automatically checks for panics, overflow, OOB
}
```

#### 2. Oracle/correctness

Function produces the same result as a reference implementation:

```rust
#[kani::proof]
fn verify_fast_matches_naive() {
    let input: u64 = kani::any();
    let fast = count_bits_fast(input);
    let naive = count_bits_naive(input);
    assert_eq!(fast, naive);
}
```

#### 3. Roundtrip

Encode-decode produces the original value:

```rust
#[kani::proof]
fn verify_varint_roundtrip() {
    let value: u64 = kani::any();
    let mut buf = [0u8; 10];
    let encoded_len = encode_varint(value, &mut buf);
    let (decoded, decoded_len) = decode_varint(&buf[..encoded_len]).unwrap();
    assert_eq!(value, decoded);
    assert_eq!(encoded_len, decoded_len);
}
```

#### 4. State machine invariant

All state transitions preserve invariants:

```rust
#[kani::proof]
fn verify_state_machine_invariant() {
    let state: State = kani::any();
    let event: Event = kani::any();

    kani::assume(state.is_valid()); // precondition

    if let Some(next_state) = state.transition(event) {
        assert!(next_state.is_valid()); // invariant preserved
        // Verify specific properties
        assert!(next_state.committed <= next_state.processed);
    }
}
```

#### 5. Bounded-size correctness

For functions that take byte slices, use `any_slice_of_array`:

```rust
#[kani::proof]
#[kani::unwind(34)]  // max_size + 2
fn verify_framer_correctness() {
    const MAX_SIZE: usize = 32;
    let arr: [u8; MAX_SIZE] = kani::any();
    let input = kani::slice::any_slice_of_array(&arr);

    let result = frame_lines(input);

    // Oracle: count newlines manually
    let expected_lines = input.iter().filter(|&&b| b == b'\n').count();
    assert_eq!(result.line_count(), expected_lines);
}
```

## Function Contracts (Compositional Verification)

### When to use contracts

Use contracts when:
- A function is called by multiple callers you want to verify
- The call chain is deep (>3 levels) and monolithic proof is too slow
- You want to prove a function's interface, then use the proven interface in higher-level proofs

### Writing contracts

```rust
#[cfg_attr(kani, kani::requires(denominator != 0))]
#[cfg_attr(kani, kani::ensures(|result| *result <= numerator))]
pub fn safe_divide(numerator: u64, denominator: u64) -> u64 {
    numerator / denominator
}
```

Use `#[cfg_attr(kani, ...)]` so contracts don't affect normal builds.

### Verifying contracts

```rust
#[cfg(kani)]
#[kani::proof_for_contract(safe_divide)]
fn verify_safe_divide_contract() {
    let n: u64 = kani::any();
    let d: u64 = kani::any();
    safe_divide(n, d);  // Kani checks requires/ensures automatically
}
```

### Using verified contracts as stubs

```rust
#[cfg(kani)]
#[kani::proof]
#[kani::stub_verified(safe_divide)]
fn verify_compute_average() {
    let values: [u64; 4] = kani::any();
    let avg = compute_average(&values); // internally calls safe_divide
    assert!(avg <= u64::MAX);
}
```

`stub_verified` replaces the real function with its contract abstraction — the callee's code is NOT re-verified, only its contract is assumed. This collapses verification cost.

### Contract composition pattern for parsers

```rust
// 1. Leaf functions get contracts
#[cfg_attr(kani, kani::requires(buf.len() >= 1))]
#[cfg_attr(kani, kani::ensures(|result| result.bytes_consumed <= buf.len()))]
fn parse_field(buf: &[u8]) -> ParseResult { ... }

// 2. Verify each leaf independently
#[cfg(kani)]
#[kani::proof_for_contract(parse_field)]
fn verify_parse_field() { ... }

// 3. Mid-level functions use stub_verified on leaves
#[cfg(kani)]
#[kani::proof]
#[kani::stub_verified(parse_field)]
fn verify_parse_record() {
    let arr: [u8; 32] = kani::any();
    let input = kani::slice::any_slice_of_array(&arr);
    let _ = parse_record(input);
}
```

## Solver Selection

| Solver | Best for | Example speedup |
|--------|----------|-----------------|
| `cadical` (default) | General-purpose, good starting point | Baseline |
| `kissat` | Byte-processing, bitmask operations | Up to 265x on some harnesses |
| `minisat` | Simple proofs | Sometimes fastest, sometimes slowest |
| `z3` | Arithmetic-heavy (multiplication, division) | Better for non-linear arithmetic |
| `bitwuzla` | Bit-vector operations | Good for shift/rotate operations |

```rust
#[kani::proof]
#[kani::solver(kissat)]  // try this if default is slow
fn verify_bitmask_operation() { ... }
```

**Strategy:** Start with default. If a proof takes >10 seconds, try kissat. If still slow with bit-vector operations, try bitwuzla. For arithmetic, try z3.

## Unwind Bounds

`#[kani::unwind(N)]` sets the maximum loop iterations Kani will explore. N must be at least `max_iterations + 1` (the extra iteration checks the exit condition).

```rust
#[kani::proof]
#[kani::unwind(17)]  // handles up to 16 iterations
fn verify_loop_based_function() {
    let arr: [u8; 16] = kani::any();
    let result = process_array(&arr);
    assert!(result.is_valid());
}
```

### Rules for setting unwind

| Loop pattern | Unwind value |
|-------------|-------------|
| `for i in 0..N` | N + 1 |
| `while condition` with max N iters | N + 1 |
| Loop with `break`/`continue` | N + 2 or N + 3 (be generous) |
| Nested loops: outer M, inner N | (M + 1) × (N + 1) (worst case) |
| No loops | Not needed |

**Soundness guarantee:** If N is too small, Kani reports an unwinding assertion failure. You cannot accidentally "prove" something by under-unwinding.

## Vacuity Detection

### The vacuity problem

A proof with `kani::assume()` that eliminates all paths succeeds trivially — it proves "there are no valid inputs," not "the function is correct."

### Prevention patterns

```rust
#[kani::proof]
fn verify_parser_correctness() {
    let buf: [u8; 8] = kani::any();
    let result = parse(&buf);

    // These covers prove the proof is non-vacuous
    kani::cover!(result.is_ok(), "at least one input parses");
    kani::cover!(result.is_err(), "at least one input fails");
    kani::cover!(result.as_ref().map_or(false, |r| r.len > 0), "non-empty parse");
}
```

### When covers are necessary vs. optional

| Proof type | Covers needed? |
|-----------|---------------|
| Has `kani::assume()` or `any_where()` | **YES** — verify interesting paths survive |
| Complex logic where vacuity isn't obvious | **YES** |
| `proof_for_contract` | No — Kani auto-checks contract satisfiability |
| Unconstrained inputs, no assumptions | Optional but recommended |
| Trivial crash-freedom (only checking no-panic) | Optional |

### Reading cover output

```
Check 1: verify_parser.cover.1
  - Status: SATISFIED    ← Good: this path is reachable
Check 2: verify_parser.cover.2  
  - Status: UNSATISFIABLE ← BAD: no input reaches this path!
```

If a cover is UNSATISFIABLE, investigate:
1. Are your `assume` constraints too tight?
2. Is the condition actually unreachable (legitimate)?
3. Did you accidentally prove something vacuously?

## Auditing Existing Proofs

### Tautological proof detection

A proof is tautological if it cannot fail regardless of the implementation:

```rust
// BAD: proves nothing about my_function
#[kani::proof]
fn verify_something() {
    let x: u32 = kani::any();
    if x < 100 {
        let result = my_function(x);
    }
    // No assertions! Kani only checks for panics in the `if` body.
    // If my_function doesn't panic, this always passes.
}
```

### Proof-skipping detection

The proof guards around the interesting case instead of testing it:

```rust
// BAD: skips the overflow case entirely
#[kani::proof]
fn verify_no_overflow() {
    let a: u64 = kani::any();
    let b: u64 = kani::any();
    if a.checked_add(b).is_some() {
        let result = a + b;  // Only tested when it DOESN'T overflow
    }
    // Should instead verify the production code handles overflow
}
```

### Assume-coverage mismatch

Every `kani::assume()` should have a justification — does the real system enforce this precondition?

| Assume | Justified if | Unjustified if |
|--------|-------------|----------------|
| `assume(len <= 32)` | Input is always ≤32 bytes in the real system | External input can be any size |
| `assume(value != 0)` | Caller validates non-zero (and has its own proof) | No caller validation exists |
| `assume(state.is_valid())` | State invariant is proven to hold at every transition | State can be corrupted by failed operations |

## Kani Sweet Spots and Limits

### What works well (aim for these)

| Pattern | Practical max input | Typical time |
|---------|-------------------|--------------|
| u64 bitmask operations (no loops) | Full 64-bit range | < 5s |
| Enum state machines (all transitions) | All state×event pairs | < 10s |
| Integer arithmetic (loop-free) | Full type range | < 5s |
| Roundtrip encode/decode (fixed-size) | Full type range | < 30s |
| Byte-slice parsing | ≤32 bytes | 10s-5min |
| State transition sequences | ≤8 steps | < 2min |

### What hits limits

| Pattern | Practical max | Workaround |
|---------|--------------|------------|
| Simple byte-slice loop | ~100 bytes | Set explicit unwind |
| Complex byte parsing | ~10-20 bytes | Compositional contracts |
| Vec operations | ~8-15 elements | Use arrays or BoundedArbitrary |
| HashMap entries | ~1-5 entries | Use BTreeMap or bitmask |
| Iterator chains | Same as loop bounds | Explicit unwind |

### What doesn't work

- Async/await
- Inline assembly
- Concurrency (compiled as sequential)
- Temporal properties (use TLA+)
- Nondeterministic-size heap collections
- Floating point precision (trig functions over-approximated)

## CI Integration

```yaml
- name: Kani Proofs
  run: |
    cargo kani -p my-crate              # all proofs
    # Or specific proofs for PR-changed modules:
    cargo kani --harness verify_changed_function
```

### Proof CI strategy

- **All proofs on every PR** if total time < 15 minutes
- **Changed-module proofs on PR, all proofs nightly** if total > 15 minutes
- **Cache Kani setup** (the CBMC download is ~2GB)

## Practical Workflow

### Adding verification to a new function

1. **Write the function first.** Pure logic, no IO.
2. **Choose the tier:**
   - Can Kani verify ALL inputs? (small fixed-width) → Tier 1 (exhaustive)
   - Can Kani verify bounded inputs? (byte slices ≤256) → Tier 2 (bounded)
   - Neither → Tier 3 (proptest)
3. **Write crash-freedom proof first** (Level 5 — easiest).
4. **Upgrade to oracle/roundtrip** (Level 1-2) if a reference exists.
5. **Add covers** for any proof with assumptions.
6. **Run locally:**
   ```bash
   cargo kani --harness verify_my_function
   ```
7. **If slow (>30s),** try `#[kani::solver(kissat)]`.
8. **If too slow for Kani,** fall back to proptest.

### Auditing existing proofs

1. List all proofs: `grep -rn '#\[kani::proof\]' src/`
2. For each proof, check:
   - Does it assert something meaningful? (not just crash-freedom)
   - Does it have `kani::cover!()` for any `assume`/`any_where`?
   - Is the unwind bound sufficient?
   - Does the proof match the current code? (function signature changes)
   - Is the oracle independent? (not just re-implementing the same algorithm)
3. Cross-reference with public API: which public functions lack proofs?
