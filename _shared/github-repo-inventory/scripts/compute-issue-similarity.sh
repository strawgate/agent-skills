#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 OWNER/REPO [OUT_DIR]" >&2
    exit 1
fi

repo="$1"
out_dir="${2:-/tmp/issue-organizer/${repo//\//__}}"

issues_dir="$out_dir/issues/open"
similar_dir="$out_dir/similar-issues"

if [[ ! -d "$issues_dir" ]]; then
    echo "Error: $issues_dir does not exist. Run fetch-repo-data.sh first." >&2
    exit 1
fi

if [[ ! -d "$similar_dir" ]]; then
    mkdir -p "$similar_dir"
fi

python3 - "$issues_dir" "$similar_dir" <<'PYTHON'
import sys
import numpy as np
from pathlib import Path
from sentence_transformers import SentenceTransformer

issues_dir = Path(sys.argv[1])
similar_dir = Path(sys.argv[2])
similar_dir.mkdir(parents=True, exist_ok=True)

# Load and parse issues
issue_files = sorted(issues_dir.glob("*.txt"))
issues = {}
texts = []
ids = []

for f in issue_files:
    lines = f.read_text().splitlines()
    meta = {}
    body_lines = []
    in_body = False
    for line in lines:
        if in_body:
            body_lines.append(line)
        elif line.startswith("number:"):
            meta["number"] = int(line.split(":", 1)[1].strip())
        elif line.startswith("title:"):
            meta["title"] = line.split(":", 1)[1].strip()
        elif line.startswith("labels:"):
            meta["labels"] = line.split(":", 1)[1].strip()
        elif line == "body:":
            in_body = True
    meta["body"] = "\n".join(body_lines)
    meta["filename"] = f.name

    # Embed title + first 500 chars of body
    embed_text = f"{meta['title']} {meta['body'][:500]}".strip()
    issues[meta["number"]] = meta
    texts.append(embed_text)
    ids.append(meta["number"])

print(f"Computing embeddings for {len(texts)} issues...", file=sys.stderr)

# Use Metal if available, otherwise CPU
model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
embeddings = model.encode(texts, show_progress_bar=False)

# Normalize
embeddings = embeddings / np.linalg.norm(embeddings, axis=1, keepdims=True)

# Compute similarity matrix
sim_matrix = embeddings @ embeddings.T

# Get top-8 similar for each issue
top_n = 8
for i, issue_num in enumerate(ids):
    sims = sim_matrix[i]
    order = np.argsort(sims)[::-1]

    similar = []
    for j in order[1:top_n+1]:
        if sims[j] > 0.3:
            similar.append({
                "number": int(ids[j]),
                "title": issues[ids[j]]["title"],
                "score": float(sims[j])
            })

    # Write per-issue file
    out_file = similar_dir / f"{issue_num:05d}.txt"
    lines = [f"Issue: #{issue_num} - {issues[issue_num]['title']}", ""]
    lines.append(f"Labels: {issues[issue_num].get('labels', 'none')}")
    lines.append("")
    lines.append("Semantically similar issues:")
    if similar:
        for s in similar:
            lines.append(f"  #{s['number']} (score={s['score']:.3f}) {s['title']}")
    else:
        lines.append("  (none above threshold)")
    out_file.write_text("\n".join(lines) + "\n")

# Write TSV summary for easy grep/pipeline
tsv_file = similar_dir / "similar-issues.tsv"
with open(tsv_file, "w") as f:
    f.write("issue\tsimilar_issue\tscore\ttitle\n")
    for i, issue_num in enumerate(ids):
        sims = sim_matrix[i]
        order = np.argsort(sims)[::-1]
        for j in order[1:top_n+1]:
            if sims[j] > 0.3:
                f.write(f"{issue_num}\t{ids[j]}\t{sims[j]:.4f}\t{issues[ids[j]]['title']}\n")

print(f"Wrote {len(issues)} similarity files + TSV to {similar_dir}", file=sys.stderr)
PYTHON