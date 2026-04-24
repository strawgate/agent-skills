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
import urllib.error
import urllib.parse
import urllib.request


TASK_ID_RE = re.compile(r"\b(task_e_[a-z0-9]+)\b")
TASK_URL_RE = re.compile(r"https://chatgpt\.com/codex/tasks/(task_e_[a-z0-9]+)")
WHAM_BASE_URL = "https://chatgpt.com/backend-api/wham"


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


def split_repo_slug(slug: str | None) -> tuple[str | None, str | None]:
    if not slug or "/" not in slug:
        return None, None
    owner, name = slug.split("/", 1)
    return owner, name


def env_repo_slugs(env: dict[str, Any]) -> list[str]:
    repo_map = env.get("repo_map")
    if not isinstance(repo_map, dict):
        return []
    slugs: list[str] = []
    for repo in repo_map.values():
        if not isinstance(repo, dict):
            continue
        slug = repo.get("repository_full_name")
        if isinstance(slug, str):
            slugs.append(slug)
    return slugs


def env_matches_repo(repo_slug: str | None, env_label: str | None) -> bool:
    if not repo_slug or not env_label:
        return True
    repo_owner, repo_name = split_repo_slug(repo_slug)
    env_owner, env_name = split_repo_slug(env_label)
    if not repo_owner or not repo_name or not env_owner or not env_name:
        return repo_slug == env_label
    if repo_owner != env_owner:
        return False
    return env_name == repo_name or env_name.startswith(f"{repo_name}-")


def load_auth_access_token() -> str:
    auth_path = pathlib.Path.home() / ".codex" / "auth.json"
    if not auth_path.exists():
        raise SystemExit("Could not find ~/.codex/auth.json; run `codex login` or pass --env explicitly.")
    with auth_path.open() as fh:
        auth = json.load(fh)
    tokens = auth.get("tokens")
    if not isinstance(tokens, dict):
        raise SystemExit("Could not parse tokens from ~/.codex/auth.json; pass --env explicitly.")
    access_token = tokens.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise SystemExit("Could not find an access token in ~/.codex/auth.json; pass --env explicitly.")
    return access_token


