"""Fetch GitHub PRs for triage."""

import httpx

from .github import get_owner_repo, gh_graphql, gh_rest, save_json


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
    """Fetch overview of all open PRs (~1 GraphQL point).

    GraphQL is used here because REST /pulls has no efficient totalCount
    for labels, comments, reviewRequests, reviewThreads, and CI status.
    """
    result = gh_graphql(PR_OVERVIEW_QUERY, {"owner": owner, "repo": repo})
    return result["repository"]["pullRequests"]["nodes"]


def fetch_pr_details(owner: str, repo: str, pr_number: int) -> dict:
    """Fetch PR metadata via REST (free).

    Returns a subset of the full REST response plus the diff_url for convenience.
    """
    pr = gh_rest(f"repos/{owner}/{repo}/pulls/{pr_number}")
    return {
        "number": pr["number"],
        "title": pr["title"],
        "body": pr["body"],
        "state": pr["state"],
        "isDraft": pr["draft"],
        "mergeable": pr.get("mergeable"),
        "additions": pr["additions"],
        "deletions": pr["deletions"],
        "changedFiles": pr["changed_files"],
        "commits": {"totalCount": pr["commits"]},
        "author": {"login": pr["user"]["login"]},
        "createdAt": pr["created_at"],
        "updatedAt": pr["updated_at"],
        "baseRefName": pr["base"]["ref"],
        "headRefName": pr["head"]["ref"],
        "diff_url": pr["diff_url"],
        "head_sha": pr["head"]["sha"],
    }


def fetch_pr_threads(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch PR review threads with resolved status (GraphQL, 1 point per page).

    REST can't provide resolved/unresolved status efficiently, so GraphQL is required.
    """
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
        result = gh_graphql(
            query,
            {"owner": owner, "repo": repo, "number": pr_number, "endCursor": end_cursor or ""},
        )
        data = result["repository"]["pullRequest"]["reviewThreads"]
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
    """Fetch PR unified diff via REST with diff Accept header (free)."""
    import subprocess

    result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
    token = result.stdout.strip()
    resp = httpx.get(
        f"https://api.github.com/repos/{owner}/{repo}/pulls/{pr_number}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github.v3.diff",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        timeout=30,
    )
    if resp.status_code >= 400:
        raise RuntimeError(f"Failed to fetch diff: {resp.status_code} {resp.text[:200]}")
    return resp.text


def fetch_pr_files(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch PR file list with patches via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/pulls/{pr_number}/files", paginate=True)


# ---------------------------------------------------------------------------
# Check runs
# ---------------------------------------------------------------------------

PR_CHECKS_QUERY = """
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      commits(last: 1) {
        nodes {
          commit {
            checkSuites(first: 10) {
              nodes {
                app { name slug databaseId }
                status
                conclusion
                checkRuns(first: 50) {
                  nodes {
                    databaseId
                    name
                    status
                    conclusion
                    title
                    summary
                    detailsUrl
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
"""


def fetch_pr_checks(owner: str, repo: str, pr_number: int) -> list[dict]:
    """Fetch check runs for the latest commit (~1 GraphQL point).

    Returns a flat list of check runs with app info merged in.
    """
    result = gh_graphql(PR_CHECKS_QUERY, {"owner": owner, "repo": repo, "pr": pr_number})
    commits = result.get("repository", {}).get("pullRequest", {}).get("commits", {}).get("nodes", [])
    runs = []
    for commit in commits:
        for suite in commit.get("commit", {}).get("checkSuites", {}).get("nodes", []):
            app = suite.get("app") or {}
            for run in suite.get("checkRuns", {}).get("nodes", []):
                runs.append({
                    "app": app.get("name", ""),
                    "app_slug": app.get("slug", ""),
                    "app_database_id": app.get("databaseId"),
                    "suite_status": suite.get("status", ""),
                    "suite_conclusion": suite.get("conclusion", ""),
                    **run,
                })
    return runs


def fetch_check_annotations(owner: str, repo: str, check_run_id: int) -> list[dict]:
    """Fetch annotations for a single check run via REST (free)."""
    return gh_rest(f"repos/{owner}/{repo}/check-runs/{check_run_id}/annotations", paginate=True)
