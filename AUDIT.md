# Skills Audit — April 2026

## TL;DR

**27 skills** across the repo. The `_shared/` extraction pattern is sound — 3 skills already delegate `fetch-repo-data.sh` and 1 delegates `fetch-pr-context.sh` correctly. But significant duplication and missing scripts remain:

| Category | Count | Priority |
|---|---|---|
| Duplicate code to extract into `_shared/` | 5 patterns | High |
| Inline SKILL.md workflows that should be scripts | 4 skills | High |
| Naming/structural inconsistencies | 3 items | Medium |
| Missing scripts to simplify workflows | 6 candidates | Medium |
| Robustness/portability bugs | 5 items | Low-Medium |
| Stale worktree mirror to clean up | 1 tree | Low |

---

## 1. Duplicate Code → Extract to `_shared/`

### 1a. Jules API library (`_shared/jules-api/jules-lib.sh`)

`BASE_URL`, auth header construction, session listing, and session detail fetching are copy-pasted across **5 scripts**:

- `assign-jules/scripts/assign.sh`
- `assign-jules/scripts/reply.sh`
- `assign-jules/scripts/archive.sh`
- `assign-jules/scripts/check-questions.sh`
- `assign-jules/scripts/review-all.sh`

**Proposed:** Create `_shared/jules-api/jules-lib.sh` exporting:
```bash
jules_base_url()      # returns BASE_URL
jules_auth_header()   # returns "-H Authorization: Bearer $JULES_API_KEY"
jules_list_sessions() # paginated session listing
jules_get_session()   # single session detail
jules_send_message()  # send prompt to session
```
Each script sources it and calls helpers instead of re-implementing curl patterns.

### 1b. Review thread GraphQL (`_shared/github-review-threads/`)

The same `reviewThreads` query + `resolveReviewThread` / `unresolveReviewThread` mutations appear in **4 places**:

- `resolve-pr-threads/SKILL.md` (inline)
- `pr-triage/SKILL.md` (inline)
- `_shared/github-pr-context/scripts/fetch-pr-context.sh`
- `follow-the-pr/scripts/wait-for-pr-activity.sh`

**Proposed:** Create `_shared/github-review-threads/scripts/review-threads.sh` with subcommands:
```bash
review-threads.sh list   OWNER/REPO PR_NUMBER   # paginated list
review-threads.sh resolve   THREAD_ID            # resolve
review-threads.sh unresolve THREAD_ID            # unresolve
review-threads.sh count-unresolved OWNER/REPO PR_NUMBER
```
Then `resolve-pr-threads/SKILL.md` references the script, `pr-triage` calls it, and `follow-the-pr` uses the count helper.

### 1c. Issue-to-prompt builder (`_shared/github-issue-prompt/`)

`assign-claude/SKILL.md`, `web-session/SKILL.md`, and `assign-jules/scripts/assign.sh` all:
1. Run `gh issue view` to get title/body/comments
2. Run `gh repo view` to get repo context
3. Build a structured prompt with visibility/branch-scope constraints
4. Launch a remote agent

**Proposed:** Create `_shared/github-issue-prompt/scripts/build-issue-prompt.sh`:
```bash
build-issue-prompt.sh OWNER/REPO ISSUE_NUMBER [--branch BRANCH]
# Outputs a structured prompt to stdout
```
Skills then pipe the output to their agent-specific launcher.

### 1d. PR snapshot for polling (`_shared/github-pr-snapshot/`)

`follow-the-pr/scripts/wait-for-pr-activity.sh` re-implements a lighter version of what `_shared/github-pr-context/scripts/fetch-pr-context.sh` does. Both fetch comments, reviews, review threads, and check statuses.

**Proposed:** Factor a lightweight `pr-snapshot.sh` out of the full context bundle that returns a normalized JSON blob suitable for diffing between poll cycles. `follow-the-pr` and `pr-triage/build-merge-checklist.sh` both consume it.

### 1e. Meta-issue parsing (`_shared/github-meta-parser/`)

`organize-meta-issues/scripts/summarize-meta-structure.sh` contains a substantial inline Python script for detecting meta issues, extracting child references, and generating summaries. `organize-work-items` already delegates to it, but:
- The Python logic is embedded in a heredoc inside bash
- `organize-work-items/scripts/summarize-work-unit-structure.sh` has its own issue-number regex that doesn't match the meta parser's pattern

