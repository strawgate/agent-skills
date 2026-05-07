"""GitHub client using githubkit + httpx."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import httpx
from githubkit import GitHub
from githubkit.auth.token import TokenAuthStrategy


def _get_github_token() -> str:
    """Read GitHub token from gh CLI."""
    result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("Failed to get GitHub token: is gh authenticated?")
    return result.stdout.strip()


_token: str | None = None


def _get_headers() -> dict[str, str]:
    global _token
    if _token is None:
        _token = _get_github_token()
    return {
        "Authorization": f"Bearer {_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


_client: GitHub | None = None


def get_client() -> GitHub:
    """Return a singleton githubkit client authenticated via gh."""
    global _client
    if _client is None:
        _client = GitHub(TokenAuthStrategy(token=_get_github_token()))
    return _client


class GitHubAPIError(RuntimeError):
    """Raised when a GitHub API call fails."""
    pass


def gh_graphql(query: str, variables: dict[str, Any] | None = None) -> dict[str, Any]:
    """Execute a GraphQL query via githubkit.

    Raises GitHubAPIError if GitHub returns errors.
    """
    client = get_client()
    try:
        result = client.graphql.request(query, variables or {})
    except Exception as e:
        raise GitHubAPIError(f"GraphQL request failed: {e}") from e

    if "errors" in result:
        msgs = "; ".join(err.get("message", str(err)) for err in result["errors"])
        raise GitHubAPIError(f"GraphQL errors: {msgs}")
    return result


def gh_rest(endpoint: str, *, paginate: bool = False) -> dict[str, Any] | list[dict[str, Any]]:
    """Execute a GitHub REST API call via httpx.

    Uses the same token as gh so no extra auth needed.
    Raises GitHubAPIError on non-OK responses.
    """
    headers = _get_headers()
    base = "https://api.github.com"

    if paginate:
        results: list[dict[str, Any]] = []
        page = 1
        while True:
            url = f"{base}/{endpoint}" + ("&" if "?" in endpoint else "?") + f"page={page}&per_page=100"
            resp = httpx.get(url, headers=headers, timeout=30)
            if resp.status_code >= 400:
                raise GitHubAPIError(f"REST {endpoint} returned {resp.status_code}: {resp.text[:200]}")
            data = resp.json()
            if not data:
                break
            results.extend(data)
            if len(data) < 100:
                break
            page += 1
        return results

    resp = httpx.get(f"{base}/{endpoint}", headers=headers, timeout=30)
    if resp.status_code >= 400:
        raise GitHubAPIError(f"REST {endpoint} returned {resp.status_code}: {resp.text[:200]}")
    return resp.json()


def gh_rest_raw(endpoint: str) -> str:
    """Execute a REST API call that returns raw (non-JSON) text."""
    headers = _get_headers()
    base = "https://api.github.com"
    resp = httpx.get(f"{base}/{endpoint}", headers=headers, timeout=30)
    if resp.status_code >= 400:
        raise GitHubAPIError(f"REST {endpoint} returned {resp.status_code}: {resp.text[:200]}")
    return resp.text


def save_json(data: dict[str, Any] | list[dict[str, Any]], path: str | Path) -> None:
    """Save data as JSON to the given path."""
    if isinstance(path, str):
        path = Path(path)
    path.write_text(json.dumps(data, indent=2, default=str))


def get_owner_repo(owner_repo: str) -> tuple[str, str]:
    """Parse OWNER/REPO string into parts."""
    parts = owner_repo.split("/")
    if len(parts) != 2:
        raise ValueError(f"Expected OWNER/REPO, got {owner_repo}")
    return parts[0], parts[1]


def ci_icon(state: str | None) -> str:
    """Convert CI state to icon."""
    return {"SUCCESS": "✓", "FAILURE": "✗", "ERROR": "✗", "PENDING": "⏳", "EXPECTED": "⏳"}.get(state or "", "?")


def ci_color(state: str | None) -> str:
    """Get color for CI state."""
    return {"SUCCESS": "green", "FAILURE": "red", "ERROR": "red", "PENDING": "yellow", "EXPECTED": "yellow"}.get(state or "", "dim")
