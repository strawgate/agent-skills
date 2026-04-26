#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
    echo "usage: $0 OWNER/REPO" >&2
    exit 1
fi

OUT_DIR="/tmp/issue-organizer/${REPO//\//__}"

echo "[1/4] Fetch repo data..."
~/.claude/skills/_shared/github-repo-inventory/scripts/fetch-repo-data.sh "$REPO" > /dev/null

echo "[2/4] Build semantic indexes..."

python3 - "$OUT_DIR" <<'PYTHON'
import sys
import numpy as np
from pathlib import Path
from sentence_transformers import SentenceTransformer

out_dir = Path(sys.argv[1])

def embed_text(title, body, max_body=500):
    return f"{title} {body[:max_body]}".strip()

def parse_record(filepath):
    lines = filepath.read_text().splitlines()
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
        elif line.startswith("created_at:"):
            meta["created_at"] = line.split(":", 1)[1].strip()
        elif line.startswith("merged_at:"):
            meta["merged_at"] = line.split(":", 1)[1].strip()
        elif line.startswith("labels:"):
            meta["labels"] = line.split(":", 1)[1].strip()
        elif line.startswith("state:"):
            meta["state"] = line.split(":", 1)[1].strip()
        elif line.startswith("url:"):
            meta["url"] = line.split(":", 1)[1].strip()
        elif line == "body:":
            in_body = True
    meta["body"] = "\n".join(body_lines)
    return meta

print("  Loading model...")
model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

# Load issues
issues_dir = out_dir / "issues" / "open"
issue_files = sorted(issues_dir.glob("*.txt"))
issues = {}
issue_texts = []
issue_ids = []
for f in issue_files:
    meta = parse_record(f)
    issues[meta["number"]] = meta
    issue_texts.append(embed_text(meta["title"], meta["body"]))
    issue_ids.append(meta["number"])

# Load closed issues
closed_issues_dir = out_dir / "issues" / "closed"
closed_issue_files = sorted(closed_issues_dir.glob("*.txt"))
closed_issues = {}
closed_issue_texts = []
closed_issue_ids = []
for f in closed_issue_files:
    meta = parse_record(f)
    closed_issues[meta["number"]] = meta
    closed_issue_texts.append(embed_text(meta["title"], meta["body"]))
    closed_issue_ids.append(meta["number"])

# Load merged PRs
prs_dir = out_dir / "prs" / "merged"
pr_files = sorted(prs_dir.glob("*.txt"))
prs = {}
pr_texts = []
pr_ids = []
for f in pr_files:
    meta = parse_record(f)
    prs[meta["number"]] = meta
    pr_texts.append(embed_text(meta["title"], meta["body"]))
    pr_ids.append(meta["number"])

print(f"  Embedding {len(issue_texts)} open issues + {len(pr_texts)} merged PRs + {len(closed_issue_texts)} closed issues...")
all_embs = model.encode(issue_texts + pr_texts + closed_issue_texts, show_progress_bar=False)
all_embs = all_embs / np.linalg.norm(all_embs, axis=1, keepdims=True)

issue_embs = all_embs[:len(issue_texts)]
pr_embs = all_embs[len(issue_texts):len(issue_texts)+len(pr_texts)]
closed_issue_embs = all_embs[len(issue_texts)+len(pr_texts):]

issue_pr_sim = issue_embs @ pr_embs.T

# Build issue -> merged PR similarity
issue_to_pr = {}
for i, issue_num in enumerate(issue_ids):
    sims = issue_pr_sim[i]
    order = np.argsort(sims)[::-1]
    matches = []
    for j in order:
        if sims[j] > 0.35:
            matches.append((pr_ids[j], prs[pr_ids[j]]["title"], float(sims[j])))
    issue_to_pr[issue_num] = matches[:8]

# Build issue -> issue similarity
issue_issue_sim = issue_embs @ issue_embs.T
issue_to_issue = {}
for i, issue_num in enumerate(issue_ids):
    sims = issue_issue_sim[i]
    order = np.argsort(sims)[::-1]
    matches = []
    for j in order:
        if i != j and sims[j] > 0.35:
            matches.append((issue_ids[j], issues[issue_ids[j]]["title"], float(sims[j])))
    issue_to_issue[issue_num] = matches[:8]

# Build issue -> closed issue similarity
issue_closed_sim = issue_embs @ closed_issue_embs.T
issue_to_closed = {}
for i, issue_num in enumerate(issue_ids):
    sims = issue_closed_sim[i]
    order = np.argsort(sims)[::-1]
    matches = []
    for j in order:
        if sims[j] > 0.35:
            matches.append((closed_issue_ids[j], closed_issues[closed_issue_ids[j]]["title"], float(sims[j])))
    issue_to_closed[issue_num] = matches[:8]

