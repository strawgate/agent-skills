---
name: repo-onboard
description: Quickly onboard to a repository by reading all key docs, understanding architecture, recent changes, and open work. Use when the user says "come up to speed", "onboard", "review the project", "what's the state of things", or "catch me up".
argument-hint: [optional focus area e.g. "pipeline", "CI", "tests"]
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# Repo Onboard

Rapidly build context on the current repository so you can work effectively.

## Phase 1: Project Docs

Read these files if they exist (skip missing ones silently):
- `README.md`
- `DEVELOPING.md` / `CONTRIBUTING.md`
- `CLAUDE.md` / `AGENTS.md`
- `docs/ARCHITECTURE.md` or any architecture doc
- `CHANGELOG.md` (last 2-3 entries only)

## Phase 2: Structure

```bash
# Workspace/package layout
ls -la
cat Cargo.toml 2>/dev/null || cat package.json 2>/dev/null || cat pyproject.toml 2>/dev/null || cat go.mod 2>/dev/null

# Directory structure (depth 2)
find . -maxdepth 2 -type f -name "*.rs" -o -name "*.ts" -o -name "*.go" -o -name "*.py" | head -50
```

## Phase 3: Recent Activity

```bash
# Last 15 commits
git log --oneline -15

# Open PRs
gh pr list --limit 10 --json number,title,author -q '.[] | "#\(.number) \(.author.login): \(.title)"' 2>/dev/null

# Open issues
gh issue list --limit 10 --json number,title -q '.[] | "#\(.number) \(.title)"' 2>/dev/null
```

## Phase 4: CI/Build Status

```bash
# CI health
gh run list --branch $(git symbolic-ref --short HEAD 2>/dev/null || echo main) --workflow CI --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null

# Build system
ls Makefile justfile Taskfile.yml .github/workflows/ 2>/dev/null
```

## Phase 5: Summarize

Present a concise summary:
1. **What this project is** (1-2 sentences)
2. **Tech stack** (language, frameworks, key deps)
3. **Crate/package layout** (if monorepo)
4. **Recent focus** (what the last ~10 commits were about)
5. **Open work** (notable PRs and issues)
6. **CI status** (green/red, any known issues)
7. **Focus area** — if `$ARGUMENTS` specified a focus, dive deeper into that area

If auto-memory is available, check memory for prior context about this project.
