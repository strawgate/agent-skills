# Workstream Prompt Template

You are handling one workstream inside a larger Codex Cloud fanout for this repository.

Assume you are operating as a principal engineer with full autonomy to investigate this workstream.
You may inspect the repo deeply, run tests or benchmarks, prototype code, edit files, and use web or doc research when that materially improves the result.
Do not stop at a shallow summary if the right answer requires code inspection, experiments, or comparison of multiple approaches.

## Reality model

Assume you can rely on **only**:

- the committed repository state on the launched branch
- this prompt text

Assume you **cannot** rely on:

- any local branch, worktree, or uncommitted file from the person who launched this task
- hidden thread context from prior tasks
- repo-local fanout artifacts unless they are committed on the launched branch

If the prompt references a local plan, rubric, or prior conclusion, treat only
the text pasted here as canonical unless the file is actually present on the
launched branch.

## Objective

[State the exact question or execution goal.]

## Why this workstream exists

[Summarize the prior finding, tension, or architectural question in plain language. Do not rely on external task memory.]

## Mode

Choose one and make it explicit:

- research
- implementation
- prototype
- benchmark
- audit

Also state the expected autonomy level:

- recommendation only
- investigate + prototype
- investigate + implement + test
- benchmark and compare alternatives

If the problem is design-heavy, say explicitly whether the agent should:

- choose the single best direction after investigation
- compare 2-3 credible options before choosing
- produce multiple implementation shapes if that helps the fan-in later

## Operating assumptions

Customize as needed, but good defaults are:

- `You are expected to investigate this like a principal engineer, not merely summarize nearby files.`
- `Use repo inspection, docs, tests, benchmarks, and web research as needed to produce a grounded result.`
- `If the problem has meaningful design space, compare multiple credible approaches before recommending one.`
- `If a focused prototype, benchmark, or code change would materially improve the answer, do it.`
- `Leave behind repo-local artifacts that make the result easy to review during fan-in.`
- `End with a decisive recommendation, implementation outcome, or benchmark conclusion.`
- `Spend at least 10 minutes doing real investigation before finalizing unless tooling blocks you.`
- `Do not stop once you have one plausible answer; keep working until the remaining new findings are likely low-value noise.`
- `Use confidence thresholds so the final output favors high-signal findings over quantity.`
- `If you change code, go beyond "it runs": add or improve meaningful tests/proofs in the touched risk area and report what coverage depth was added.`
- `Before finalizing, run a self-review focused on correctness/regression risk/test gaps and address high-confidence issues you find.`

## Required execution checklist

Use this section when you need prescriptive cloud behavior.

Write explicit items such as:

- `You MUST read A, B, and C before changing anything.`
- `You MUST run X and Y benchmarks or explain exactly why you could not.`
- `You MUST add or update one repo-local deliverable at <path>.`
- `You MUST end with a concrete recommendation label.`
- `You MUST compare the main approach against at least one plausible alternative.`
- `You MUST explain what evidence would change your recommendation.`
- `You MUST prototype or benchmark if that is the shortest path to a reliable answer.`
- `You MUST, for implementation workstreams, (1) get the change working, (2) meaningfully strengthen verification/test coverage for the changed behavior, and (3) run a self-review pass before returning.`
- `You MUST classify findings by confidence; only promote findings at roughly 0.7 confidence or higher.`
- `You MUST downgrade uncertain items to watch items instead of mixing them into the main recommendation.`
- `You MUST continue the audit until the remaining new items are likely throwaway noise, duplicates, or low-confidence suspicions.`

After the hard requirements, add a second section for judgment:

- `After completing the required work, use your judgment to explore adjacent options only if they materially improve the decision quality.`

## Required repo context

Read at least these:

- `[path/to/doc-or-file]`
- `[path/to/doc-or-file]`
- `[path/to/doc-or-file]`

Inspect any additional files needed to make a grounded recommendation or implementation.

If prior cloud tasks or local research matter, summarize the important conclusions here explicitly rather than assuming the agent can see local diffs or hidden task context.

If a local or branch-specific diff matters, include a section like:

- `Canonical diff context you must use`
- `git diff --stat` summary
- changed-file list
- commit list if helpful
- exact patch hunks or excerpted diffs for the files/functions under review

Do not assume the cloud agent can see your local diff unless you paste it here.

If the task depends on a shared rubric or checklist, include it inline or
summarize it inline unless you have verified the file exists on the launched
branch.

If you are launching against the default branch while reasoning about an unmerged PR or local branch, include a section like:

- `Branch-specific context you must treat as canonical`
- the intended branch name
- the key files changed
- the important behavior changes already under discussion
- the exact edge cases or regressions that motivated the work

Do not assume the cloud agent can access that branch unless you have verified it.

If this workstream depends on non-obvious constraints, include them here explicitly:

- performance or hot-path sensitivity
- verification boundaries
- crate layering constraints
- rollout or compatibility assumptions
- what should remain custom vs what may be replaced with a library

## Deliverable

Write one repo-local output at:

`[path/to/output.md or output file]`

If this is an implementation workstream, also edit the necessary code in the repo and list the changed files in the final note.

Good deliverables often include:

- a memo with recommendation + alternatives + risks
- a prototype patch plus a short evaluation note
- benchmark output with interpretation
- a migration or sequencing plan with concrete file/module touch points

## Constraints

- ground everything in the actual repo
- separate hot-path concerns from maintainability concerns
- distinguish product semantics from substrate/library concerns
- be explicit about what you would keep custom and what you would replace
- if benchmarks are needed, say so clearly
- state what not to do
- assume only prompt text + committed repo context are reliably available
- assume that if a file is not committed on the launched branch, you cannot rely on it
- for benchmark work, distinguish `required evidence` from `optional exploration`
- if you leave the repo unchanged, explain why that was the right call
- if a better answer would require a different seam or plan than the prompt assumes, say so clearly instead of forcing the wrong shape

## Success criteria

- [State exactly what output or evidence would make this workstream useful.]
- [If relevant, state what kind of disagreement or alternative the agent should surface rather than suppress.]

## Decision style

End with a decisive recommendation or implementation outcome, not a vague survey.

When appropriate, end with:

- `Recommendation: <label>`
- `Primary rationale: <1-3 bullets>`
- `Alternatives considered: <short list>`
- `What would change my mind: <specific evidence>`
