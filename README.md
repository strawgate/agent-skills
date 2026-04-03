# Agent Skills

Reusable AI agent skills for Claude Code and VS Code Copilot.

## Skills

| Skill | Description |
|-------|-------------|
| [assign-copilot](assign-copilot/SKILL.md) | Assign GitHub issues to Copilot coding agent with model and custom agent selection |
| [bench-compare](bench-compare/SKILL.md) | Run benchmarks, compare against a baseline, and format results for PR bodies |
| [go-perf](go-perf/SKILL.md) | Go performance optimization — profile, benchmark, isolate, and format results |
| [kani-proof-audit](kani-proof-audit/SKILL.md) | Audit Kani formal verification proofs in a Rust codebase |
| [pr-triage](pr-triage/SKILL.md) | Triage, review, fix, and manage open PRs for a GitHub repo |
| [repo-onboard](repo-onboard/SKILL.md) | Quickly onboard to a repository — docs, structure, recent activity, CI status |
| [research](research/SKILL.md) | Deep research into a library, pattern, technique, or codebase question |

## Usage

Each skill is a standalone `SKILL.md` file with YAML frontmatter and structured instructions. Place skill folders under `~/.claude/skills/` (Claude Code) or reference them in your VS Code agent configuration.