**Proposed:** Extract the Python into `_shared/github-meta-parser/scripts/parse_meta_issues.py` as a proper Python script with CLI args. Both summarize scripts call it.

---

## 2. Inline Workflows → Real Scripts

### 2a. `assign-copilot/SKILL.md`

The entire workflow is inline GraphQL snippets. This is the most fragile skill because:
- Complex multi-step GraphQL (repo lookup → actor lookup → issue ID → mutation)
- Custom HTTP headers (`Gh-Next: copilot_chat_dotcom_agent_integration`)
- No error handling

**Proposed:** `assign-copilot/scripts/assign-to-copilot.sh OWNER/REPO ISSUE_NUMBER [--agent AGENT_FILE] [--model MODEL]`

### 2b. `resolve-pr-threads/SKILL.md`

Three inline GraphQL commands that are a natural script (see 1b above — shared extraction covers this).

### 2c. `find-stale-issues/SKILL.md`

Contains extensive inline jq loops and audit logic that runs against cached issue JSON. The actual audit algorithm — PR-reference checking, duplicate detection, comment freshness — is all prose + snippets.

**Proposed:** `find-stale-issues/scripts/classify-issues.sh OWNER/REPO [OUT_DIR]` that:
1. Calls `fetch-repo-data.sh`
2. Runs the classification logic
3. Outputs a structured report

### 2d. `bench-compare/SKILL.md`

The stash/checkout/benchmark/compare flow is entirely instructions. The risky `git stash` + branch-switch pattern should be automated with safety checks.

**Proposed:** `bench-compare/scripts/run-comparison.sh [--baseline BRANCH] [--command CMD]` that:
1. Detects build system
2. Runs current benchmark
3. Safely switches to baseline, runs benchmark
4. Returns to original state
5. Outputs comparison table

---

## 3. Naming & Structural Inconsistencies

### 3a. `SKILL.md` vs `skill.md`

Two skills use lowercase:
- `assign-jules/skill.md`
- `bug-hunt/skill.md`

All others use `SKILL.md`. Any loader that pattern-matches `SKILL.md` will miss these.

**Fix:** Rename both to `SKILL.md`.

### 3b. Top-level `bug-hunt.md` pointer

`bug-hunt.md` at the repo root is a thin redirect to `bug-hunt/skill.md`. This is the only skill with a root-level pointer file.

**Fix:** Remove `bug-hunt.md` and rename `bug-hunt/skill.md` → `bug-hunt/SKILL.md`.

### 3c. `README.md` claims all skills use `SKILL.md`

The README says each skill is a standalone `SKILL.md`, which is false for the two above.

**Fix:** Update after renaming, or if keeping mixed casing, document both patterns.

---

## 4. Missing Scripts to Add

### 4a. `_shared/detect-build-system.sh`

Multiple skills (bench-compare, make-into-pr, burning-down-work-units) need to detect the repo's build system (cargo, go, npm, make, just, etc.) and its test/bench/lint commands.

```bash
detect-build-system.sh [REPO_ROOT]
# Outputs JSON: {"build_system": "cargo", "test_cmd": "cargo test", "bench_cmd": "cargo bench", ...}
```

### 4b. `_shared/safe-baseline-switch.sh`

Both bench-compare and go-perf need to safely:
1. Stash or commit current work
2. Switch to a baseline branch/commit
3. Run a command
4. Switch back and restore state

This is error-prone and should be a single helper.

```bash
safe-baseline-switch.sh --baseline origin/main --command "cargo bench" --output /tmp/baseline.txt
```

### 4c. `bug-hunt/scripts/init-hunt.sh`

The bug-hunt skill defines a precise directory structure (`tmp/bug-hunt/{claims,candidates,verified}/`) but leaves creation to the agent. A setup script would enforce the layout.

```bash
init-hunt.sh [--dir DIR] [--mode sweep|single]
```

### 4d. `formal-coverage-audit/scripts/inventory-proofs.sh`

The formal-coverage-audit skill requires cataloging all Kani harnesses, proptest functions, and TLA+ specs. This grep/rg-based inventory is mechanical and should be scripted.

```bash
inventory-proofs.sh [REPO_ROOT]
# Outputs JSON inventory of all formal verification artifacts
```

