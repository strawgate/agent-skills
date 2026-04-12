# Agent Skills

Reusable AI agent skills for Claude Code, Codex, and VS Code Copilot.

## Skills

| Skill | Description |
|-------|-------------|
| [assign-copilot](assign-copilot/SKILL.md) | Assign GitHub issues to Copilot coding agent with model and custom agent selection |
| [assign-codex-fanin](assign-codex-fanin/SKILL.md) | Collect Codex Cloud task outputs, inspect attempts, and synthesize one recommendation or integration plan |
| [assign-codex-fanout](assign-codex-fanout/SKILL.md) | Split a task into workstreams and launch Codex Cloud fanout with multiple attempts per workstream |
| [assign-jules](assign-jules/skill.md) | Assign GitHub issues to Jules, review completed sessions, answer blocked sessions, and archive finished work |
| [bench-compare](bench-compare/SKILL.md) | Run benchmarks, compare against a baseline, and format results for PR bodies |
| [bug-hunt](bug-hunt/skill.md) | Hunt for real production-impacting bugs, file issues, and periodically land fixes with regression coverage |
| [find-stale-issues](find-stale-issues/SKILL.md) | Audit open issues against PRs and code to find stale, resolved, duplicate, and overlapping work |
| [follow-the-pr](follow-the-pr/SKILL.md) | Follow a PR after pushing by polling for new feedback, CI changes, and merge readiness |
| [formal-coverage-audit](formal-coverage-audit/SKILL.md) | Audit formal and property verification coverage and produce a prioritized proof plan |
| [go-perf](go-perf/SKILL.md) | Go performance optimization — profile, benchmark, isolate, and format results |
| [kani](kani/SKILL.md) | Write and audit Kani proof harnesses — exhaustive verification, function contracts, solver selection |
| [kani-proof-audit](kani-proof-audit/SKILL.md) | Audit Kani formal verification proofs in a Rust codebase |
| [organize-meta-issues](organize-meta-issues/SKILL.md) | Plan and maintain bite-size meta issues and phased issue trees for bugs, features, and refactors |
| [organize-work-items](organize-work-items/SKILL.md) | Create and maintain work-unit issues that schedule low-conflict, agent-sized batches of work |
| [pr-triage](pr-triage/SKILL.md) | Triage, review, fix, and manage open PRs for a GitHub repo |
| [proptest](proptest/SKILL.md) | Property-based testing — strategy design, oracle testing, state machine testing, bolero integration |
| [repo-onboard](repo-onboard/SKILL.md) | Quickly onboard to a repository — docs, structure, recent activity, CI status |
| [refresh-yourself](refresh-yourself/SKILL.md) | Refresh project context after time away using a generated snapshot of PRs/issues/commits/files |
| [research](research/SKILL.md) | Deep research into a library, pattern, technique, or codebase question |
| [tla-audit](tla-audit/SKILL.md) | Audit TLA+/TLC specifications — property strength, liveness, abstraction gaps, state space coverage |

## Usage

Each skill is a standalone `SKILL.md` file with YAML frontmatter and structured instructions. Place skill folders under your agent's skills directory (for example `~/.claude/skills/`) or reference them in your editor or agent configuration.
