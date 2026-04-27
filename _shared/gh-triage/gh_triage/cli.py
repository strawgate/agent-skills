"""Unified GitHub issue and PR triage CLI."""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.table import Table

from .github import get_owner_repo, ci_icon, ci_color
from .fetch_issues import fetch_issue_overview, write_issue_record
from .fetch_prs import fetch_pr_overview, fetch_pr_details, fetch_pr_threads, fetch_pr_comments, fetch_pr_reviews, fetch_pr_diff, fetch_pr_files

console = Console()


def get_output_dir(owner_repo: str, custom_dir: Optional[str] = None) -> Path:
    if custom_dir:
        return Path(custom_dir)
    safe_name = owner_repo.replace("/", "__")
    return Path(f"/tmp/gh-triage/{safe_name}")


def ensure_dirs(base: Path) -> None:
    (base / "prs").mkdir(parents=True, exist_ok=True)
    (base / "prs-merged").mkdir(parents=True, exist_ok=True)
    (base / "prs-closed").mkdir(parents=True, exist_ok=True)
    (base / "issues").mkdir(parents=True, exist_ok=True)


@click.group()
def cli():
    """GitHub issue and PR triage - unified CLI."""
    pass


@cli.command()
@click.argument("owner_repo")
@click.option("--output-dir", "-o", help="Output directory")
def issues(owner_repo: str, output_dir: Optional[str]):
    """Fetch issue overview (~1 GraphQL point)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    ensure_dirs(out_dir)

    console.print(f"[bold]Issue Overview: {owner_repo}[/bold]")
    console.print(f"[dim]Cost: ~1 GraphQL point[/dim]\n")

    issues_data = fetch_issue_overview(owner, repo)

    save_json = lambda d, p: (Path(p).write_text(__import__('json').dumps(d, indent=2, default=str)))
    save_json({"owner": owner, "repo": repo, "issues": issues_data}, out_dir / "open-issues.json")

    table = Table(title=f"Open Issues ({len(issues_data)})")
    table.add_column("#", style="cyan")
    table.add_column("State")
    table.add_column("Labels")
    table.add_column("Assignees")
    table.add_column("Comments")
    table.add_column("Created")
    table.add_column("Title")

    for issue in issues_data:
        labels = issue.get("labels", {}).get("totalCount", 0)
        assignees = issue.get("assignees", {}).get("totalCount", 0)
        comments = issue.get("comments", {}).get("totalCount", 0)
        created = issue.get("createdAt", "")[:10]
        state = issue.get("state", "")

        table.add_row(
            str(issue["number"]),
            state,
            str(labels),
            str(assignees),
            str(comments),
            created,
            issue["title"][:60],
        )

    console.print(table)
    console.print(f"\n[dim]Data: {out_dir}/open-issues.json[/dim]")


@cli.command()
@click.argument("owner_repo")
@click.option("--output-dir", "-o", help="Output directory")
def prs(owner_repo: str, output_dir: Optional[str]):
    """Fetch PR overview (~1 GraphQL point)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    ensure_dirs(out_dir)

    console.print(f"[bold]PR Overview: {owner_repo}[/bold]")
    console.print(f"[dim]Cost: ~1 GraphQL point[/dim]\n")

    prs_data = fetch_pr_overview(owner, repo)

    import json
    Path(out_dir / "open-prs.json").write_text(json.dumps({"owner": owner, "repo": repo, "pullRequests": prs_data}, indent=2, default=str))

    table = Table(title=f"Open PRs ({len(prs_data)})")
    table.add_column("#", style="cyan")
    table.add_column("Draft")
    table.add_column("Mergeable")
    table.add_column("CI")
    table.add_column("Threads")
    table.add_column("Comments")
    table.add_column("+L")
    table.add_column("-L")
    table.add_column("Title")

    for pr in prs_data:
        # Get CI state
        ci_state = None
        commits = pr.get("commits", {}).get("nodes", [])
        if commits:
            rollup = commits[0].get("commit", {}).get("statusCheckRollup", {})
            ci_state = rollup.get("state")

        ci = ci_icon(ci_state)
        color = ci_color(ci_state)
        ci_str = f"[{color}]{ci}[/{color}]"

        threads = pr.get("reviewThreads", {}).get("totalCount", 0)
        threads_str = f"[red]✗{threads}[/red]" if threads > 0 else "[green]✓[/green]"

        comments = pr.get("comments", {}).get("totalCount", 0)

        draft = "📝" if pr.get("isDraft") else ""

        table.add_row(
            str(pr["number"]),
            draft,
            pr.get("mergeable", ""),
            ci_str,
            threads_str,
            str(comments),
            f"+{pr.get('additions', 0)}",
            f"-{pr.get('deletions', 0)}",
            pr["title"][:50],
        )

    console.print(table)
    console.print(f"\n[dim]Data: {out_dir}/open-prs.json[/dim]")