### 4e. `refresh-yourself/scripts/` + `repo-onboard/scripts/` unification

`refresh-yourself` has a script; `repo-onboard` does not. They overlap significantly (both fetch recent commits, open PRs/issues, repo structure). Consider:
- Making `repo-onboard` delegate to `refresh_snapshot.sh` with a `--full` flag
- Or extracting the common bits into `_shared/repo-snapshot/`

### 4f. Codex cloud helper library

`assign-codex-fanout` and `assign-codex-fanin` are tightly coupled but share no code. Both interact with Codex Cloud APIs, parse task IDs, and manage manifests.

**Proposed:** `_shared/codex-cloud/codex-lib.py` with:
- Environment auto-detection
- Task launch wrapper
- Task status/diff fetcher
- Manifest read/write helpers

---

## 5. Robustness & Portability Fixes

| File | Issue | Fix |
|---|---|---|
| `_shared/github-repo-inventory/scripts/fetch-repo-data.sh:24` | Uses `python` instead of `python3` | Change to `python3` |
| `assign-claude/scripts/launch-cloud-fanout.sh` | JSON manifest built with string interpolation (not escaped) | Use `jq` to build JSON safely |
| `assign-jules/scripts/assign.sh` | Calls `gh issue view` 3 times per issue instead of once | Cache the first call |
| `assign-jules/scripts/*.sh` | No pagination beyond first page (100 sessions) | Add `nextPageToken` loop |
| `organize-work-items/scripts/summarize-work-unit-structure.sh` | `grep -oP '#\d+'` matches any `#123` in prose, URLs, etc. | Use the meta parser's stricter regex |
| `assign-jules/scripts/archive.sh` | Brittle `date` parsing (GNU vs BSD) | Use `python3 -c` for portable date math |
| `follow-the-pr/scripts/wait-for-pr-activity.sh` | No backoff or jitter in polling loop | Add exponential backoff with jitter |

---

## 6. Stale Worktree Mirror

`.claude/worktrees/nifty-jingling-liskov/` is a full mirror of the skills directory (59 files). It appears to be a leftover from a Claude Code worktree session. Any glob-based tooling will double-count files.

**Fix:** Delete `.claude/worktrees/` if the session is complete, or add it to `.gitignore`.

---

## 7. Summary of Proposed `_shared/` Structure

```
_shared/
├── github-pr-context/          # (existing) full PR bundle
├── github-repo-inventory/      # (existing) issue/PR inventory
├── github-review-threads/      # NEW: list/resolve/unresolve review threads
│   └── scripts/
│       └── review-threads.sh
├── github-issue-prompt/        # NEW: issue → structured agent prompt
│   └── scripts/
│       └── build-issue-prompt.sh
├── github-pr-snapshot/         # NEW: lightweight PR state for polling
│   └── scripts/
│       └── pr-snapshot.sh
├── github-meta-parser/         # NEW: meta-issue detection & child extraction
│   └── scripts/
│       └── parse_meta_issues.py
├── jules-api/                  # NEW: Jules REST API library
│   └── jules-lib.sh
├── codex-cloud/                # NEW: Codex Cloud API helpers
│   └── codex-lib.py
├── detect-build-system/        # NEW: repo build system detection
│   └── scripts/
│       └── detect-build-system.sh
└── safe-baseline-switch/       # NEW: safe branch switching for benchmarks
    └── scripts/
        └── safe-baseline-switch.sh
```

## 8. Recommended Execution Order

1. **Quick wins** (< 1 hour each):
   - Rename `skill.md` → `SKILL.md` (2 files)
   - Fix `python` → `python3` in shared inventory script
   - Delete or `.gitignore` the worktree mirror
   - Update README.md

2. **High-value extractions** (medium effort):
   - Jules API library (de-duplicates 5 scripts)
   - Review threads shared script (de-duplicates 4 locations)
   - Issue-to-prompt builder (de-duplicates 3 skills)

3. **New scripts** (higher effort):
   - `assign-to-copilot.sh` (scriptify the most fragile skill)
   - `classify-issues.sh` for find-stale-issues
   - `run-comparison.sh` for bench-compare
   - Codex cloud library

4. **Polish** (when convenient):
   - PR snapshot extraction
   - Build system detection
   - Safe baseline switch helper
   - Bug-hunt init script
   - Robustness fixes (pagination, backoff, JSON escaping)
