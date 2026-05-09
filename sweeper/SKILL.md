---
name: sweeper
description: Exhaustively find all instances of a specific bug or anti-pattern across a codebase and file a comprehensive report.
argument-hint: "[bug or anti-pattern to search for]"
allowed-tools: Read Grep Glob Bash Edit Write Agent WebFetch
---

# Sweeper — Exhaustive Codebase Search

Find ONE specific type of bug, anti-pattern, or issue and file a comprehensive report listing EVERY instance across the entire codebase.

## When to Use

Use when the user wants a thorough, exhaustive search rather than just finding a few examples. The goal is to enable an engineer to fix an entire category of issues in one pass.

## How to Sweep

### Step 1: Identify the Target

The user will specify what to search for. If not clear, ask:
> What specific anti-pattern or bug should I sweep for?

### Step 2: Audit the Codebase

Search the codebase broadly to understand:
- What code patterns exist around this issue
- How frequently it occurs
- What variations exist

### Step 3: Find Every Instance

Execute a comprehensive search pass to find ALL instances:
- Use `grep` with appropriate patterns
- Check multiple file types if relevant
- Verify matches manually if needed

### Step 4: Categorize and Group

Group findings by:
- File path
- Line number
- Severity (if applicable)
- Type of fix needed

### Step 5: File the Report

File a single issue containing:
1. **Explanation** of the anti-pattern and why it's a problem
2. **Correct fix** pattern to apply
3. **Exhaustive checklist** of every file path and line number

## Output Rules

- **Exhaustive, not sample** — Do not stop at 2-3 examples. List EVERY instance found.
- **Silence is better than noise** — If no genuine instances found, report that and do not file an issue.
- **Specific locations** — Every item must include file path and line number.
- **Actionable fix** — The issue should enable an engineer to fix all instances without further investigation.

## Example Output

```markdown
## Sweep Report: Missing error handling in async functions

### Pattern
Async functions that return `Promise<void>` without try/catch or `.catch()`

### Why It Matters
Unhandled rejections in async functions can cause silent failures and difficult-to-debug issues.

### Fix Pattern
```typescript
// Before
async function processData() {
  await doSomething();
}

// After
async function processData() {
  try {
    await doSomething();
  } catch (error) {
    console.error('processData failed:', error);
    throw error;
  }
}
```

### Exhaustive Instance List

| File | Line | Function |
|------|-------|----------|
| src/services/auth.ts | 23 | `validateToken` |
| src/services/auth.ts | 45 | `refreshSession` |
| src/utils/parser.ts | 78 | `parseInput` |
| src/utils/parser.ts | 112 | `parseResponse` |
| ... | ... | ... |

### Count: 47 instances across 23 files
```
