#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import time


def run_collect(
    collect_script: pathlib.Path,
    manifest_path: pathlib.Path,
    output_dir: pathlib.Path | None,
    final_only: bool,
    attempts: int | None,
    retry_429: int,
    retry_delay_sec: float,
) -> subprocess.CompletedProcess[str]:
    """Run the collector once so readiness checks always use fresh artifact state."""

    cmd = [sys.executable, str(collect_script), str(manifest_path)]
    if output_dir is not None:
        cmd.extend(["--output-dir", str(output_dir)])
    if final_only:
        cmd.append("--final-only")
    if attempts is not None:
        cmd.extend(["--attempts", str(attempts)])
    cmd.extend(
        [
            "--retry-429",
            str(retry_429),
            "--retry-delay-sec",
            str(retry_delay_sec),
        ]
    )
    return subprocess.run(cmd, text=True, capture_output=True, check=False)


def load_index(index_path: pathlib.Path) -> dict:
    """Read the latest artifact index produced by the collector."""

    return json.loads(index_path.read_text())


def task_ready(task: dict, mode: str) -> bool:
    """Return whether a task is ready under the selected fan-in mode."""

    if mode == "full":
        return bool(task.get("usable_for_fanin_full", task.get("final_diff_available", False)))
    return bool(
        task.get(
            "usable_for_fanin_partial",
            task.get("final_diff_available", False) or bool(task.get("attempts_saved", [])),
        )
    )


def summarize(index: dict, mode: str) -> tuple[int, int, list[str]]:
    """Compute readiness counts and one-line per-task summaries."""

    tasks = index.get("tasks", [])
    ready = 0
    lines: list[str] = []
    for task in tasks:
        is_ready = task_ready(task, mode)
        if is_ready:
            ready += 1
        attempts_saved = task.get("attempts_saved", [])
        lines.append(
            f"- {task.get('name', task.get('task_id'))}: "
            f"{'ready' if is_ready else 'waiting'} "
            f"(final={task.get('final_diff_available', False)}, attempts={attempts_saved})"
        )
    return ready, len(tasks), lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Poll a fanout manifest until its artifact bundle is ready for fan-in."
    )
    parser.add_argument("manifest", help="Path to fanout-manifest.json.")
    parser.add_argument(
        "--mode",
        choices=["partial", "full"],
        default="partial",
        help="Wait for partial fan-in readiness or full final-diff readiness.",
    )
    parser.add_argument(
        "--interval-sec",
        type=float,
        default=30.0,
        help="Seconds to wait between polling attempts.",
    )
    parser.add_argument(
        "--timeout-sec",
        type=float,
        default=3600.0,
        help="Maximum total wait time before giving up.",
    )
    parser.add_argument(
        "--output-dir",
        help="Artifact directory. Defaults to <manifest-dir>/cloud-artifacts.",
    )
    parser.add_argument(
        "--final-only",
        action="store_true",
        help="Only collect final diffs while polling.",
    )
    parser.add_argument(
        "--attempts",
        type=int,
        help="Override attempt count instead of using the manifest value.",
    )
    parser.add_argument(
        "--retry-429",
        type=int,
        default=3,
        help="How many times to retry a cloud call that returns HTTP 429.",
    )
    parser.add_argument(
        "--retry-delay-sec",
        type=float,
        default=2.0,
        help="Initial delay before retrying a rate-limited cloud call.",
    )
    args = parser.parse_args()

    script_dir = pathlib.Path(__file__).resolve().parent
    collect_script = script_dir / "collect-cloud-artifacts.py"
    manifest_path = pathlib.Path(args.manifest).expanduser().resolve()
    output_dir = pathlib.Path(args.output_dir).expanduser().resolve() if args.output_dir else None
    index_path = (output_dir or manifest_path.parent / "cloud-artifacts") / "artifact-index.json"

    start = time.time()
    attempt = 0
    while True:
        attempt += 1
        result = run_collect(
            collect_script=collect_script,
            manifest_path=manifest_path,
            output_dir=output_dir,
            final_only=args.final_only,
            attempts=args.attempts,
            retry_429=args.retry_429,
            retry_delay_sec=args.retry_delay_sec,
        )
        if result.returncode != 0:
            sys.stderr.write(result.stdout)
            sys.stderr.write(result.stderr)
            return result.returncode
        if not index_path.exists():
            sys.stderr.write(f"artifact index missing after collect run: {index_path}\n")
            return 1

        index = load_index(index_path)
        ready, total, lines = summarize(index, args.mode)
        elapsed = time.time() - start
        print(
            f"[wait-for-fanin] attempt={attempt} mode={args.mode} "
            f"ready={ready}/{total} elapsed={elapsed:.1f}s"
        )
        for line in lines:
            print(line)
        print(f"artifact index: {index_path}")

        if total > 0 and ready == total:
            print("[wait-for-fanin] ready for fan-in")
            return 0

        if elapsed >= args.timeout_sec:
            print("[wait-for-fanin] timed out before the wave became ready")
            return 2

        time.sleep(args.interval_sec)


if __name__ == "__main__":
    raise SystemExit(main())
