---
name: research
description: Deep research into a library, pattern, technique, or codebase question. Searches the web, reads docs, explores source code, and produces an actionable report. Use when the user says "research", "investigate", "look into", "dig into", "what can we learn from".
argument-hint: [topic e.g. "arrow IPC compression", "jemalloc vs mimalloc", "how does X project handle Y"]
allowed-tools: Read, Grep, Glob, Bash, Agent, WebSearch, WebFetch
context: fork
agent: Explore
effort: high
---

# Research

Conduct thorough research on `$ARGUMENTS` and produce an actionable report.

## Approach

1. **Web search** — find official docs, blog posts, GitHub issues/PRs, benchmarks, and discussions
2. **Source code** — if the topic involves a specific project/library, read the actual source (clone if needed, or use GitHub code search)
3. **Local codebase** — check how the current project relates to the topic. What do we already have? What's missing?
4. **Cross-reference** — verify claims from one source against others. Don't trust a single blog post.

## Output Format

Structure the report as:

### Summary
2-3 sentence executive summary of findings.

### Key Findings
Numbered list of the most important discoveries. For each:
- What was found
- Why it matters for our project
- Source/evidence

### Patterns to Adopt
Things we should steal/implement, with specific recommendations.

### Pitfalls to Avoid
Mistakes others made that we can learn from.

### Actionable Items
Concrete next steps, categorized by priority:
- **High** — do now
- **Medium** — plan for
- **Low** — note for future

### Sources
Links to everything referenced.

## Guidelines

- Prefer primary sources (official docs, source code, issue threads) over blog summaries
- When researching a GitHub project, look at: README, issues, PRs, commit history, and actual source
- If the topic has performance implications, look for benchmarks and profiling data
- Note version numbers and dates — advice from 2022 may not apply in 2026
- If findings should persist across conversations, suggest saving to memory
