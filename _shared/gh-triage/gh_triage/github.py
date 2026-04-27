"""Shared GitHub client for GraphQL and REST operations."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Optional


def gh_graphql(query: str, variables: Optional[dict] = None) -> dict:
    """Run gh api graphql and return parsed JSON."""
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    if variables:
        for key, value in variables.items():
            cmd.extend(["-F", f"{key}={value}"])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh graphql failed: {result.stderr}")
    return json.loads(result.stdout)


def gh_rest(endpoint: str, paginate: bool = False) -> dict | list:
    """Run gh api and return parsed JSON."""
    cmd = ["gh", "api", endpoint]
    if paginate:
        cmd.append("--paginate")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh api failed: {result.stderr}")
    return json.loads(result.stdout)


def get_owner_repo(owner_repo: str) -> tuple[str, str]:
    """Parse OWNER/REPO string into parts."""
    parts = owner_repo.split("/")
    if len(parts) != 2:
        raise ValueError(f"Expected OWNER/REPO, got {owner_repo}")
    return parts[0], parts[1]


def save_json(data: dict | list, path: Path) -> None:
    """Save data to JSON file."""
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def ci_icon(state: Optional[str]) -> str:
    """Convert CI state to icon."""
    return {
        "SUCCESS": "✓",
        "FAILURE": "✗",
        "ERROR": "✗",
        "PENDING": "⏳",
        "EXPECTED": "⏳",
    }.get(state or "", "?")


def ci_color(state: Optional[str]) -> str:
    """Get color for CI state."""
    return {
        "SUCCESS": "green",
        "FAILURE": "red",
        "ERROR": "red",
        "PENDING": "yellow",
        "EXPECTED": "yellow",
    }.get(state or "", "dim")
