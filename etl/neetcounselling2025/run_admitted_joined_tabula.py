#!/usr/bin/env python3
"""
Convenience runner for the specific admitted-joined PDF requested by user.

Usage:
  # sample extraction
  .venv/bin/python etl/neetcounselling2025/run_admitted_joined_tabula.py --sample

  # full extraction + ingest
  DATABASE_URL='postgresql+psycopg2://learner:***@neetprep-staging.cvvtorjqg7t7.ap-south-1.rds.amazonaws.com/learner_development' \
  .venv/bin/python etl/neetcounselling2025/run_admitted_joined_tabula.py --ingest
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


PDF_NAME = "ADMITTED JOINED CANDIDATES LIST UPTO ROUND 3 UG COUNSELLING 2025 - 202511031508909973.pdf"


def get_pdf_page_count(pdf_path: Path) -> int:
    cmd = ["pdfinfo", str(pdf_path)]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True)
    for line in out.stdout.splitlines():
        if line.lower().startswith("pages:"):
            return int(line.split(":", 1)[1].strip())
    raise RuntimeError("Unable to determine page count from pdfinfo output")


def build_page_windows(total_pages: int, chunk_size: int) -> list[tuple[int, int]]:
    if total_pages <= 0:
        raise ValueError("total_pages must be > 0")
    if chunk_size <= 0:
        raise ValueError("chunk_size must be > 0")

    windows: list[tuple[int, int]] = []
    start = 1
    while start <= total_pages:
        end = min(start + chunk_size - 1, total_pages)
        windows.append((start, end))
        start = end + 1
    return windows


def filter_completed_windows(
    windows: list[tuple[int, int]], completed_windows: set[tuple[int, int]]
) -> list[tuple[int, int]]:
    return [window for window in windows if window not in completed_windows]


def ensure_repo_root_on_sys_path(root: Path) -> None:
    root_str = str(root)
    if root_str not in sys.path:
        sys.path.insert(0, root_str)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run Tabula extraction for admitted-joined PDF")
    p.add_argument("--sample", action="store_true", help="Generate sample JSON")
    p.add_argument("--ingest", action="store_true", help="Run full ingestion into DB")
    p.add_argument("--mode", choices=["lattice", "stream"], default="lattice")
    p.add_argument("--pages", default="all")
    p.add_argument("--schema", default="neetcounselling2025")
    p.add_argument("--sample-out", default=".sisyphus/extracts/tabula_sample_admitted_joined.json")
    p.add_argument("--chunked", action="store_true", help="Run ingestion in page windows")
    p.add_argument("--chunk-size", type=int, default=10, help="Pages per window in chunked mode")
    p.add_argument("--db-url", default=os.getenv("DATABASE_URL"), help="DB URL for ingest mode")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[2]
    pdf_path = root / PDF_NAME
    if not pdf_path.exists():
        raise FileNotFoundError(f"Missing target PDF: {pdf_path}")

    runner = root / "etl" / "neetcounselling2025" / "tabula_extract_ingest.py"
    python_bin = str(root / ".venv" / "bin" / "python")

    if args.chunked and args.ingest:
        total_pages = get_pdf_page_count(pdf_path)
        windows = build_page_windows(total_pages=total_pages, chunk_size=args.chunk_size)
        completed_windows: set[tuple[int, int]] = set()
        if args.db_url:
            ensure_repo_root_on_sys_path(root)
            from sqlalchemy import create_engine

            from etl.neetcounselling2025.tabula_extract_ingest import get_completed_windows

            engine = create_engine(args.db_url)
            completed_windows = get_completed_windows(engine, args.schema, pdf_path)
        pending_windows = filter_completed_windows(windows, completed_windows)
        if completed_windows:
            print(f"Skipping {len(completed_windows)} previously completed chunk(s)")
        if not pending_windows:
            print("No pending chunks remain")
            return 0
        for start, end in pending_windows:
            cmd = [
                python_bin,
                str(runner),
                "--pdf",
                str(pdf_path),
                "--mode",
                args.mode,
                "--pages",
                f"{start}-{end}",
                "--schema",
                args.schema,
                "--ingest",
                "--page-start",
                str(start),
                "--page-end",
                str(end),
            ]
            if args.db_url:
                cmd.extend(["--db-url", args.db_url])
            print(f"Running chunk pages {start}-{end}")
            _ = subprocess.run(cmd, check=True)
    else:
        cmd = [
            python_bin,
            str(runner),
            "--pdf",
            str(pdf_path),
            "--mode",
            args.mode,
            "--pages",
            args.pages,
            "--schema",
            args.schema,
        ]

        if args.sample:
            cmd.extend(["--sample", "--sample-out", args.sample_out])

        if args.ingest:
            cmd.append("--ingest")
            if args.db_url:
                cmd.extend(["--db-url", args.db_url])

        if not args.sample and not args.ingest:
            cmd.append("--sample")
            cmd.extend(["--sample-out", args.sample_out])

        _ = subprocess.run(cmd, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
