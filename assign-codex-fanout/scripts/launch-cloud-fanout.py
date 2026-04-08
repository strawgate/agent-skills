#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Any


TASK_ID_RE = re.compile(r"\b(task_e_[a-z0-9]+)\b")
TASK_URL_RE = re.compile(r"https://chatgpt\.com/codex/tasks/(task_e_[a-z0-9]+)")


def run(cmd: list[str], cwd: pathlib.Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=True,
        check=False,
    )


def first_heading(text: str) -> str | None:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            return stripped.lstrip("#").strip()
    return None


def infer_repo_slug(cwd: pathlib.Path) -> str | None:
    result = run(["git", "remote", "get-url", "origin"], cwd=cwd)
    if result.returncode != 0:
        return None
    raw = result.stdout.strip()
    if raw.startswith("git@github.com:"):
        raw = raw.split(":", 1)[1]
    elif "github.com/" in raw:
        raw = raw.split("github.com/", 1)[1]
    else:
        return None
    if raw.endswith(".git"):
        raw = raw[:-4]
    parts = [p for p in raw.split("/") if p]
    if len(parts) >= 2:
        return f"{parts[-2]}/{parts[-1]}"
    return None


def collect_env_candidates(value: Any) -> list[dict[str, str]]:
    candidates: list[dict[str, str]] = []

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            node_id = node.get("id")
            label = node.get("label")
            if isinstance(node_id, str) and isinstance(label, str):
                candidates.append({"id": node_id, "label": label})
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)

    walk(value)

    dedup: dict[tuple[str, str], dict[str, str]] = {}
    for item in candidates:
        dedup[(item["id"], item["label"])] = item
    return list(dedup.values())


def detect_env(explicit_env: str | None, explicit_label: str | None, cwd: pathlib.Path) -> tuple[str, str | None]:
    if explicit_env:
        return explicit_env, explicit_label

    state_path = pathlib.Path.home() / ".codex" / ".codex-global-state.json"
    if not state_path.exists():
        raise SystemExit("Could not find ~/.codex/.codex-global-state.json; pass --env explicitly.")

    with state_path.open() as fh:
        state = json.load(fh)

    candidates = collect_env_candidates(state)
    if not candidates:
        raise SystemExit("No environment candidates found in ~/.codex/.codex-global-state.json; pass --env explicitly.")

    if explicit_label:
        exact = [c for c in candidates if c["label"] == explicit_label]
        if len(exact) == 1:
            return exact[0]["id"], exact[0]["label"]
        contains = [c for c in candidates if explicit_label in c["label"]]
        if len(contains) == 1:
            return contains[0]["id"], contains[0]["label"]

    repo_slug = infer_repo_slug(cwd)
    if repo_slug:
        matched = [c for c in candidates if c["label"] == repo_slug]
        if len(matched) == 1:
            return matched[0]["id"], matched[0]["label"]

    if len(candidates) == 1:
        return candidates[0]["id"], candidates[0]["label"]

    choices = "\n".join(f"- {c['id']}  {c['label']}" for c in candidates)
    raise SystemExit(f"Could not uniquely detect a cloud environment. Pass --env or --env-label.\nCandidates:\n{choices}")


def detect_branch(cwd: pathlib.Path, explicit_branch: str | None) -> str:
    if explicit_branch:
        return explicit_branch
    result = run(["git", "branch", "--show-current"], cwd=cwd)
    branch = result.stdout.strip()
    if result.returncode != 0 or not branch:
        raise SystemExit("Could not determine current git branch; pass --branch explicitly.")
    return branch


def discover_prompts(prompt_dir: pathlib.Path, pattern: str, explicit_prompts: list[str]) -> list[pathlib.Path]:
    if explicit_prompts:
        prompts = [pathlib.Path(p).expanduser().resolve() for p in explicit_prompts]
    else:
        prompts = sorted(prompt_dir.glob(pattern))
    prompts = [p for p in prompts if p.is_file()]
    if not prompts:
        raise SystemExit("No prompt files found.")
    return prompts