def fetch_wham_json(path: str) -> Any:
    token = load_auth_access_token()
    req = urllib.request.Request(
        f"{WHAM_BASE_URL}{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "CodexFanoutLauncher/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        body = exc.read(400).decode("utf-8", "replace")
        raise SystemExit(f"Failed to query Codex Cloud environments: HTTP {exc.code} for {path}\n{body}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Failed to query Codex Cloud environments: {exc}") from exc


def fetch_api_env_candidates(repo_slug: str | None) -> list[dict[str, Any]]:
    if repo_slug:
        owner, name = split_repo_slug(repo_slug)
        if owner and name:
            quoted_owner = urllib.parse.quote(owner, safe="")
            quoted_name = urllib.parse.quote(name, safe="")
            data = fetch_wham_json(f"/environments/by-repo/github/{quoted_owner}/{quoted_name}")
            if isinstance(data, list):
                return [item for item in data if isinstance(item, dict)]
    data = fetch_wham_json("/environments")
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    raise SystemExit("Unexpected environment list response from Codex Cloud.")


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


def format_env_choices(candidates: list[dict[str, Any]]) -> str:
    lines = []
    for candidate in candidates:
        repos = ", ".join(env_repo_slugs(candidate)) or "unknown"
        lines.append(f"- {candidate.get('id')}  {candidate.get('label')}  repos=[{repos}]")
    return "\n".join(lines)


def detect_env(
    explicit_env: str | None,
    explicit_label: str | None,
    cwd: pathlib.Path,
    repo_slug: str | None,
) -> tuple[str, str | None, list[dict[str, Any]]]:
    if explicit_env:
        return explicit_env, explicit_label, []

    candidates = fetch_api_env_candidates(repo_slug)
    if not candidates:
        state_path = pathlib.Path.home() / ".codex" / ".codex-global-state.json"
        if state_path.exists():
            with state_path.open() as fh:
                state = json.load(fh)
            cached = collect_env_candidates(state)
            if len(cached) == 1:
                return cached[0]["id"], cached[0]["label"], []
        raise SystemExit("No environment candidates found via Codex Cloud API; pass --env explicitly.")

    if explicit_label:
        exact = [c for c in candidates if c.get("label") == explicit_label]
        if len(exact) == 1:
            return exact[0]["id"], exact[0].get("label"), candidates
        contains = [c for c in candidates if isinstance(c.get("label"), str) and explicit_label in c["label"]]
        if len(contains) == 1:
            return contains[0]["id"], contains[0].get("label"), candidates

    if repo_slug:
        exact = [c for c in candidates if c.get("label") == repo_slug]
        if len(exact) == 1:
            return exact[0]["id"], exact[0].get("label"), candidates

        repo_map_matches = [c for c in candidates if repo_slug in env_repo_slugs(c)]
        if len(repo_map_matches) == 1:
            return repo_map_matches[0]["id"], repo_map_matches[0].get("label"), candidates

    if len(candidates) == 1:
        return candidates[0]["id"], candidates[0].get("label"), candidates

    raise SystemExit(
        "Could not uniquely detect a cloud environment. Pass --env or --env-label.\nCandidates:\n"
        f"{format_env_choices(candidates)}"
    )


def detect_branch(cwd: pathlib.Path, explicit_branch: str | None) -> str:
    if explicit_branch:
        return explicit_branch
    result = run(["git", "branch", "--show-current"], cwd=cwd)
    branch = result.stdout.strip()
    if result.returncode != 0 or not branch:
        raise SystemExit("Could not determine current git branch; pass --branch explicitly.")
    return branch


def rev_parse(cwd: pathlib.Path, ref: str) -> str | None:
    result = run(["git", "rev-parse", ref], cwd=cwd)
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        return None
    return value


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
    parser.add_argument("--repo-slug", help="GitHub repo slug to resolve environments for, e.g. owner/repo.")
    parser.add_argument(
        "--list-envs",
        action="store_true",
        help="List candidate environments for the inferred or explicit repo slug, then exit.",
    )
    parser.add_argument(
        "--allow-env-mismatch",
        action="store_true",
        help="Allow launching even when inferred repo slug and selected environment label do not match.",
    )
    parser.add_argument("--branch", help="Git branch to run in cloud.")
    parser.add_argument(
        "--remote-branch",
        help="Remote-tracking branch that should match the launched cloud branch. Defaults to origin/<branch>.",
    )
    parser.add_argument("--cwd", default=".", help="Repo root for git branch and env inference.")
    parser.add_argument("--manifest", help="Output manifest path. Defaults to <prompt-dir>/fanout-manifest.json.")
    parser.add_argument(
        "--allow-unpushed",
        action="store_true",
        help="Allow launching even when local HEAD differs from the remote-tracking branch head.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing them.")
    args = parser.parse_args()

    cwd = pathlib.Path(args.cwd).expanduser().resolve()
    prompt_dir = pathlib.Path(args.prompt_dir).expanduser().resolve()
    manifest_path = pathlib.Path(args.manifest).expanduser().resolve() if args.manifest else (prompt_dir / "fanout-manifest.json")

    repo_slug = args.repo_slug or infer_repo_slug(cwd)
    if args.list_envs:
        candidates = fetch_api_env_candidates(repo_slug)
        print(format_env_choices(candidates))
        return 0

    env_id, env_label, env_candidates = detect_env(args.env, args.env_label, cwd, repo_slug)
    if not args.allow_env_mismatch and not env_matches_repo(repo_slug, env_label):
        raise SystemExit(
            "Refusing to launch cloud fanout with mismatched repo/environment.\n"
            f"Inferred repo slug: {repo_slug or 'unknown'}\n"
            f"Selected environment: {env_label or env_id}\n"
            "Pass --env-label for the correct repo or use --allow-env-mismatch if this is intentional."
        )
    branch = detect_branch(cwd, args.branch)
    remote_branch = args.remote_branch or f"origin/{branch}"
    local_head = rev_parse(cwd, "HEAD")
    remote_head = rev_parse(cwd, remote_branch)
    if remote_head is None:
        raise SystemExit(
            f"Could not resolve remote branch {remote_branch!r}. Push the branch first or pass --remote-branch explicitly."
        )
    if local_head is None:
        raise SystemExit("Could not resolve local HEAD.")
    if local_head != remote_head and not args.allow_unpushed:
        raise SystemExit(
            "Local HEAD does not match the remote branch cloud will see.\n"
            f"  local HEAD:  {local_head}\n"
            f"  remote HEAD: {remote_head}\n"
            f"  remote ref:  {remote_branch}\n"
            "Push first, or pass --allow-unpushed if you intentionally want to launch against stale remote state."
        )
    prompts = discover_prompts(prompt_dir, args.pattern, args.prompt)
    prompt_attempts = parse_prompt_attempt_overrides(args.prompt_attempt)

    manifest: dict[str, Any] = {
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "cwd": str(cwd),
        "repo_slug": repo_slug,
        "prompt_dir": str(prompt_dir),
        "pattern": args.pattern,
        "branch": branch,
        "remote_branch": remote_branch,
        "local_head": local_head,
        "remote_head": remote_head,
        "branch_synced": local_head == remote_head,
        "env_id": env_id,
        "env_label": env_label,
        "env_candidates": [
            {"id": candidate.get("id"), "label": candidate.get("label"), "repos": env_repo_slugs(candidate)}
            for candidate in env_candidates
        ],
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
