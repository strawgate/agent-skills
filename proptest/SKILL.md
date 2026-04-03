---
name: proptest
description: Write effective property-based tests with proptest for Rust. Covers strategy design, oracle testing, state machine testing, shrinking, and integration with fuzz/formal verification. Use when the user says "proptest", "property test", "property-based", "stateful test", "fuzz test", or "write proptests".
argument-hint: [target module, property to test, or "state machine" for stateful testing]
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit, Write
---

# Proptest for Rust

Write high-quality property-based tests that find real bugs, not just exercise happy paths.

## Principles

1. **Properties, not examples.** Don't test `f(3) == 9`. Test `for all x, f(x) >= 0`. The power is in describing what MUST be true for all inputs.
2. **Shrinking is the killer feature.** proptest doesn't just find failing inputs — it minimizes them. Design strategies that shrink well.
3. **Oracles beat assertions.** The strongest test compares your implementation against an independent reference. If you don't have a reference, test roundtrips, invariants, or algebraic properties.
4. **Crash-freedom is the baseline.** `let _ = f(arbitrary_input);` catches panics. Always start here before testing correctness.
5. **State machine testing finds the worst bugs.** Bugs in stateful systems hide in specific sequences of operations. Random operation sequences find what unit tests miss.

## Choosing the Right Property

### The property hierarchy (strongest to weakest)

| Level | Property type | Example | Strength |
|-------|--------------|---------|----------|
| 1 | **Oracle / differential** | `my_parser(input) == reference_parser(input)` | Proves functional equivalence |
| 2 | **Roundtrip / inverse** | `decode(encode(x)) == x` | Proves lossless transformation |
| 3 | **Algebraic** | `reverse(reverse(x)) == x`, `sort(sort(x)) == sort(x)` | Proves structural properties |
| 4 | **Invariant** | `output.len() <= input.len()` | Proves bounds |
| 5 | **Crash-freedom** | `let _ = f(input);` (no panic) | Proves robustness |
| 6 | **Classification** | `prop_assert!(result.is_ok() \|\| result.is_err())` | Nearly vacuous — avoid |

Always aim for the highest level possible. Level 5 (crash-freedom) should be the minimum for any function handling external input.

### Oracle testing tricks

When you don't have a full reference implementation:

- **Naive vs. optimized**: Write a simple O(n²) version, test that the O(n log n) version matches
- **Known-answer tests**: Generate inputs where the answer is known by construction (`sort(already_sorted) == already_sorted`)
- **Cross-implementation**: Compare against a different library (e.g., your JSON parser vs. serde_json)
- **Inverse pair**: If you have `encode`, the test IS `decode(encode(x)) == x` — no separate oracle needed
- **Partial oracle**: Even checking one property of the output against a known-good computation is valuable

### Dealing with semantic differences between oracle and implementation

Real oracle tests often need to handle intentional behavior differences:
```rust
proptest! {
    #[test]
    fn scanner_matches_reference(input in valid_json_lines()) {
        let ours = our_scanner(&input);
        let reference = reference_scanner(&input);
        // Our impl uses first-writer-wins for duplicate keys;
        // reference uses last-writer-wins. Skip inputs with duplicates.
        prop_assume!(!has_duplicate_keys(&input));
        prop_assert_eq!(ours, reference);
    }
}
```

Document WHY you skip certain inputs. `prop_assume!` that silently discards 99% of inputs is a red flag.

## Strategy Design

### Built-in strategies worth knowing

```rust
use proptest::prelude::*;

// Numeric ranges (shrink toward 0)
any::<u64>()                    // full range
0u32..1000u32                   // bounded
(0u32..100, 0u32..100)          // tuple of ranges

// Strings
"[a-z]{1,10}"                   // regex-generated string
any::<String>()                 // arbitrary Unicode
"\\PC{1,100}"                   // printable non-control chars

// Collections
prop::collection::vec(any::<u8>(), 0..256)  // Vec with size range
prop::collection::hash_set(1..100i32, 0..20) // HashSet

// Byte slices (the most useful for parser testing)
prop::collection::vec(any::<u8>(), 0..1024)

// Enums/choices
prop_oneof![
    Just(Action::Read),
    (0..100u32).prop_map(Action::Write),
    any::<u8>().prop_map(Action::Delete),
]
```

### Custom strategies for domain-specific inputs

The most effective proptests use strategies tailored to the input domain:

```rust
// Generate valid JSON lines (much more useful than random bytes)
fn json_line() -> impl Strategy<Value = String> {
    prop::collection::vec(
        (field_name(), json_value()),
        1..8
    ).prop_map(|fields| {
        let obj: Vec<String> = fields.into_iter()
            .map(|(k, v)| format!("\"{}\":{}", k, v))
            .collect();
        format!("{{{}}}", obj.join(","))
    })
}

fn field_name() -> impl Strategy<Value = String> {
    "[a-z_]{1,16}"
}

fn json_value() -> impl Strategy<Value = String> {
    prop_oneof![
        any::<i64>().prop_map(|n| n.to_string()),
        "\"[a-zA-Z0-9 ]{0,32}\"".prop_map(|s| s),
        Just("true".to_string()),
        Just("false".to_string()),
        Just("null".to_string()),
    ]
}
```

