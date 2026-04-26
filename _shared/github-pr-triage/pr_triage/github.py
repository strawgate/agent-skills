from __future__ import annotations

import json
import subprocess
from typing import Optional


def gh_apigraphql(query: str, variables: Optional[dict] = None) -> dict:
    """Run gh api graphql and return parsed JSON."""
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    if variables:
        for key, value in variables.items():
            cmd.extend(["-F", f"{key}={value}"])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh api failed: {result.stderr}")
    return json.loads(result.stdout)


def gh_api(endpoint: str, paginate: bool = False) -> dict | list:
    """Run gh api and return parsed JSON."""
    cmd = ["gh", "api", endpoint]
    if paginate:
        cmd.append("--paginate")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh api failed: {result.stderr}")
    data = json.loads(result.stdout)
    return data


def get_owner_repo(owner_repo: str) -> tuple[str, str]:
    parts = owner_repo.split("/")
    if len(parts) != 2:
        raise ValueError(f"Expected OWNER/REPO, got {owner_repo}")
    return parts[0], parts[1]


def fetch_overview(owner: str, repo: str) -> dict:
    """Fetch overview of all open PRs - 1 GraphQL point for all PRs."""
    query = """
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
            labels(first: 20) { totalCount nodes { name } }
            comments { totalCount }
            reviewRequests(first: 10) { totalCount }
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

    variables = {"owner": owner, "repo": repo}
    response = gh_apigraphql(query, variables)
    return response["data"]["repository"]["pullRequests"]["nodes"]


def fetch_pr_details(owner: str, repo: str, pr_number: int) -> dict:
    """Fetch full details for a single PR - ~4 GraphQL points."""
    # Fetch PR metadata via GraphQL
    query = """
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          number
          title
          body
          state
          isDraft
          mergeable
          author { login }
          additions
          deletions
          changedFiles
          commits { totalCount }
          createdAt
          updatedAt
          baseRefName
          headRefName
        }
      }
    }
    """

    variables = {"owner": owner, "repo": repo, "number": pr_number}
    gql_response = gh_apigraphql(query, variables)
    pr_data = gql_response["data"]["repository"]["pullRequest"]

    # Fetch checks via GraphQL
    checks_query = """
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  state
                }
              }
            }
          }
        }
      }
    }
    """
    checks_response = gh_apigraphql(checks_query, variables)
    checks_data = checks_response["data"]["repository"]["pullRequest"]["commits"]["nodes"]
    ci_state = None
    if checks_data:
        rollup = checks_data[0].get("commit", {}).get("statusCheckRollup", {})
        if rollup:
            ci_state = rollup.get("state")

    # Add CI state to pr_data
    pr_data["_ci_state"] = ci_state

    # Fetch review threads via GraphQL
    threads_query = """
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
        thread_vars = {"owner": owner, "repo": repo, "number": pr_number, "endCursor": end_cursor or ""}
        thread_response = gh_apigraphql(threads_query, thread_vars)
        threads_data = thread_response["data"]["repository"]["pullRequest"]["reviewThreads"]
        all_threads.extend(threads_data["nodes"])
        page_info = threads_data.get("pageInfo", {})
        if page_info.get("hasNextPage"):
            end_cursor = page_info.get("endCursor")
        else:
            break

    return {
        "pr": pr_data,
        "threads": all_threads,
    }


def fetch_pr_comments(owner: str, repo: str, pr_number: int) -> list:
    """Fetch PR comments via REST (free)."""
    return gh_api(f"repos/{owner}/{repo}/pulls/{pr_number}/comments", paginate=True)


def fetch_pr_reviews(owner: str, repo: str, pr_number: int) -> list:
    """Fetch PR reviews via REST (free)."""
    return gh_api(f"repos/{owner}/{repo}/pulls/{pr_number}/reviews", paginate=True)


def fetch_pr_files(owner: str, repo: str, pr_number: int) -> tuple[list[dict], str]:
    """Fetch PR file list with patches via REST (free). Returns (files, diff_text)."""
    files = gh_api(f"repos/{owner}/{repo}/pulls/{pr_number}/files", paginate=True)

    # Build unified diff
    diff_lines = []
    for f in files:
        patch = f.get("patch", "")
        if patch:
            diff_lines.append(f"--- a/{f['filename']}")
            diff_lines.append(f"+++ b/{f['filename']}")
            diff_lines.append(patch)
            diff_lines.append("")

    return files, "\n".join(diff_lines)
