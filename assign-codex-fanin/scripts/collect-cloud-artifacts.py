#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
from typing import Any


def run(cmd: list[str], cwd: pathlib.Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=True,
        check=False,
    )


def slugify(value: str) -> str:
    out = []
    for ch in value.lower():
        if ch.isalnum():
            out.append(ch)
        else:
            out.append("-")
    text = "".join(out)
    while "--" in text:
        text = text.replace("--", "-")
    return text.strip("-") or "task"


def try_extract_new_file(diff_text: str) -> tuple[str, str] | None:
    lines = diff_text.splitlines()
    old_path = None
    new_path = None
    content: list[str] = []
    in_hunk = False

    for line in lines:
        if line.startswith("--- "):
            old_path = line[4:].strip()
        elif line.startswith("+++ "):
            new_path = line[4:].strip()
        elif line.startswith("@@"):
            in_hunk = True
        elif in_hunk:
            if line.startswith("+") and not line.startswith("+++"):
                content.append(line[1:])
            elif line.startswith(" "):
                content.append(line[1:])
            elif line.startswith("-"):
                return None

    if old_path == "/dev/null" and new_path and new_path.startswith("b/"):
        return new_path[2:], "\n".join(content) + ("\n" if content else "")
    return None


def write_extracted_file(task_dir: pathlib.Path, rel_path: str, content: str, source_name: str) -> pathlib.Path:
    out_path = task_dir / "extracted" / rel_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content)
    (task_dir / "extracted-source.txt").write_text(source_name + "\n")
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Download status and diff artifacts for Codex Cloud tasks listed in a manifest.")
    parser.add_argument("manifest", nargs="?", help="Path to fanout-manifest.json produced by assign-codex-fanout.")
    parser.add_argument("--task", action="append", default=[], help="Codex Cloud task ID. May be repeated when no manifest is provided.")
    parser.add_argument("--output-dir", help="Output directory. Defaults to <manifest-dir>/cloud-artifacts.")
    parser.add_argument("--final-only", action="store_true", help="Only save final diffs, not per-attempt diffs.")
    parser.add_argument("--attempts", type=int, help="Override attempt count instead of using the manifest value.")
    args = parser.parse_args()

    if not args.manifest and not args.task:
        raise SystemExit("Provide either a manifest path or at least one --task.")

    if args.manifest:
        manifest_path = pathlib.Path(args.manifest).expanduser().resolve()
        with manifest_path.open() as fh:
            manifest = json.load(fh)
    else:
        manifest_path = None
        manifest = {
            "cwd": ".",
            "attempts_requested": args.attempts or 1,
            "tasks": [{"task_id": task_id, "name": task_id, "url": None} for task_id in args.task],
        }

    cwd = pathlib.Path(manifest.get("cwd", ".")).expanduser().resolve()
    output_dir = pathlib.Path(args.output_dir).expanduser().resolve() if args.output_dir else ((manifest_path.parent / "cloud-artifacts") if manifest_path else (cwd / "cloud-artifacts"))
    output_dir.mkdir(parents=True, exist_ok=True)

    attempts = args.attempts or int(manifest.get("attempts_requested", 1))
    index: dict[str, Any] = {
        "manifest": str(manifest_path) if manifest_path else None,
        "cwd": str(cwd),
        "attempts_saved": attempts,
        "tasks": [],
    }

    for task in manifest.get("tasks", []):
        task_id = task.get("task_id")
        if not task_id:
            continue

        name = task.get("name") or task_id
        task_dir = output_dir / f"{slugify(name)}-{task_id}"
        task_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n==> {name} ({task_id})")

        status = run(["codex", "cloud", "status", task_id], cwd=cwd)
        (task_dir / "status.txt").write_text(status.stdout + status.stderr)

        task_attempts = args.attempts or int(task.get("attempts", attempts))

        final_diff = run(["codex", "cloud", "diff", task_id], cwd=cwd)
        final_text = final_diff.stdout + final_diff.stderr
        (task_dir / "final.diff.txt").write_text(final_text)

        extracted = try_extract_new_file(final_text) if final_diff.returncode == 0 else None
        extracted_path = None
        if extracted:
            rel_path, content = extracted
            extracted_path = write_extracted_file(task_dir, rel_path, content, "final.diff.txt")

        attempts_saved: list[int] = []
        attempt_extracts: list[dict[str, Any]] = []
        if not args.final_only:
            for attempt in range(1, task_attempts + 1):
                result = run(["codex", "cloud", "diff", task_id, "--attempt", str(attempt)], cwd=cwd)
                text = result.stdout + result.stderr
                attempt_path = task_dir / f"attempt-{attempt}.diff.txt"
                attempt_path.write_text(text)
                if result.returncode == 0:
                    attempts_saved.append(attempt)
                    extracted = try_extract_new_file(text)
                    if extracted:
                        rel_path, content = extracted
                        source_name = f"attempt-{attempt}.diff.txt"
                        if extracted_path is None:
                            extracted_path = write_extracted_file(task_dir, rel_path, content, source_name)
                        attempt_extracts.append(
                            {
                                "attempt": attempt,
                                "path": rel_path,
                                "source": source_name,
                            }
                        )

        index["tasks"].append(
            {
                "name": name,
                "task_id": task_id,
                "url": task.get("url"),
                "attempts_requested": task_attempts,
                "task_dir": str(task_dir),
                "status_file": str(task_dir / "status.txt"),
                "final_diff_file": str(task_dir / "final.diff.txt"),
                "final_diff_available": final_diff.returncode == 0,
                "attempts_saved": attempts_saved,
                "attempt_extracts": attempt_extracts,
                "extracted_new_file": str(extracted_path) if extracted_path else None,
            }
        )

    index_path = output_dir / "artifact-index.json"
    index_path.write_text(json.dumps(index, indent=2) + "\n")
    print(f"\nWrote artifact index: {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