### Strategy composition patterns

```rust
// Dependent generation: second value depends on first
(1..100usize).prop_flat_map(|len| {
    (Just(len), prop::collection::vec(any::<u8>(), len..=len))
})

// Filter (use sparingly — high reject rate kills performance)
any::<u32>().prop_filter("must be even", |x| x % 2 == 0)

// Map to transform
any::<Vec<u8>>().prop_map(|bytes| String::from_utf8_lossy(&bytes).into_owned())

// SBoxedStrategy for recursive/complex types
fn json_tree(depth: u32) -> SBoxedStrategy<JsonValue> {
    if depth == 0 {
        prop_oneof![
            any::<i64>().prop_map(JsonValue::Num),
            "[a-z]{1,8}".prop_map(JsonValue::Str),
        ].sboxed()
    } else {
        prop_oneof![
            any::<i64>().prop_map(JsonValue::Num),
            prop::collection::vec(json_tree(depth - 1), 0..4)
                .prop_map(JsonValue::Array),
        ].sboxed()
    }
}
```

### Shrinking considerations

- **Numeric values shrink toward 0.** If your bug only triggers at large values, consider `(large_min..large_max)` ranges.
- **Vecs shrink by removing elements.** The minimal failing case will have the fewest elements that still trigger the bug.
- **`prop_filter` preserves shrinking.** `prop_assume!` does too but wastes more test cases.
- **`prop_flat_map` partially preserves shrinking.** The outer value shrinks; the inner regenerates.
- **Regex strategies shrink well** — they're preferred over `.prop_map(|v| format!(...))` for strings.
- **Custom `Arbitrary` impls control shrinking.** Implement `arbitrary_with` for fine-grained control.

## State Machine Testing

State machine testing is the most powerful proptest pattern. It generates random sequences of operations and checks invariants after each one.

### When to use it

- Data structures with mutation APIs
- Client-server interactions
- Protocol state machines
- Pipeline stages with buffered state
- Anything where bugs hide in operation ORDER, not individual operations

### Structure

```rust
use proptest_state_machine::{
    prop_state_machine, ReferenceStateMachine, StateMachineTest,
};

// 1. Define transitions
#[derive(Clone, Debug)]
enum Transition {
    Push(u32),
    Pop,
    Clear,
}

// 2. Define reference state machine (the "oracle")
#[derive(Clone, Debug)]
struct Reference;

impl ReferenceStateMachine for Reference {
    type State = Vec<u32>;
    type Transition = Transition;

    fn init_state() -> BoxedStrategy<Self::State> {
        Just(Vec::new()).boxed()
    }

    fn transitions(state: &Self::State) -> BoxedStrategy<Self::Transition> {
        if state.is_empty() {
            // Can't pop from empty — only generate valid transitions
            any::<u32>().prop_map(Transition::Push).boxed()
        } else {
            prop_oneof![
                any::<u32>().prop_map(Transition::Push),
                Just(Transition::Pop),
                Just(Transition::Clear),
            ].boxed()
        }
    }

    fn apply(mut state: Self::State, transition: &Self::Transition) -> Self::State {
        match transition {
            Transition::Push(v) => state.push(*v),
            Transition::Pop => { state.pop(); },
            Transition::Clear => state.clear(),
        }
        state
    }

    fn preconditions(state: &Self::State, transition: &Self::Transition) -> bool {
        match transition {
            Transition::Pop => !state.is_empty(),
            _ => true,
        }
    }
}

// 3. Define SUT test
struct MyStackTest;

impl StateMachineTest for MyStackTest {
    type SystemUnderTest = MyStack;
    type Reference = Reference;

    fn init_test(ref_state: &<Self::Reference as ReferenceStateMachine>::State) -> Self::SystemUnderTest {
        MyStack::new()
    }

    fn apply(
        mut sut: Self::SystemUnderTest,
        ref_state: &<Self::Reference as ReferenceStateMachine>::State,
        transition: <Self::Reference as ReferenceStateMachine>::Transition,
    ) -> Self::SystemUnderTest {
        match transition {
            Transition::Push(v) => sut.push(v),
            Transition::Pop => { sut.pop(); },
            Transition::Clear => sut.clear(),
        }
        sut
    }

    fn check_invariants(sut: &Self::SystemUnderTest, ref_state: &<Self::Reference as ReferenceStateMachine>::State) {
        assert_eq!(sut.len(), ref_state.len());
        assert_eq!(sut.to_vec(), *ref_state);
    }
}

// 4. Run it
prop_state_machine! {
    #[test]
    fn my_stack_sm_test(sequential 1..50 => MyStackTest);
}
```

### State machine testing patterns from real projects

**Pipeline ack ordering**: Generate random (send, ack, fail, reject) sequences. Reference tracks expected checkpoint position. SUT is the real pipeline. Check checkpoint matches after each operation.

