#!/usr/bin/env bash
# Launch Claude Code cloud sessions for a set of prompt files.
#
# Usage:
#   bash launch-cloud-fanout.sh \
#     --prompt-dir hackmonty/prompts/sandbox-wave28-claude-host-secret \
#     [--pattern '*.prompt.md'] \
#     [--model claude-sonnet-4-6] \
#     [--dry-run]
#
# Each *.prompt.md file in the directory gets its own cloud session via
# `claude --remote`.  Output is a JSON manifest written alongside the prompts.

set -euo pipefail

PROMPT_DIR=""
PATTERN="*.prompt.md"
MODEL=""
DRY_RUN=false
MANIFEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-dir)  PROMPT_DIR="$2";  shift 2 ;;
    --pattern)     PATTERN="$2";     shift 2 ;;
    --model)       MODEL="$2";       shift 2 ;;
    --manifest)    MANIFEST="$2";    shift 2 ;;
    --dry-run)     DRY_RUN=true;     shift   ;;
    *)             echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROMPT_DIR" ]]; then
  echo "Error: --prompt-dir is required" >&2
  exit 1
fi

PROMPT_DIR="$(cd "$PROMPT_DIR" && pwd)"
MANIFEST="${MANIFEST:-$PROMPT_DIR/claude-fanout-manifest.json}"

# Collect prompt files
mapfile -t PROMPTS < <(find "$PROMPT_DIR" -maxdepth 1 -name "$PATTERN" -type f | sort)

if [[ ${#PROMPTS[@]} -eq 0 ]]; then
  echo "No files matching '$PATTERN' in $PROMPT_DIR" >&2
  exit 1
fi

echo "Found ${#PROMPTS[@]} prompt files"
echo "Manifest: $MANIFEST"
echo ""

# Start JSON manifest
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current 2>/dev/null || echo unknown)"
LOCAL_HEAD="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
REMOTE_HEAD="$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo unknown)"
REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo unknown)"

# Build manifest header using jq for safe JSON
jq -n \
  --arg now "$NOW" \
  --arg repo "$REPO_SLUG" \
  --arg branch "$BRANCH" \
  --arg local_head "$LOCAL_HEAD" \
  --arg remote_head "$REMOTE_HEAD" \
  --arg model "${MODEL:-default}" \
  --arg prompt_dir "$PROMPT_DIR" \
  '{
    created_at: $now,
    tool: "assign-claude",
    repo: $repo,
    branch: $branch,
    local_head: $local_head,
    remote_head: $remote_head,
    model: $model,
    prompt_dir: $prompt_dir,
    tasks: []
  }' > "$MANIFEST"

for PROMPT_FILE in "${PROMPTS[@]}"; do
  NAME="$(basename "$PROMPT_FILE" .prompt.md)"
  PROMPT_TEXT="$(cat "$PROMPT_FILE")"

  echo "==> $NAME"

  if $DRY_RUN; then
    echo "    [dry-run] Would launch: $NAME"
    jq --arg name "$NAME" --arg file "$PROMPT_FILE" \
      '.tasks += [{"name": $name, "prompt_file": $file, "status": "dry-run"}]' \
      "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
    continue
  fi

  # Build the claude --remote command
  CMD=(claude)
  if [[ -n "$MODEL" ]]; then
    CMD+=(--model "$MODEL")
  fi
  CMD+=(--remote "$PROMPT_TEXT")

  # Launch
  OUTPUT="$("${CMD[@]}" 2>&1)" || true
  echo "    Output: $OUTPUT"

  # Append to manifest using jq for safe JSON encoding
  jq --arg name "$NAME" --arg file "$PROMPT_FILE" --arg output "$OUTPUT" \
    '.tasks += [{"name": $name, "prompt_file": $file, "status": "launched", "output": $output}]' \
    "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
done

echo ""
echo "Manifest written: $MANIFEST"
