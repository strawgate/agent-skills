"""Fetch GitHub PRs for triage."""

from __future__ import annotations

from pathlib import Path
from typing import Optional
from .github import gh_graphql, gh_rest, get_owner_repo, save_json


PR_OVERVIEW_QUERY = """
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    pullRequests(first: 100, states: OPEN) {
      nodes {
        number
        title
        isDraft
        mergeable
        changedFiles
        additions
        deletions
        author { login }
        createdAt
        updatedAt
        baseRefName
        headRefName
        labels { totalCount }
        comments { totalCount }
        reviewRequests { totalCount }
        reviewThreads { totalCount }
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup { state }
            }
          }
        }
      }
    }
  }
}
"""


def fetch_pr_overview(owner: str, repo: str) -> list[dict]:
    """Fetch overview of all open PRs - 1 GraphQL point."""
    response = gh_graphql(PR_OVERVIEW_QUERY, {"owner": owner, "repo": repo})
    return response["data"]["repository"]["pullRequests"]["nodes"]


def fetch_pr_details(owner: str, repo: str, pr_number: int) -> dict:
    """Fetch full PR details - ~2 GraphQL points."""
    # PR metadata
    query = """
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          number title body state isDraft mergeable
          author { login }
          additions deletions changedFiles
          commits { totalCount }
          createdAt updatedAt
          baseRefName headRefName
        }
      }
    }
    """
    pr_data = gh_graphql(query, {"owner": owner, "repo": repo, "number": pr_number})
    return pr_data["data"]["repository"]["pullRequest"]


def fetch_pr_threads(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch PR review threads - 1 GraphQL point."""
    query = """
    query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              isOutdated
              isCollapsed
              path
              line
              startLine
              comments(first: 100) {
                nodes {
                  id
                  databaseId
                  body
                  createdAt
                  author { login }
                }
              }
            }
          }
        }
      }
    }
    """
    all_threads = []
    end_cursor = None
    while True:
        result = gh_graphql(query, {"owner": owner, "repo": repo, "number": pr_number, "endCursor": end_cursor or ""})
        data = result["data"]["repository"]["pullRequest"]["reviewThreads"]
        all_threads.extend(data["nodes"])
        if data["pageInfo"]["hasNextPage"]:
            end_cursor = data["pageInfo"]["endCursor"]
        else:
            break
    return all_threads


def fetch_pr_comments(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch PR comments via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/pulls/{pr_number}/comments", paginate=True)


def fetch_pr_reviews(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch PR reviews via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/pulls/{pr_number}/reviews", paginate=True)


def fetch_pr_diff(owner: str, repo: str, pr_number: int) -> str:
    """Fetch PR diff via REST (free)."""
    result = gh_rest(f"repos/{owner}/{repo}/pulls/{pr_number}", paginate=False)
    diff_url = f"https://github.com/{owner}/{repo}/pull/{pr_number}.diff"
    import subprocess
    proc = subprocess.run(
        ["gh", "api", diff_url],
        capture_output=True, text=True
    )
    return proc.stdout


def fetch_pr_files(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch PR file list with patches via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/pulls/{pr_number}/files", paginate=True)
