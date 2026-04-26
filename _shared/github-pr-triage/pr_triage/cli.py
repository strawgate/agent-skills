from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.table import Table

from . import github
from .models import PRDetails

console = Console()


def get_output_dir(owner_repo: str, custom_dir: Optional[str] = None) -> Path:
    if custom_dir:
        return Path(custom_dir)
    safe_name = owner_repo.replace("/", "__")
    return Path(f"/tmp/pr-triage/{safe_name}")


def ensure_dirs(base: Path) -> None:
    (base / "prs").mkdir(parents=True, exist_ok=True)
    (base / "prs-merged").mkdir(parents=True, exist_ok=True)
    (base / "prs-closed").mkdir(parents=True, exist_ok=True)


def save_json(data: dict | list, path: Path) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def ci_status_icon(state: Optional[str]) -> str:
    if state == "SUCCESS":
        return "✓"
    elif state in ("FAILURE", "ERROR"):
        return "✗"
    elif state in ("PENDING", "EXPECTED"):
        return "⏳"
    return "?"


def run_overview(owner: str, repo: str, output_dir: Path) -> list[dict]:
    ensure_dirs(output_dir)

    # Fetch via GraphQL
    console.print("[dim]Fetching PRs (1 GraphQL point)...[/dim]")
    prs = github.fetch_overview(owner, repo)

    # Save raw data
    save_json({"owner": owner, "repo": repo, "pull_requests": prs}, output_dir / "open-prs.json")

    # Archive closed PRs
    current_prs = {pr["number"] for pr in prs}
    for pr_dir in (output_dir / "prs").iterdir():
        if pr_dir.is_dir() and int(pr_dir.name) not in current_prs:
            closed_dir = output_dir / "prs-closed" / pr_dir.name
            closed_dir.mkdir(parents=True, exist_ok=True)
            for f in pr_dir.iterdir():
                f.rename(closed_dir / f.name)
            pr_dir.rmdir()
            console.print(f"[dim]Archived #{pr_dir.name}[/dim]")

    # Save open pr list
    with open(output_dir / "prs-open.txt", "w") as f:
        for pr in prs:
            f.write(f"{pr['number']}\t{pr['isDraft']}\t{pr['mergeable']}\t{pr['changedFiles']}\t{pr['title']}\n")

    return prs


def run_details(owner: str, repo: str, pr_number: int, output_dir: Path) -> dict:
    ensure_dirs(output_dir)
    pr_dir = output_dir / "prs" / str(pr_number)
    pr_dir.mkdir(parents=True, exist_ok=True)

    # Fetch GraphQL data
    console.print(f"[cyan]Fetching PR #{pr_number} details...[/cyan]")
    data = github.fetch_pr_details(owner, repo, pr_number)
    pr_data = data["pr"]
    threads = data["threads"]

    # Fetch REST data (free)
    console.print("[dim]  Fetching comments (REST, free)...[/dim]")
    comments = github.fetch_pr_comments(owner, repo, pr_number)

    console.print("[dim]  Fetching reviews (REST, free)...[/dim]")
    reviews = github.fetch_pr_reviews(owner, repo, pr_number)

    console.print("[dim]  Fetching files and diff (REST, free)...[/dim]")
    files, diff_text = github.fetch_pr_files(owner, repo, pr_number)

    # Save all files
    save_json(pr_data, pr_dir / "pr.json")
    save_json([], pr_dir / "checks.json")  # Individual checks require gh pr checks (2pt)
    save_json(threads, pr_dir / "threads.json")
    save_json(comments, pr_dir / "comments.json")
    save_json(reviews, pr_dir / "reviews.json")
    save_json(files, pr_dir / "files.json")

    with open(pr_dir / "pr.diff", "w") as f:
        f.write(diff_text)

    # Metadata
    ci_state = pr_data.get("_ci_state")
    checks_failed = 1 if ci_state == "FAILURE" else 0
    unresolved = sum(1 for t in threads if not t.get("isResolved"))

    metadata = {
        "number": pr_data["number"],
        "isDraft": pr_data.get("isDraft", False),
        "mergeable": pr_data.get("mergeable", ""),
        "checksFailed": checks_failed,
        "updatedAt": pr_data.get("updatedAt", ""),
        "diffLines": len(diff_text.splitlines()) if diff_text else 0,
        "unresolvedThreads": unresolved,
    }
    save_json(metadata, pr_dir / "metadata.json")

    return {
        "pr": pr_data,
        "threads": threads,
        "comments": comments,
        "reviews": reviews,
        "files_count": len(files),
        "diff_lines": len(diff_text.splitlines()) if diff_text else 0,
    }


@click.group()
def cli():
    """Efficient GitHub PR triage with caching."""
    pass


