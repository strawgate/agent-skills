---
name: bug-hunt
description: Generic, evidence-driven bug hunting for any repository. Coordinate multiple agents through a shared results directory, avoid duplicate work, reproduce real user-impacting bugs, and write structured findings that can become issues or fixes.
---

# Bug Hunt Skill

Use the repo-local `bug-hunt/skill.md` as the canonical workflow.

Key points:
- generic, not language- or framework-specific
- one markdown file per candidate
- optional `claims/`, then `candidates/`, then `verified/<severity>/`
- build a slice-local issue cache up front
- skip already-known issues unless you have materially new evidence
- in sweep mode, keep harvesting distinct candidates until the slice is exhausted or the quota is met
