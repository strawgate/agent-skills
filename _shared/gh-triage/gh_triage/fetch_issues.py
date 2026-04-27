"""Fetch GitHub issues for triage."""

from __future__ import annotations

from pathlib import Path
from typing import Optional
from .github import gh_graphql, gh_rest, get_owner_repo, save_json


ISSUE_OVERVIEW_QUERY = """
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    issues(first: 100, states: OPEN) {
      nodes {
        number
        title
        state
        createdAt
        updatedAt
        author { login }
        labels { totalCount }
        assignees { totalCount }
        comments { totalCount }
        milestone { title }
      }
    }
  }
}
"""


def fetch_issue_overview(owner: str, repo: str) -> list[dict]:
    """Fetch overview of all open issues - 1 GraphQL point.

    GraphQL is used here because REST /issues has no efficient totalCount.
    With REST, we'd need to fetch all issues and count them.
    """
    response = gh_graphql(ISSUE_OVERVIEW_QUERY, {"owner": owner, "repo": repo})
    return response["data"]["repository"]["issues"]["nodes"]


def fetch_closed_issues(owner: str, repo: str) -> list[dict]:
    """Fetch closed issues via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/issues?state=closed&per_page=100", paginate=True)


def fetch_issue_comments(owner: str, repo: str, issue_number: int) -> list[dict]:
    """Fetch issue comments via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/issues/{issue_number}/comments", paginate=True)


def fetch_issue_details(owner: str, repo: str, issue_number: int) -> dict:
    """Fetch full issue details via REST (free).

    REST is preferred here because all data comes from 2 free calls:
    - Issue metadata + assignees from /issues/{number}
    - Labels from /issues/{number}/labels
    Total: 2 free calls vs 1 GraphQL point.
    """
    issue_resp = gh_rest(f"repos/{owner}/{repo}/issues/{issue_number}", paginate=False)
    labels = gh_rest(f"repos/{owner}/{repo}/issues/{issue_number}/labels", paginate=False) or []

    return {
        "number": issue_resp["number"],
        "title": issue_resp["title"],
        "body": issue_resp["body"],
        "state": issue_resp["state"],
        "createdAt": issue_resp["created_at"],
        "updatedAt": issue_resp["updated_at"],
        "author": {"login": issue_resp["user"]["login"]},
        "labels": {"nodes": [{"name": l["name"]} for l in labels]},
        "assignees": {"nodes": [{"login": a["login"]} for a in issue_resp.get("assignees", [])]},
        "comments": {"totalCount": issue_resp["comments"]},
        "milestone": {"title": issue_resp["milestone"]["title"] if issue_resp.get("milestone") else None},
    }


def write_issue_record(issue: dict, output_dir: Path, owner: str, repo: str) -> None:
    """Write a single issue as a text file."""
    number = issue["number"]
    lines = [
        f"number: {number}",
        f"title: {issue.get('title', '')}",
        f"state: {issue.get('state', '')}",
        f"created_at: {issue.get('createdAt', '')}",
        f"updated_at: {issue.get('updatedAt', '')}",
        f"author: {issue.get('author', {}).get('login', 'none')}",
        f"labels_count: {issue.get('labels', {}).get('totalCount', 0) if isinstance(issue.get('labels'), dict) else len(issue.get('labels', {}).get('nodes', []))}",
        f"assignees_count: {issue.get('assignees', {}).get('totalCount', 0) if isinstance(issue.get('assignees'), dict) else len(issue.get('assignees', {}).get('nodes', []))}",
        f"comments_count: {issue.get('comments', {}).get('totalCount', 0) if isinstance(issue.get('comments'), dict) else issue.get('comments', 0)}",
        f"milestone: {issue.get('milestone', {}).get('title', '')}",
        f"url: https://github.com/{owner}/{repo}/issues/{number}",
        "",
        "body:",
    ]
    lines.extend((issue.get("body") or "").splitlines() or ["<empty>"])

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / f"{number:05d}.txt").write_text("\n".join(lines) + "\n")