@cli.command()
@click.argument("owner_repo")
@click.option("--output-dir", "-o", help="Output directory (default: /tmp/pr-triage/OWNER__REPO)")
def overview(owner_repo: str, output_dir: Optional[str]):
    """Fetch PR overview (~1 GraphQL point)."""
    owner, repo = github.get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)

    console.print(f"[bold]PR Triage Overview: {owner_repo}[/bold]")
    console.print(f"[dim]Output: {out_dir}[/dim]\n")

    prs = run_overview(owner, repo, out_dir)

    # Render table
    table = Table(title=f"Open PRs ({len(prs)})")
    table.add_column("#", style="cyan")
    table.add_column("Draft")
    table.add_column("Mergeable")
    table.add_column("CI")
    table.add_column("Threads")
    table.add_column("Comments")
    table.add_column("+L")
    table.add_column("-L")
    table.add_column("Title")

    for pr in prs:
        # Get CI state
        ci_state = None
        if pr.get("commits", {}).get("nodes"):
            ci_state = pr["commits"]["nodes"][0].get("commit", {}).get("statusCheckRollup", {}).get("state")

        icon = ci_status_icon(ci_state)
        ci_str = f"[green]{icon}[/green]" if icon == "✓" else f"[red]{icon}[/red]" if icon == "✗" else f"[yellow]{icon}[/yellow]"

        threads_count = pr.get("reviewThreads", {}).get("totalCount", 0)
        threads_str = f"[red]✗{threads_count}[/red]" if threads_count > 0 else "[green]✓[/green]"

        comments_count = pr.get("comments", {}).get("totalCount", 0)

        draft = "📝" if pr.get("isDraft") else ""

        table.add_row(
            str(pr["number"]),
            draft,
            pr.get("mergeable", ""),
            ci_str,
            threads_str,
            str(comments_count),
            f"+{pr.get('additions', 0)}",
            f"-{pr.get('deletions', 0)}",
            pr["title"],
        )

    console.print(table)
    console.print(f"\n[dim]Run: pr-triage details {owner_repo} PR_NUMBER[/dim]")


@cli.command()
@click.argument("owner_repo")
@click.argument("pr_number", type=int)
@click.option("--output-dir", "-o", help="Output directory")
def details(owner_repo: str, pr_number: int, output_dir: Optional[str]):
    """Fetch full details for one PR (~4 GraphQL points)."""
    owner, repo = github.get_owner_repo(owner_repo)
    out_dir = get_output_dir(owner_repo, output_dir)

    console.print(f"[bold]PR Details: {owner_repo} #{pr_number}[/bold]\n")

    data = run_details(owner, repo, pr_number, out_dir)
    pr = data["pr"]
    threads = data["threads"]

    # Render summary
    console.print(f"## [cyan]PR #{pr['number']}[/cyan]: {pr['title']}")
    console.print(f"**Author:** {pr.get('author', {}).get('login', 'unknown')}")
    console.print(f"**Draft:** {pr.get('isDraft', False)}")
    console.print(f"**Mergeable:** {pr.get('mergeable', '')}")
    console.print(f"**Branches:** {pr.get('baseRefName', '')} <- {pr.get('headRefName', '')}")

    # Get CI state from statusCheckRollup
    ci_state = pr.get("_ci_state")

    if ci_state == "FAILURE":
        console.print(f"\n[red]CI: ✗ Failing[/red]")
        console.print(f"[dim]  (Run: gh pr checks {pr_number} --repo {owner_repo} for details)[/dim]")
    elif ci_state == "SUCCESS":
        console.print(f"\n[green]CI: ✓ All passing[/green]")
    else:
        console.print(f"\n[yellow]CI: {ci_state or 'Unknown'}[/yellow]")

    unresolved = sum(1 for t in threads if not t.get("isResolved"))
    if unresolved > 0:
        console.print(f"\n[red]Unresolved Threads: ✗ {unresolved}[/red]")
        for thread in threads[:5]:
            if not thread.get("isResolved"):
                comments = thread.get("comments", {}).get("nodes", [])
                author = comments[0].get("author", {}).get("login", "unknown") if comments else "unknown"
                console.print(f"  - {thread.get('path')}:{thread.get('line')} by {author}")
        if unresolved > 5:
            console.print(f"  ... and {unresolved - 5} more")
    else:
        console.print(f"\n[green]Unresolved Threads: ✓[/green]")

    console.print(f"\n[dim]Files: {data['files_count']} | Diff: {data['diff_lines']} lines[/dim]")
    console.print(f"[dim]Saved to: {out_dir}/prs/{pr_number}/[/dim]")


@cli.command()
@click.argument("owner_repo")
@click.argument("pr_number", type=int)
@click.option("--output-dir", "-o", help="Output directory (default: /tmp/pr-triage/OWNER__REPO/pr-NUMBER/context)")
def context(owner_repo: str, pr_number: int, output_dir: Optional[str]):
    """Fetch full PR context bundle for follow-through (threads, comments, diff)."""
    import shutil

    owner, repo = github.get_owner_repo(owner_repo)

    if output_dir:
        context_dir = Path(output_dir)
    else:
        safe_name = owner_repo.replace("/", "__")
        context_dir = Path(f"/tmp/pr-triage/{safe_name}/pr-{pr_number}/context")

    context_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[bold]Fetching PR context: {owner_repo} #{pr_number}[/bold]")
    console.print(f"[dim]Output: {context_dir}[/dim]\n")

    data = run_details(owner, repo, pr_number, context_dir.parent.parent)

    pr_dir = get_output_dir(owner_repo) / "prs" / str(pr_number)
    if pr_dir.exists():
        for f in pr_dir.iterdir():
            if f.is_file():
                shutil.copy2(f, context_dir / f.name)

    console.print(f"[green]Context saved to {context_dir}[/green]")


if __name__ == "__main__":
    cli()
