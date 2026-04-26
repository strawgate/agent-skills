#!/usr/bin/env bash
set -euo pipefail

PR_LIMIT=30
ISSUE_LIMIT=30
COMMIT_LIMIT=40
FILE_DEPTH=3
MAX_PATHS=500
CWD="$(pwd)"
OUT=""

usage() {
  cat <<'USAGE'
Usage: refresh_snapshot.sh [options]

Options:
  --cwd <path>          Directory to inspect (default: current directory)
  --out <path>          Output markdown file (default: <repo>/.codex/refresh/refresh-<timestamp>.md)
  --pr-limit <n>        Number of PRs to include (default: 30)
  --issue-limit <n>     Number of issues per state to include (default: 30)
  --commit-limit <n>    Number of commits to inspect (default: 40)
  --file-depth <n>      Max depth for current-directory file listing (default: 3)
  --max-paths <n>       Max paths to print in file listings (default: 500)
  -h, --help            Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)
      CWD="$2"; shift 2 ;;
    --out)
      OUT="$2"; shift 2 ;;
    --pr-limit)
      PR_LIMIT="$2"; shift 2 ;;
    --issue-limit)
      ISSUE_LIMIT="$2"; shift 2 ;;
    --commit-limit)
      COMMIT_LIMIT="$2"; shift 2 ;;
    --file-depth)
      FILE_DEPTH="$2"; shift 2 ;;
    --max-paths)
      MAX_PATHS="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if ! git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "error: '$CWD' is not inside a git repository" >&2
  exit 1
fi

REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
STAMP_FILE="$(date +"%Y%m%d-%H%M%S")"

if [[ -z "$OUT" ]]; then
  OUT="$REPO_ROOT/.codex/refresh/refresh-$STAMP_FILE.md"
fi
mkdir -p "$(dirname "$OUT")"

REPO_FULL_NAME=""
DEFAULT_BRANCH=""
REPO_URL=""
GH_READY=0

if command -v gh >/dev/null 2>&1; then
  if (cd "$REPO_ROOT" && gh auth status >/dev/null 2>&1); then
    GH_READY=1
    if INFO="$(cd "$REPO_ROOT" && gh repo view --json nameWithOwner,defaultBranchRef,url --template '{{.nameWithOwner}}|{{.defaultBranchRef.name}}|{{.url}}' 2>/dev/null)"; then
      REPO_FULL_NAME="${INFO%%|*}"
      REST="${INFO#*|}"
      DEFAULT_BRANCH="${REST%%|*}"
      REPO_URL="${REST#*|}"
    fi
  fi
fi

if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
fi
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="main"
fi

if [[ -z "$REPO_FULL_NAME" ]]; then
  ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  REPO_FULL_NAME="${ORIGIN_URL##*:}"
  REPO_FULL_NAME="${REPO_FULL_NAME%.git}"
  REPO_URL="$ORIGIN_URL"
fi

# Refresh remote branch pointer when possible.
git -C "$REPO_ROOT" fetch origin "$DEFAULT_BRANCH" --quiet >/dev/null 2>&1 || true

section() {
  echo "## $1"
  echo
}

code_block() {
  local title="$1"
  shift
  echo "### $title"
  echo
  echo '```text'
  "$@" 2>&1 || echo "[command failed]"
  echo '```'
  echo
}

{
  echo "# Refresh Snapshot"
  echo
  echo "- Generated (UTC): $TIMESTAMP"
  echo "- Repo root: $REPO_ROOT"
  echo "- Current cwd: $CWD"
  echo "- Repo: $REPO_FULL_NAME"
  echo "- Default branch: $DEFAULT_BRANCH"
  echo "- Repo URL: $REPO_URL"
  echo

  section "Working Tree"
  code_block "git status -sb" git -C "$REPO_ROOT" status -sb
  code_block "current branch" git -C "$REPO_ROOT" branch --show-current
  code_block "HEAD" git -C "$REPO_ROOT" rev-parse HEAD

  section "Recent Commits"
  code_block "current branch commits (latest $COMMIT_LIMIT)" \
    git -C "$REPO_ROOT" log --date=short --pretty=format:'%h %ad %an %s' -n "$COMMIT_LIMIT"
  code_block "origin/$DEFAULT_BRANCH commits (latest $COMMIT_LIMIT)" \
    git -C "$REPO_ROOT" log --date=short --pretty=format:'%h %ad %an %s' -n "$COMMIT_LIMIT" "origin/$DEFAULT_BRANCH"
  code_block "files changed on origin/$DEFAULT_BRANCH across last $COMMIT_LIMIT commits" \
    git -C "$REPO_ROOT" diff --name-status "origin/$DEFAULT_BRANCH~$COMMIT_LIMIT..origin/$DEFAULT_BRANCH"

  section "GitHub Activity"
  if [[ "$GH_READY" -eq 1 && -n "$REPO_FULL_NAME" ]]; then
    code_block "recent PRs (state=all, limit=$PR_LIMIT)" \
      gh -R "$REPO_FULL_NAME" pr list --state all --limit "$PR_LIMIT" \
      --json number,title,state,isDraft,author,updatedAt,baseRefName,headRefName,url \
      --template '{{range .}}#{{.number}} {{if .isDraft}}[DRAFT] {{end}}{{.state}} {{.title}} ({{.author.login}}) updated={{.updatedAt}} base={{.baseRefName}} head={{.headRefName}} {{.url}}{{"\n"}}{{end}}'

    code_block "open issues (limit=$ISSUE_LIMIT)" \
      gh -R "$REPO_FULL_NAME" issue list --state open --limit "$ISSUE_LIMIT" \
      --json number,title,updatedAt,author,url \
      --template '{{range .}}#{{.number}} OPEN {{.title}} ({{.author.login}}) updated={{.updatedAt}} {{.url}}{{"\n"}}{{end}}'

    code_block "recently closed issues (limit=$ISSUE_LIMIT)" \
      gh -R "$REPO_FULL_NAME" issue list --state closed --limit "$ISSUE_LIMIT" \
      --json number,title,updatedAt,author,url \
      --template '{{range .}}#{{.number}} CLOSED {{.title}} ({{.author.login}}) updated={{.updatedAt}} {{.url}}{{"\n"}}{{end}}'
  else
    echo "GitHub CLI is not ready (missing gh auth or repo visibility)."
    echo
  fi

  section "Current Directory Files"
  code_block "directory tree from cwd (depth=$FILE_DEPTH, max=$MAX_PATHS)" \
    bash -lc "find \"$CWD\" -maxdepth $FILE_DEPTH -mindepth 1 -not -path '*/.git/*' -print | sed 's|^$CWD/||' | sort | head -n $MAX_PATHS"

  code_block "tracked files in repo (max=$MAX_PATHS)" \
    bash -lc "git -C \"$REPO_ROOT\" ls-files | head -n $MAX_PATHS"

  section "Suggested Follow-Up"
  echo "1. Read this snapshot from top to bottom and list assumptions that might now be stale (architecture, contracts, release process, dependencies, roadmap)."
  echo "2. Inspect likely-changing files from recent main commits first (design docs, crate contracts, runtime wiring, CI, Cargo.toml)."
  echo "3. Cross-check open PRs/issues for behavior changes that have not landed on main yet but affect near-term work."
  echo "4. Produce a short 'what changed / what did not change / what needs deeper confirmation' memo before coding."
  echo
} > "$OUT"

echo "$OUT"
