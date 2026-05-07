"""Unified GitHub issue and PR triage CLI."""

import json
import shutil
from pathlib import Path

import click
from rich.console import Console
from rich.table import Table

from .fetch_issues import fetch_issue_details, fetch_issue_overview, fetch_issue_comments
from .fetch_prs import (
    fetch_check_annotations,
    fetch_pr_checks,
    fetch_pr_comments,
    fetch_pr_details,
    fetch_pr_diff,
    fetch_pr_files,
    fetch_pr_overview,
    fetch_pr_reviews,
    fetch_pr_threads,
)
from .github import ci_icon, ci_color, get_owner_repo, save_json

console = Console()


def get_output_dir(owner_repo: str, custom_dir: str | None = None) -> Path:
    if custom_dir:
        return Path(custom_dir)
    safe_name = owner_repo.replace("/", "__")
    return Path(f"/tmp/gh-triage/{safe_name}")


def ensure_dirs(base: Path) -> None:
    (base / "prs").mkdir(parents=True, exist_ok=True)
    (base / "issues").mkdir(parents=True, exist_ok=True)


@click.group()
def cli():
    """GitHub issue and PR triage - unified CLI."""
    pass


@cli.command()
@click.argument("owner_repo")
@click.option("--output-dir", "-o")
def issues(owner_repo: str, output_dir: str | None):
    """Fetch issue overview (~1 GraphQL point)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    ensure_dirs(out_dir)

    console.print(f"[bold]Issue Overview: {owner_repo}[/bold]")
    console.print("[dim]Cost: ~1 GraphQL point[/dim]\n")

    issues_data = fetch_issue_overview(owner, repo)
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

        table.add_row(
            str(issue["number"]),
            issue.get("state", ""),
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
@click.option("--output-dir", "-o")
def prs(owner_repo: str, output_dir: str | None):
    """Fetch PR overview (~1 GraphQL point)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    ensure_dirs(out_dir)

    console.print(f"[bold]PR Overview: {owner_repo}[/bold]")
    console.print("[dim]Cost: ~1 GraphQL point[/dim]\n")

    prs_data = fetch_pr_overview(owner, repo)
    save_json({"owner": owner, "repo": repo, "pullRequests": prs_data}, out_dir / "open-prs.json")

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
        ci_state = None
        commits = pr.get("commits", {}).get("nodes", [])
        if commits:
            rollup = commits[0].get("commit", {}).get("statusCheckRollup", {})
            ci_state = rollup.get("state")

        ci_str = f"[{ci_color(ci_state)}]{ci_icon(ci_state)}[/]"

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
@click.option("--output-dir", "-o")
def pr_details(owner_repo: str, pr_number: int, output_dir: str | None):
    """Fetch full PR details (~1 GraphQL point + REST free)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    pr_dir = out_dir / "prs" / str(pr_number)
    pr_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[bold]PR Details: {owner_repo} #{pr_number}[/bold]\n")

    console.print("[dim]Fetching PR metadata...[/dim]")
    pr_data = fetch_pr_details(owner, repo, pr_number)

    console.print("[dim]Fetching threads...[/dim]")
    threads = fetch_pr_threads(owner, repo, pr_number)

    console.print("[dim]Fetching comments (REST, free)...[/dim]")
    comments = fetch_pr_comments(owner, repo, pr_number)

    console.print("[dim]Fetching reviews (REST, free)...[/dim]")
    reviews = fetch_pr_reviews(owner, repo, pr_number)

    console.print("[dim]Fetching diff (REST, free)...[/dim]")
    diff_text = fetch_pr_diff(owner, repo, pr_number)

    console.print("[dim]Fetching files (REST, free)...[/dim]")
    files = fetch_pr_files(owner, repo, pr_number)

    console.print("[dim]Fetching check runs (GraphQL, ~1 point)...[/dim]")
    checks = fetch_pr_checks(owner, repo, pr_number)

    # Save all data
    save_json(pr_data, pr_dir / "pr.json")
    save_json(threads, pr_dir / "threads.json")
    save_json(comments, pr_dir / "comments.json")
    save_json(reviews, pr_dir / "reviews.json")
    save_json(files, pr_dir / "files.json")
    (pr_dir / "pr.diff").write_text(diff_text)

    # Save check runs and annotations
    checks_dir = pr_dir / "checks"
    checks_dir.mkdir(exist_ok=True)
    failed_checks = []
    for check in checks:
        run_id = check.get("databaseId")
        if run_id:
            run_dir = checks_dir / str(run_id)
            run_dir.mkdir(exist_ok=True)
            save_json(check, run_dir / "check-run.json")
            if check.get("conclusion") == "FAILURE":
                annotations = fetch_check_annotations(owner, repo, run_id)
                save_json(annotations, run_dir / "annotations.json")
                failed_checks.append(check)

    # Derive CI state from check runs
    ci_state = _derive_ci_state(checks)
    unresolved = sum(1 for t in threads if not t.get("isResolved"))

    metadata = {
        "number": pr_number,
        "isDraft": pr_data.get("isDraft", False),
        "mergeable": pr_data.get("mergeable", ""),
        "updatedAt": pr_data.get("updatedAt", ""),
        "diffLines": len(diff_text.splitlines()) if diff_text else 0,
        "unresolvedThreads": unresolved,
        "ciState": ci_state,
        "checkCount": len(checks),
        "failedCheckCount": len(failed_checks),
    }
    save_json(metadata, pr_dir / "metadata.json")

    # Print check summary
    if checks:
        console.print(f"\n[bold]Checks ({len(checks)} total)[/bold]")
        if failed_checks:
            console.print(f"[red]  ✗ {len(failed_checks)} failed[/red]")
            for c in failed_checks[:5]:
                title = c.get("title") or (c.get("summary") or "")[:60]
                console.print(f"    - {c.get('name', 'unknown')}: {title}")
        else:
            console.print("[green]  ✓ All checks passed[/green]")

    console.print(f"\n## [cyan]PR #{pr_number}[/cyan]: {pr_data.get('title', '')}")
    console.print(f"**Author:** {pr_data.get('author', {}).get('login', 'unknown')}")
    console.print(f"**Draft:** {pr_data.get('isDraft', False)}")
    console.print(f"**Mergeable:** {pr_data.get('mergeable', '')}")
    console.print(f"**CI:** {ci_state or 'Unknown'}")

    if unresolved > 0:
        console.print(f"\n[red]Unresolved Threads: ✗ {unresolved}[/red]")
        for thread in threads[:3]:
            if not thread.get("isResolved"):
                thread_comments = thread.get("comments", {}).get("nodes", [{}])
                author = thread_comments[0].get("author", {}).get("login", "unknown") if thread_comments else "unknown"
                console.print(f"  - {thread.get('path')}:{thread.get('line')} by {author}")
    else:
        console.print("\n[green]Unresolved Threads: ✓[/green]")

    console.print(f"\n[dim]Files: {len(files)} | Diff: {metadata['diffLines']} lines[/dim]")
    console.print(f"[dim]Saved to: {pr_dir}[/dim]")


def _derive_ci_state(checks: list[dict]) -> str | None:
    """Derive overall CI state from check runs."""
    if not checks:
        return None
    completed = {c.get("conclusion") for c in checks if c.get("status") == "COMPLETED"}
    in_progress = any(c.get("status") == "IN_PROGRESS" for c in checks)
    if "FAILURE" in completed or "ERROR" in completed or "ACTION_REQUIRED" in completed:
        return "FAILURE"
    if completed or in_progress:
        return "PENDING" if in_progress else "SUCCESS"
    if in_progress:
        return "PENDING"
    return "SUCCESS"


@cli.command()
@click.argument("owner_repo")
@click.argument("pr_number", type=int)
@click.option("--output-dir", "-o")
def pr_context(owner_repo: str, pr_number: int, output_dir: str | None):
    """Fetch PR context bundle for follow-through.

    Copies the output of pr_details into a context/ subdirectory for
    use by downstream agents.
    """
    owner, repo = get_owner_repo(owner_repo)

    if output_dir:
        context_dir = Path(output_dir)
    else:
        safe_name = owner_repo.replace("/", "__")
        context_dir = Path(f"/tmp/gh-triage/{safe_name}/pr-{pr_number}/context")

    context_dir.mkdir(parents=True, exist_ok=True)

    # First ensure pr_details data exists
    pr_dir = get_output_dir(owner_repo, output_dir) / "prs" / str(pr_number)
    if not pr_dir.exists():
        console.print("[dim]pr_details not cached yet — fetching now...[/dim]")
        ctx = click.get_current_context()
        ctx.invoke(pr_details, owner_repo=owner_repo, pr_number=pr_number, output_dir=output_dir)
        pr_dir = get_output_dir(owner_repo, output_dir) / "prs" / str(pr_number)

    # Copy files into context_dir
    if pr_dir.exists():
        for f in pr_dir.iterdir():
            if f.is_file():
                shutil.copy2(f, context_dir / f.name)
        # Also copy checks subdirectory
        checks_src = pr_dir / "checks"
        if checks_src.exists():
            checks_dst = context_dir / "checks"
            shutil.copytree(checks_src, checks_dst, dirs_exist_ok=True)

    console.print(f"[green]Context saved to {context_dir}[/green]")


@cli.command()
@click.argument("owner_repo")
@click.argument("issue_number", type=int)
@click.option("--output-dir", "-o")
def issue_details(owner_repo: str, issue_number: int, output_dir: str | None):
    """Fetch full issue details (REST free)."""
    owner, repo = get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)
    issue_dir = out_dir / "issues" / str(issue_number)
    issue_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[bold]Issue Details: {owner_repo} #{issue_number}[/bold]\n")

    console.print("[dim]Fetching issue metadata...[/dim]")
    issue_data = fetch_issue_details(owner, repo, issue_number)

    console.print("[dim]Fetching comments (REST, free)...[/dim]")
    comments = fetch_issue_comments(owner, repo, issue_number)

    save_json(issue_data, issue_dir / "issue.json")
    save_json(comments, issue_dir / "comments.json")

    labels_nodes = issue_data.get("labels", {}).get("nodes", [])
    assignees_nodes = issue_data.get("assignees", {}).get("nodes", [])

    console.print(f"\n## [cyan]Issue #{issue_number}[/cyan]: {issue_data.get('title', '')}")
    console.print(f"**Author:** {issue_data.get('author', {}).get('login', 'none')}")
    console.print(f"**State:** {issue_data.get('state', '')}")
    console.print(f"**Labels:** {len(labels_nodes)} - {', '.join(l['name'] for l in labels_nodes[:5])}")
    console.print(f"**Assignees:** {len(assignees_nodes)} - {', '.join(a['login'] for a in assignees_nodes[:5])}")
    console.print(f"**Comments:** {issue_data.get('comments', {}).get('totalCount', 0)}")

    body = issue_data.get("body") or "<empty>"
    if len(body) > 200:
        body = body[:200] + "..."
    console.print(f"\n**Body:**\n{body}")
    console.print(f"\n[dim]Saved to: {issue_dir}[/dim]")


if __name__ == "__main__":
    cli()
