#!/usr/bin/env python3
"""Extract Cline/Copilot conversations to a directory for agent analysis."""

import json
import random
import sys
from pathlib import Path


def find_cline_transcripts() -> list[Path]:
    """Find all Cline transcript files."""
    cline_base = Path.home() / "Library" / "Application Support" / "Cursor" / "User" / "globalStorage" / "rooveterinaryinc.roo-cline" / "tasks"
    if not cline_base.exists():
        return []

    transcripts = []
    for task_dir in cline_base.iterdir():
        if task_dir.is_dir():
            transcript_file = task_dir / "api_conversation_history.json"
            if transcript_file.exists():
                transcripts.append(transcript_file)
    return transcripts


def extract_cline_transcripts(output_dir: Path, limit: int = 20, sample: int = 0):
    """Extract conversations from Cline/Copilot.

    Args:
        output_dir: Directory to write extracts
        limit: Maximum transcripts to process
        sample: If > 0, randomly sample this many
    """
    transcripts = find_cline_transcripts()

    if sample > 0 and sample < len(transcripts):
        transcripts = random.sample(transcripts, sample)
    else:
        transcripts = transcripts[:limit]

    output_dir.mkdir(parents=True, exist_ok=True)

    all_conversations = []
    for i, transcript_path in enumerate(transcripts):
        try:
            with open(transcript_path) as f:
                data = json.load(f)

            messages = []
            for msg in data:
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
                    messages.append({
                        "role": role,
                        "text": text[:1000],  # Truncate long content
                    })

            if messages:
                all_conversations.append({
                    "transcript_id": transcript_path.parent.name,
                    "messages": messages,
                })
        except (json.JSONDecodeError, IOError) as e:
            continue

    # Write full extract
    full_path = output_dir / "cline_full.json"
    with open(full_path, "w") as f:
        json.dump(all_conversations, f, indent=2)

    # Write markdown summary
    md_path = output_dir / "cline_summary.md"
    with open(md_path, "w") as f:
        f.write(f"# Cline/Copilot Transcript Extract\n\n")
        f.write(f"Total conversations: {len(all_conversations)}\n\n")

        f.write(f"## Sample Conversations\n\n")
        for i, conv in enumerate(all_conversations[:10]):
            f.write(f"### Conversation {i+1} ({conv['transcript_id']})\n\n")
            for msg in conv["messages"][:4]:  # First 4 messages
                f.write(f"**{msg['role']}**: {msg['text'][:300]}...\n\n")
            f.write("---\n\n")

    print(f"Extracted {len(all_conversations)} conversations to {output_dir}")
    print(f"  - {full_path}")
    print(f"  - {md_path}")


if __name__ == "__main__":
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/transcripts/cline")
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    sample = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    extract_cline_transcripts(output_dir, limit, sample)