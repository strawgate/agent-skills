#!/bin/bash
# Find all agent transcript files on the system

set -e

echo "=== Transcript Sources ==="
echo ""

# OpenCode transcripts
if [ -f ~/.claude/history.jsonl ]; then
    echo "OpenCode: ~/.claude/history.jsonl"
    wc -l < ~/.claude/history.jsonl
    echo ""
fi

# Cline/Copilot transcripts
CLINE_TASKS="$HOME/Library/Application Support/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks"
if [ -d "$CLINE_TASKS" ]; then
    COUNT=$(find "$CLINE_TASKS" -name "api_conversation_history.json" 2>/dev/null | wc -l | tr -d ' ')
    echo "Cline/Copilot: $CLINE_TASKS"
    echo "  Found $COUNT transcript files"
    echo ""
fi

# Claude Desktop sessions
if [ -d ~/.claude/sessions ]; then
    COUNT=$(find ~/.claude/sessions -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    echo "Claude Desktop: ~/.claude/sessions/"
    echo "  Found $COUNT session files"
    echo ""
fi

# Codex transcripts
if [ -d ~/.codex ]; then
    echo "Codex: ~/.codex/"
    ls ~/.codex/ | head -10
    echo ""
fi

echo "=== Transcript Locations ==="
find ~/.claude -name "history.jsonl" -o -name "*transcript*" 2>/dev/null | head -10
find ~/Library/Application\ Support/Cursor -name "api_conversation_history.json" 2>/dev/null | head -5