**Parser batch sequences**: Generate random valid-and-invalid input chunks. Reference accumulates expected outputs. SUT is the streaming parser. Check output matches after each batch.

**Connection pool**: Generate random (connect, query, disconnect, timeout) sequences. Reference tracks expected pool state. SUT is the real pool. Check invariants after each operation.

## Integration Patterns

### Bolero unification (proptest + fuzz + Kani)

A single harness that runs as proptest, libfuzzer, AND Kani proof:

```rust
#[test]
#[cfg_attr(kani, kani::proof, kani::solver(kissat), kani::unwind(9))]
fn roundtrip_test() {
    bolero::check!()
        .with_type::<[u8; 16]>()
        .for_each(|input| {
            let encoded = encode(input);
            let decoded = decode(&encoded).unwrap();
            assert_eq!(input, &decoded[..]);
        });
}
```

Under `cargo test`: randomized proptest. Under `cargo bolero test`: coverage-guided fuzzing. Under `cargo kani`: exhaustive symbolic verification.

**Input size asymmetry**: Fuzzers want large inputs, Kani needs small. Use conditional compilation:
```rust
#[cfg(kani)]
type Input = [u8; 8];   // Kani: small, symbolic
#[cfg(not(kani))]
type Input = Vec<u8>;    // Fuzz/proptest: large, concrete
```

### SIMD equivalence testing

For SIMD implementations, proptest proves SIMD matches scalar for random inputs:

```rust
proptest! {
    #[test]
    fn simd_matches_scalar(input in prop::collection::vec(any::<u8>(), 0..4096)) {
        let scalar_result = find_structural_chars_scalar(&input);
        let simd_result = find_structural_chars_simd(&input);
        prop_assert_eq!(scalar_result, simd_result);
    }
}
```

### Configuration-space exploration

Test that your system works across all valid configurations:

```rust
proptest! {
    #[test]
    fn works_with_any_config(
        batch_size in 1..1000usize,
        max_retries in 0..5u32,
        timeout_ms in 1..10000u64,
        buffer_size in 64..65536usize,
    ) {
        let config = Config { batch_size, max_retries, timeout_ms, buffer_size };
        let system = System::new(config);
        // Run a standard workload
        let result = system.process(&test_data());
        prop_assert!(result.is_ok());
    }
}
```

## Common Pitfalls

### 1. prop_assume! discards too many inputs

If `prop_assume!` rejects > 5% of cases, generate valid inputs directly instead:
```rust
// BAD: 90%+ rejection rate
proptest! {
    #[test]
    fn test_valid_json(s in ".*") {
        prop_assume!(serde_json::from_str::<Value>(&s).is_ok());
        // ...
    }
}

// GOOD: generate valid JSON directly
proptest! {
    #[test]
    fn test_valid_json(s in json_string_strategy()) {
        // ...
    }
}
```

### 2. Not testing boundaries

Proptest biases toward the center of distributions. Explicitly include boundaries:
```rust
prop_oneof![
    Just(0u64),                    // min
    Just(u64::MAX),                // max
    Just(u64::MAX / 2),            // midpoint
    Just(u64::MAX / 2 + 1),        // midpoint + 1 (signed boundary)
    any::<u64>(),                  // random
]
```

### 3. Insufficient test cases

Default is 256 cases. For parser testing against untrusted input, 256 is not enough:
```rust
proptest! {
    #![proptest_config(ProptestConfig::with_cases(2000))]
    #[test]
    fn parser_never_panics(input in any::<Vec<u8>>()) {
        let _ = parse(&input);
    }
}
```

Or via environment: `PROPTEST_CASES=10000 cargo test`.

### 4. Ignoring shrunk output

When proptest finds a failure, READ THE MINIMAL CASE. It tells you exactly what class of input triggers the bug:
- Shrunk to length 0? Empty input not handled.
- Shrunk to a single byte? Off-by-one in length check.
- Specific byte value? That byte has special meaning (delimiter, escape, null).

### 5. Regression files not committed

Always `git add proptest-regressions/`. These files replay exact failures. If you delete them, you lose the regression test.

## Performance Tips

- **Constrain input sizes** for tests that construct complex objects. `vec(any::<u8>(), 0..64)` is much faster than `0..65536`.
- **Use `ProptestConfig::with_cases`** to balance thoroughness and speed. CI can run fewer; local dev can run more.
- **Use `PROPTEST_MAX_SHRINK_ITERS`** to limit shrinking time for expensive tests.
- **Parallelize with `cargo test -- --test-threads=N`** — proptest tests are independent.
- **For very expensive SUTs**, reduce case count but increase input diversity via custom strategies.

## Test Organization

```
crate/
  src/
    parser.rs         # Implementation
    parser/tests.rs   # Unit tests
  tests/
    parser_props.rs   # Property tests (in integration test dir for slow tests)
```

Put fast proptests alongside unit tests. Put slow proptests (state machine, large inputs) in `tests/` so `cargo test` runs the fast ones first.
