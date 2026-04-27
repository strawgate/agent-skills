#!/usr/bin/env python3
"""Get random samples of transcripts for agent analysis."""

import json
import random
import sys
from pathlib import Path


def sample_opencode(count: int) -> list[dict]:
    """Get random sample of OpenCode prompts."""
    input_path = Path.home() / ".claude" / "history.jsonl"
    entries = []

    with open(input_path) as f:
        for line in f:
            try:
                entry = json.loads(line.strip())
                if entry.get("display"):
                    entries.append({
                        "source": "opencode",
                        "session_id": entry.get("sessionId", ""),
                        "project": entry.get("project", ""),
                        "prompt": entry.get("display", ""),
                        "timestamp": entry.get("timestamp", 0),
                    })
            except json.JSONDecodeError:
                continue

    if count < len(entries):
        entries = random.sample(entries, count)

    return entries


def sample_cline(count: int) -> list[dict]:
    """Get random sample of Cline conversations."""
    cline_base = Path.home() / "Library" / "Application Support" / "Cursor" / "User" / "globalStorage" / "rooveterinaryinc.roo-cline" / "tasks"
    if not cline_base.exists():
        return []

    transcripts = []
    for task_dir in cline_base.iterdir():
        if task_dir.is_dir():
            transcript_file = task_dir / "api_conversation_history.json"
            if transcript_file.exists():
                transcripts.append(transcript_file)

    if count < len(transcripts):
        transcripts = random.sample(transcripts, count)

    samples = []
    for transcript_path in transcripts:
        try:
            with open(transcript_path) as f:
                data = json.load(f)

            messages = []
            for msg in data[:6]:  # First 6 messages
                role = msg.get("role", "unknown")
                content = msg.get("content", [])
                if isinstance(content, list):
                    text = " ".join(
                        c.get("text", "") for c in content
                        if isinstance(c, dict) and c.get("type") == "text"
                    )
                else:
                    text = str(content)

                if text.strip():
                    messages.append({"role": role, "text": text[:500]})

            if messages:
                samples.append({
                    "source": "cline",
                    "transcript_id": transcript_path.parent.name,
                    "messages": messages,
                })
        except (json.JSONDecodeError, IOError):
            continue

    return samples


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "opencode"
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    if source == "opencode":
        samples = sample_opencode(count)
        output = {"source": "opencode", "samples": samples}
    elif source == "cline":
        samples = sample_cline(count)
        output = {"source": "cline", "samples": samples}
    elif source == "all":
        opencode_samples = sample_opencode(count // 2 + 1)
        cline_samples = sample_cline(count // 2)
        output = {
            "source": "mixed",
            "opencode": opencode_samples[:count // 2],
            "cline": cline_samples[:count // 2],
        }
    else:
        print(f"Unknown source: {source}")
        print("Available: opencode, cline, all")
        sys.exit(1)

    # Write to stdout as JSON
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()