# Workstream Prompt Template

You are handling one workstream inside a larger Codex Cloud fanout for this repository.

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

## Required execution checklist

Use this section when you need prescriptive cloud behavior.

Write explicit items such as:

- `You MUST read A, B, and C before changing anything.`
- `You MUST run X and Y benchmarks or explain exactly why you could not.`
- `You MUST add or update one repo-local deliverable at <path>.`
- `You MUST end with a concrete recommendation label.`

After the hard requirements, add a second section for judgment:

- `After completing the required work, use your judgment to explore adjacent options only if they materially improve the decision quality.`

## Required repo context

Read at least these:

- `[path/to/doc-or-file]`
- `[path/to/doc-or-file]`
- `[path/to/doc-or-file]`

Inspect any additional files needed to make a grounded recommendation or implementation.

If prior cloud tasks or local research matter, summarize the important conclusions here explicitly rather than assuming the agent can see local diffs or hidden task context.

## Deliverable

Write one repo-local output at:

`[path/to/output.md or output file]`

If this is an implementation workstream, also edit the necessary code in the repo and list the changed files in the final note.

## Constraints

- ground everything in the actual repo
- separate hot-path concerns from maintainability concerns
- distinguish product semantics from substrate/library concerns
- be explicit about what you would keep custom and what you would replace
- if benchmarks are needed, say so clearly
- state what not to do
- assume only prompt text + committed repo context are reliably available
- for benchmark work, distinguish `required evidence` from `optional exploration`

## Success criteria

- [State exactly what output or evidence would make this workstream useful.]

## Decision style

End with a decisive recommendation or implementation outcome, not a vague survey.
