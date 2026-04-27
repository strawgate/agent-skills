#!/usr/bin/env python3
"""Extract OpenCode prompts to a directory for agent analysis."""

import json
import random
import sys
from pathlib import Path


def extract_opencode_history(input_path: Path, output_dir: Path, limit: int = 100, sample: int = 0):
    """Extract prompts from OpenCode history.jsonl.

    Args:
        input_path: Path to history.jsonl
        output_dir: Directory to write extracts
        limit: Maximum entries to process
        sample: If > 0, randomly sample this many entries instead
    """
    entries = []
    with open(input_path) as f:
        for i, line in enumerate(f):
            if i >= limit:
                break
            try:
                entry = json.loads(line.strip())
                if entry.get("display"):
                    entries.append({
                        "session_id": entry.get("sessionId", ""),
                        "project": entry.get("project", ""),
                        "prompt": entry.get("display", ""),
                        "timestamp": entry.get("timestamp", 0),
                    })
            except json.JSONDecodeError:
                continue

    if sample > 0 and sample < len(entries):
        entries = random.sample(entries, sample)

    output_dir.mkdir(parents=True, exist_ok=True)

    # Write full extract
    full_path = output_dir / "opencode_full.json"
    with open(full_path, "w") as f:
        json.dump(entries, f, indent=2)

    # Write markdown summary for agent
    md_path = output_dir / "opencode_summary.md"
    with open(md_path, "w") as f:
        f.write(f"# OpenCode Transcript Extract\n\n")
        f.write(f"Total entries: {len(entries)}\n\n")

        # Group by project
        by_project = {}
        for e in entries:
            proj = e.get("project", "unknown")
            if proj not in by_project:
                by_project[proj] = []
            by_project[proj].append(e)

        f.write(f"## Projects ({len(by_project)})\n\n")
        for proj, proj_entries in list(by_project.items())[:10]:
            f.write(f"- {proj}: {len(proj_entries)} prompts\n")

        f.write(f"\n## Sample Prompts (first 20)\n\n")
        for i, e in enumerate(entries[:20]):
            f.write(f"### {i+1}. {e.get('project', 'unknown').split('/')[-1]}\n\n")
            f.write(f"```\n{e['prompt'][:500]}\n```\n\n")

    print(f"Extracted {len(entries)} entries to {output_dir}")
    print(f"  - {full_path}")
    print(f"  - {md_path}")


if __name__ == "__main__":
    input_path = Path.home() / ".claude" / "history.jsonl"
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/transcripts/opencode")
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    sample = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    extract_opencode_history(input_path, output_dir, limit, sample)