print(f"  Built similarity maps")

# Write consolidated issue folders
issues_out = out_dir / "issues"
issues_out.mkdir(exist_ok=True)

for issue_num, meta in issues.items():
    folder = issues_out / f"{issue_num:05d}"
    folder.mkdir(exist_ok=True)

    lines = [
        f"number: {issue_num}",
        f"title: {meta['title']}",
        f"created_at: {meta.get('created_at', '')}",
        f"updated_at: {meta.get('updated_at', '')}",
        f"labels: {meta.get('labels', '')}",
        f"url: {meta.get('url', '')}",
        "",
        "body:",
    ]
    lines.extend(meta["body"].splitlines())
    lines.append("")
    lines.append("similar_issues:")
    for num, title, score in issue_to_issue.get(issue_num, []):
        lines.append(f"  #{num} (score={score:.3f}) {title}")
    lines.append("")
    lines.append("similar_merged_prs:")
    for num, title, score in issue_to_pr.get(issue_num, []):
        lines.append(f"  #{num} (score={score:.3f}) {title}")
    lines.append("")
    lines.append("similar_closed_issues:")
    for num, title, score in issue_to_closed.get(issue_num, []):
        lines.append(f"  #{num} (score={score:.3f}) {title}")

    (folder / "issue.txt").write_text("\n".join(lines) + "\n")

print(f"  Wrote {len(issues)} issue folders")

# Build pr -> issue similarity
pr_issue_sim = pr_embs @ issue_embs.T
pr_to_issue = {}
for i, pr_num in enumerate(pr_ids):
    sims = pr_issue_sim[i]
    order = np.argsort(sims)[::-1]
    matches = []
    for j in order:
        if sims[j] > 0.35:
            matches.append((issue_ids[j], issues[issue_ids[j]]["title"], float(sims[j])))
    pr_to_issue[pr_num] = matches[:8]

# Write consolidated pr folders
prs_out = out_dir / "prs"
for pr_num, meta in prs.items():
    folder = prs_out / f"{pr_num:05d}"
    folder.mkdir(exist_ok=True)

    lines = [
        f"number: {pr_num}",
        f"title: {meta['title']}",
        f"created_at: {meta.get('created_at', '')}",
        f"merged_at: {meta.get('merged_at', '')}",
        f"labels: {meta.get('labels', '')}",
        f"url: {meta.get('url', '')}",
        "",
        "body:",
    ]
    lines.extend(meta["body"].splitlines())
    lines.append("")
    lines.append("similar_issues:")
    for num, title, score in pr_to_issue.get(pr_num, []):
        lines.append(f"  #{num} (score={score:.3f}) {title}")

    (folder / "pr.txt").write_text("\n".join(lines) + "\n")

print(f"  Wrote {len(prs)} pr folders")

# Write minimal indexes
def write_index(filepath, records, date_key, limit=None):
    records_sorted = sorted(records, key=lambda x: x.get(date_key) or "")
    if limit:
        records_sorted = records_sorted[-limit:]
    lines = ["# | Date | Title"]
    for r in records_sorted:
        date = (r.get(date_key) or "")[:10]
        lines.append(f"{r['number']} | {date} | {r['title']}")
    filepath.write_text("\n".join(lines) + "\n")

# issues-open.txt: all open issues
write_index(out_dir / "issues-open.txt", list(issues.values()), "created_at")

# issues-closed-last-100.txt: last 100 closed issues by date
write_index(out_dir / "issues-closed-last-100.txt", list(closed_issues.values()), "created_at", limit=100)

# prs-merged-last-100.txt: last 100 merged PRs by date
write_index(out_dir / "prs-merged-last-100.txt", list(prs.values()), "merged_at", limit=100)

# prs-open.txt: all open PRs (usually small)
open_prs_dir = out_dir / "prs" / "open"
open_prs_files = sorted(open_prs_dir.glob("*.txt"))
open_prs_meta = [parse_record(f) for f in open_prs_files]
write_index(out_dir / "prs-open.txt", open_prs_meta, "created_at")

# prs-closed-last-20.txt: last 20 closed PRs
closed_prs_dir = out_dir / "prs" / "closed"
closed_prs_files = sorted(closed_prs_dir.glob("*.txt"))
closed_prs_meta = [parse_record(f) for f in closed_prs_files]
write_index(out_dir / "prs-closed-last-20.txt", closed_prs_meta, "created_at", limit=20)

print(f"  Wrote minimal indexes")
PYTHON

echo "[3/4] Done"
echo "Data: $OUT_DIR"
echo ""
echo "Structure:"
find "$OUT_DIR" -maxdepth 2 -type d | sort | head -20