#!/usr/bin/env python3
"""Convert gh-triage JSON output to .txt record format for semantic indexing.

This bridges gh-triage's JSON output to the format expected by build-semantic-index.sh.
"""

import json
import re
import sys
from pathlib import Path


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    slug = re.sub(r"-+", "-", slug)
    slug = slug[:80].rstrip("-")
    return slug or "untitled"


def write_issue_records(issues_json: Path, output_dir: Path) -> None:
    """Write issue JSON to .txt records."""
    issues = json.loads(issues_json.read_text())
    data = issues.get("issues", issues.get("data", {}).get("repository", {}).get("issues", {}).get("nodes", []))

    if not data:
        data = issues if isinstance(issues, list) else []

    open_dir = output_dir / "issues" / "open"
    closed_dir = output_dir / "issues" / "closed"
    open_dir.mkdir(parents=True, exist_ok=True)
    closed_dir.mkdir(parents=True, exist_ok=True)

    for record in sorted(data, key=lambda x: int(x.get("number", 0))):
        number = int(record["number"])
        title = (record.get("title") or "").strip()
        state = record.get("state", "OPEN").lower()
        is_pr = record.get("pull_request") is not None

        if is_pr:
            continue  # Skip PRs in issues

        labels = ", ".join(
            l.get("name", "") if isinstance(l, dict) else str(l)
            for l in record.get("labels", {}).get("nodes", [])
        )
        assignees = ", ".join(
            a.get("login", "") if isinstance(a, dict) else str(a)
            for a in record.get("assignees", {}).get("nodes", [])
        )
        milestone = record.get("milestone")
        if isinstance(milestone, dict):
            milestone = milestone.get("title", "")

        lines = [
            f"kind: issue",
            f"state: {state}",
            f"number: {number}",
            f"title: {title}",
            f"url: {record.get('url', record.get('html_url', ''))}",
        ]

        if record.get("createdAt"):
            lines.append(f"created_at: {record['createdAt']}")
        if record.get("updatedAt"):
            lines.append(f"updated_at: {record['updatedAt']}")
        if labels:
            lines.append(f"labels: {labels}")
        if assignees:
            lines.append(f"assignees: {assignees}")
        if milestone:
            lines.append(f"milestone: {milestone}")

        lines.append("")
        lines.append("body:")
        body = record.get("body") or ""
        if body:
            lines.extend(body.splitlines())
        else:
            lines.append("<empty>")
        lines.append("")

        target_dir = open_dir if state == "open" else closed_dir
        output_file = target_dir / f"{number:05d}-{slugify(title)}.txt"
        output_file.write_text("\n".join(lines) + "\n")


def write_pr_records(prs_json: Path, output_dir: Path) -> None:
    """Write PR JSON to .txt records."""
    prs = json.loads(prs_json.read_text())
    data = prs.get("pullRequests", prs.get("data", {}).get("repository", {}).get("pullRequests", {}).get("nodes", []))

    if not data:
        data = prs if isinstance(prs, list) else []

    open_dir = output_dir / "prs" / "open"
    merged_dir = output_dir / "prs" / "merged"
    closed_dir = output_dir / "prs" / "closed"
    open_dir.mkdir(parents=True, exist_ok=True)
    merged_dir.mkdir(parents=True, exist_ok=True)
    closed_dir.mkdir(parents=True, exist_ok=True)

    for record in sorted(data, key=lambda x: int(x.get("number", 0))):
        number = int(record["number"])
        title = (record.get("title") or "").strip()
        state = record.get("state", "OPEN").lower()
        merged_at = record.get("mergedAt")

        labels = ", ".join(
            l.get("name", "") if isinstance(l, dict) else str(l)
            for l in record.get("labels", {}).get("nodes", [])
        )

        lines = [
            f"kind: pr",
            f"state: {state}",
            f"number: {number}",
            f"title: {title}",
            f"url: {record.get('url', record.get('html_url', ''))}",
        ]

        if record.get("createdAt"):
            lines.append(f"created_at: {record['createdAt']}")
        if record.get("updatedAt"):
            lines.append(f"updated_at: {record['updatedAt']}")
        if merged_at:
            lines.append(f"merged_at: {merged_at}")
        if record.get("isDraft"):
            lines.append(f"draft: true")
        if record.get("baseRefName"):
            lines.append(f"base: {record['baseRefName']}")
        if record.get("headRefName"):
            lines.append(f"head: {record['headRefName']}")
        if labels:
            lines.append(f"labels: {labels}")

        lines.append("")
        lines.append("body:")
        body = record.get("body") or ""
        if body:
            lines.extend(body.splitlines())
        else:
            lines.append("<empty>")
        lines.append("")

        if merged_at:
            target_dir = merged_dir
        elif state == "open":
            target_dir = open_dir
        else:
            target_dir = closed_dir

        output_file = target_dir / f"{number:05d}-{slugify(title)}.txt"
        output_file.write_text("\n".join(lines) + "\n")


def main():
    gh_triage_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/gh-triage")

    # Try to detect owner/repo from gh-triage output
    owner_repo = "unknown"
    if (gh_triage_dir / "open-issues.json").exists():
        try:
            issues_json = json.loads((gh_triage_dir / "open-issues.json").read_text())
            owner = issues_json.get("owner", "")
            repo = issues_json.get("repo", "")
            if owner and repo:
                owner_repo = f"{owner}__{repo}"
        except:
            pass

    output_dir = Path("/tmp/issue-organizer") / owner_repo

    output_dir.mkdir(parents=True, exist_ok=True)

    # Process issues
    issues_json = gh_triage_dir / owner_repo / "open-issues.json"
    if issues_json.exists():
        write_issue_records(issues_json, output_dir)
        print(f"Wrote issues to {output_dir / 'issues'}")

    # Process PRs
    prs_json = gh_triage_dir / owner_repo / "open-prs.json"
    if prs_json.exists():
        write_pr_records(prs_json, output_dir)
        print(f"Wrote PRs to {output_dir / 'prs'}")

    print(f"\nData ready for semantic indexing: {output_dir}")
    print(f"Run: {Path(__file__).parent / 'build-semantic-index.sh'} {owner_repo.replace('__', '/')}")


if __name__ == "__main__":
    main()