def parse_prompt_attempt_overrides(values: list[str]) -> dict[pathlib.Path, int]:
    overrides: dict[pathlib.Path, int] = {}
    for value in values:
        if "=" not in value:
            raise SystemExit(f"Invalid --prompt-attempt value {value!r}; expected PATH=ATTEMPTS.")
        raw_path, raw_attempts = value.rsplit("=", 1)
        try:
            attempts = int(raw_attempts)
        except ValueError as exc:
            raise SystemExit(f"Invalid attempts in --prompt-attempt value {value!r}.") from exc
        if attempts < 1:
            raise SystemExit(f"Attempts must be >= 1 in --prompt-attempt value {value!r}.")
        prompt_path = pathlib.Path(raw_path).expanduser().resolve()
        overrides[prompt_path] = attempts
    return overrides


def main() -> int:
    parser = argparse.ArgumentParser(description="Launch one Codex Cloud task per prompt file using best-of-N attempts.")
    parser.add_argument("--prompt-dir", default=".", help="Directory containing workstream prompt files.")
    parser.add_argument("--pattern", default="*.prompt.md", help="Glob pattern used inside --prompt-dir.")
    parser.add_argument("--prompt", action="append", default=[], help="Explicit prompt file path. May be repeated.")
    parser.add_argument("--attempts", type=int, default=4, help="Number of attempts per task.")
    parser.add_argument(
        "--prompt-attempt",
        action="append",
        default=[],
        help="Override attempts for one prompt file using PATH=ATTEMPTS. May be repeated.",
    )
    parser.add_argument("--env", help="Codex Cloud environment ID.")
    parser.add_argument("--env-label", help="Preferred environment label when auto-detecting.")
    parser.add_argument("--branch", help="Git branch to run in cloud.")
    parser.add_argument("--cwd", default=".", help="Repo root for git branch and env inference.")
    parser.add_argument("--manifest", help="Output manifest path. Defaults to <prompt-dir>/fanout-manifest.json.")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing them.")
    args = parser.parse_args()

    cwd = pathlib.Path(args.cwd).expanduser().resolve()
    prompt_dir = pathlib.Path(args.prompt_dir).expanduser().resolve()
    manifest_path = pathlib.Path(args.manifest).expanduser().resolve() if args.manifest else (prompt_dir / "fanout-manifest.json")

    env_id, env_label = detect_env(args.env, args.env_label, cwd)
    branch = detect_branch(cwd, args.branch)
    prompts = discover_prompts(prompt_dir, args.pattern, args.prompt)
    prompt_attempts = parse_prompt_attempt_overrides(args.prompt_attempt)

    manifest: dict[str, Any] = {
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "cwd": str(cwd),
        "prompt_dir": str(prompt_dir),
        "pattern": args.pattern,
        "branch": branch,
        "env_id": env_id,
        "env_label": env_label,
        "attempts_requested": args.attempts,
        "prompt_attempt_overrides": {str(path): attempts for path, attempts in prompt_attempts.items()},
        "tasks": [],
    }

    for prompt_path in prompts:
        prompt_text = prompt_path.read_text()
        heading = first_heading(prompt_text) or prompt_path.stem
        attempts = prompt_attempts.get(prompt_path, args.attempts)
        cmd = [
            "codex",
            "cloud",
            "exec",
            "--env",
            env_id,
            "--branch",
            branch,
            "--attempts",
            str(attempts),
            prompt_text,
        ]
        print(f"\n==> {prompt_path.name}")
        print(" ".join(shlex.quote(part) for part in cmd[:8]), "...")

        record: dict[str, Any] = {
            "name": heading,
            "prompt_file": str(prompt_path),
            "attempts": attempts,
            "task_id": None,
            "url": None,
        }

        if args.dry_run:
            manifest["tasks"].append(record)
            continue

        result = run(cmd, cwd=cwd)
        combined = "\n".join(part for part in [result.stdout, result.stderr] if part).strip()
        task_match = TASK_ID_RE.search(combined)
        url_match = TASK_URL_RE.search(combined)
        task_id = task_match.group(1) if task_match else None
        url = url_match.group(0) if url_match else None

        record.update(
            {
                "task_id": task_id,
                "url": url,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        )
        manifest["tasks"].append(record)

        if result.returncode != 0 or not task_id:
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            print(combined, file=sys.stderr)
            raise SystemExit(f"Failed to launch task for {prompt_path}. Partial manifest written to {manifest_path}.")

        print(f"Task: {task_id}")
        if url:
            print(f"URL:  {url}")

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nWrote manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