@cli.command()
@click.argument("owner_repo")
@click.argument("pr_number", type=int)
@click.option("--output-dir", "-o", help="Output directory")
def pr_details(owner_repo: str, pr_number: int, output_dir: Optional[str]):
    """Fetch full PR details (~2 GraphQL points)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    pr_dir = out_dir / "prs" / str(pr_number)
    pr_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[bold]PR Details: {owner_repo} #{pr_number}[/bold]\n")

    # Fetch GraphQL data
    console.print("[dim]Fetching PR metadata...[/dim]")
    pr_data = fetch_pr_details(owner, repo, pr_number)

    console.print("[dim]Fetching threads...[/dim]")
    threads = fetch_pr_threads(owner, repo, pr_number)

    # Fetch REST data (free)
    console.print("[dim]Fetching comments (REST, free)...[/dim]")
    comments = fetch_pr_comments(owner, repo, pr_number)

    console.print("[dim]Fetching reviews (REST, free)...[/dim]")
    reviews = fetch_pr_reviews(owner, repo, pr_number)

    console.print("[dim]Fetching diff (REST, free)...[/dim]")
    diff_text = fetch_pr_diff(owner, repo, pr_number)

    console.print("[dim]Fetching files (REST, free)...[/dim]")
    files = fetch_pr_files(owner, repo, pr_number)

    # Save files
    import json
    Path(pr_dir / "pr.json").write_text(json.dumps(pr_data, indent=2, default=str))
    Path(pr_dir / "threads.json").write_text(json.dumps(threads, indent=2, default=str))
    Path(pr_dir / "comments.json").write_text(json.dumps(comments, indent=2, default=str))
    Path(pr_dir / "reviews.json").write_text(json.dumps(reviews, indent=2, default=str))
    Path(pr_dir / "pr.diff").write_text(diff_text)
    Path(pr_dir / "files.json").write_text(json.dumps(files, indent=2, default=str))

    # Metadata
    ci_state = None
    unresolved = sum(1 for t in threads if not t.get("isResolved"))

    metadata = {
        "number": pr_number,
        "isDraft": pr_data.get("isDraft", False),
        "mergeable": pr_data.get("mergeable", ""),
        "updatedAt": pr_data.get("updatedAt", ""),
        "diffLines": len(diff_text.splitlines()) if diff_text else 0,
        "unresolvedThreads": unresolved,
    }
    Path(pr_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, default=str))

    # Summary
    console.print(f"\n## [cyan]PR #{pr_number}[/cyan]: {pr_data.get('title', '')}")
    console.print(f"**Author:** {pr_data.get('author', {}).get('login', 'unknown')}")
    console.print(f"**Draft:** {pr_data.get('isDraft', False)}")
    console.print(f"**Mergeable:** {pr_data.get('mergeable', '')}")
    console.print(f"**CI:** {ci_state or 'Unknown'}")

    if unresolved > 0:
        console.print(f"\n[red]Unresolved Threads: ✗ {unresolved}[/red]")
        for thread in threads[:3]:
            if not thread.get("isResolved"):
                comments = thread.get("comments", {}).get("nodes", [{}])
                author = comments[0].get("author", {}).get("login", "unknown") if comments else "unknown"
                console.print(f"  - {thread.get('path')}:{thread.get('line')} by {author}")
    else:
        console.print(f"\n[green]Unresolved Threads: ✓[/green]")

    console.print(f"\n[dim]Files: {len(files)} | Diff: {metadata['diffLines']} lines[/dim]")
    console.print(f"[dim]Saved to: {pr_dir}[/dim]")


@cli.command()
@click.argument("owner_repo")
@click.argument("pr_number", type=int)
@click.option("--output-dir", "-o", help="Output directory")
def pr_context(owner_repo: str, pr_number: int, output_dir: Optional[str]):
    """Fetch PR context bundle for follow-through."""
    owner, repo = get_owner_repo(owner_repo)

    if output_dir:
        context_dir = Path(output_dir)
    else:
        safe_name = owner_repo.replace("/", "__")
        context_dir = Path(f"/tmp/gh-triage/{safe_name}/pr-{pr_number}/context")

    context_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[bold]Fetching PR context: {owner_repo} #{pr_number}[/bold]")
    console.print(f"[dim]Output: {context_dir}[/dim]\n")

    # Fetch PR details
    pr_dir = context_dir.parent.parent / "prs" / str(pr_number)
    if not pr_dir.exists():
        # Use the pr_details flow to populate
        from .cli import pr_details as run_pr_details
        pr_dir.mkdir(parents=True, exist_ok=True)

    # Copy files from pr_dir to context_dir
    if pr_dir.exists():
        for f in pr_dir.iterdir():
            if f.is_file():
                shutil.copy2(f, context_dir / f.name)

    console.print(f"[green]Context saved to {context_dir}[/dim]")


@cli.command()
@click.argument("owner_repo")
@click.argument("issue_number", type=int)
@click.option("--output-dir", "-o", help="Output directory")
def issue_details(owner_repo: str, issue_number: int, output_dir: Optional[str]):
    """Fetch full issue details (~1 GraphQL point + REST free)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    issue_dir = out_dir / "issues" / str(issue_number)
    issue_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[bold]Issue Details: {owner_repo} #{issue_number}[/bold]\n")

    # Fetch issue via GraphQL
    console.print("[dim]Fetching issue metadata...[/dim]")
    from .fetch_issues import fetch_issue_details
    issue_data = fetch_issue_details(owner, repo, issue_number)

    # Fetch comments via REST (free)
    console.print("[dim]Fetching comments (REST, free)...[/dim]")
    from .fetch_issues import fetch_issue_comments
    comments = fetch_issue_comments(owner, repo, issue_number)

    # Save files
    import json
    Path(issue_dir / "issue.json").write_text(json.dumps(issue_data, indent=2, default=str))
    Path(issue_dir / "comments.json").write_text(json.dumps(comments, indent=2, default=str))

    # Summary
    console.print(f"\n## [cyan]Issue #{issue_number}[/cyan]: {issue_data.get('title', '')}")
    console.print(f"**Author:** {issue_data.get('author', {}).get('login', 'none')}")
    console.print(f"**State:** {issue_data.get('state', '')}")
    console.print(f"**Labels:** {issue_data.get('labels', {}).get('totalCount', 0)}")
    console.print(f"**Assignees:** {issue_data.get('assignees', {}).get('totalCount', 0)}")
    console.print(f"**Comments:** {len(comments)}")

    body = issue_data.get("body") or "<empty>"
    if len(body) > 200:
        body = body[:200] + "..."
    console.print(f"\n**Body:**\n{body}")

    console.print(f"\n[dim]Saved to: {issue_dir}[/dim]")


if __name__ == "__main__":
    cli()
