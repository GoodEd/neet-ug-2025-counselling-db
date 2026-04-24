#!/usr/bin/env python3
"""
Tabula-based table extraction and ingestion for NEET counselling PDFs.

Supports:
1) Sample extraction (first N rows) for quick verification.
2) Full extraction and ingestion into PostgreSQL staging table.

Designed to satisfy table-only extraction requirements.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List

import pandas as pd
import tabula
from sqlalchemy import create_engine, text


@dataclass
class ExtractConfig:
    pdf_path: Path
    pages: str = "all"
    mode: str = "lattice"  # lattice|stream
    multiple_tables: bool = True
    no_header: bool = False


REQUIRED_RESULT_HEADERS = {
    "rank",
    "allotted quota",
    "allotted institute",
    "course",
    "alloted category",
    "candidate category",
}


def normalize_col(col: str) -> str:
    return " ".join(str(col).replace("\n", " ").replace("\r", " ").split()).strip().lower()


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_tables(cfg: ExtractConfig) -> List[pd.DataFrame]:
    if not cfg.pdf_path.exists():
        raise FileNotFoundError(f"PDF not found: {cfg.pdf_path}")

    # tabula-py uses Java underneath; choose flavor explicitly.
    kwargs = {
        "input_path": str(cfg.pdf_path),
        "pages": cfg.pages,
        "multiple_tables": cfg.multiple_tables,
        "guess": True,
    }

    if cfg.mode == "lattice":
        kwargs["lattice"] = True
        kwargs["stream"] = False
    elif cfg.mode == "stream":
        kwargs["stream"] = True
        kwargs["lattice"] = False
    else:
        raise ValueError("mode must be 'lattice' or 'stream'")

    if cfg.no_header:
        kwargs["pandas_options"] = {"header": None}

    tables = tabula.read_pdf(**kwargs)

    # Table-only rule: extraction must produce actual tabular rows.
    valid = [df for df in tables if not df.empty and len(df.columns) > 1 and df.dropna(how="all").shape[0] > 0]
    return valid


def enforce_result_header_gate(df: pd.DataFrame) -> bool:
    cols = {normalize_col(c) for c in df.columns}
    return REQUIRED_RESULT_HEADERS.issubset(cols)


def add_common_metadata(df: pd.DataFrame, pdf_path: Path, table_index: int) -> pd.DataFrame:
    out = df.copy()
    out["_source_pdf"] = pdf_path.name
    out["_source_pdf_path"] = str(pdf_path)
    out["_source_pdf_sha256"] = file_sha256(pdf_path)
    out["_table_index"] = table_index
    return out


def write_sample_json(tables: Iterable[pd.DataFrame], out_file: Path, sample_rows: int, pdf_path: Path) -> None:
    payload = []
    for i, df in enumerate(tables):
        sample = add_common_metadata(df.head(sample_rows), pdf_path, i)
        payload.append(
            {
                "table_index": i,
                "columns": [str(c) for c in sample.columns],
                "row_count_sample": int(sample.shape[0]),
                "rows": sample.fillna("").to_dict(orient="records"),
            }
        )
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def ensure_staging_schema(engine, schema: str) -> None:
    ddl = f"""
    create schema if not exists {schema};

    create table if not exists {schema}.tabula_extracted_rows (
        id bigserial primary key,
        source_pdf text not null,
        source_pdf_path text not null,
        source_pdf_sha256 text not null,
        table_index int not null,
        extracted_at timestamptz not null default now(),
        row_data jsonb not null
    );

    create table if not exists {schema}.tabula_ingestion_windows (
        source_pdf text not null,
        source_pdf_sha256 text not null,
        page_start int not null,
        page_end int not null,
        completed_at timestamptz not null default now(),
        primary key (source_pdf_sha256, page_start, page_end)
    );
    """
    with engine.begin() as conn:
        conn.execute(text(ddl))


def get_completed_windows(engine, schema: str, pdf_path: Path) -> set[tuple[int, int]]:
    ensure_staging_schema(engine, schema)
    sha = file_sha256(pdf_path)
    stmt = text(
        f"""
        select page_start, page_end
        from {schema}.tabula_ingestion_windows
        where source_pdf_sha256 = :source_pdf_sha256
        order by page_start, page_end
        """
    )
    with engine.begin() as conn:
        rows = conn.execute(stmt, {"source_pdf_sha256": sha}).fetchall()
    return {(int(row.page_start), int(row.page_end)) for row in rows}


def _chunked(items: List[dict], size: int) -> Iterable[List[dict]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def ingest_tables(
    engine,
    schema: str,
    tables: Iterable[pd.DataFrame],
    pdf_path: Path,
    page_start: int | None = None,
    page_end: int | None = None,
) -> int:
    ensure_staging_schema(engine, schema)
    rows_inserted = 0
    pdf_sha256 = file_sha256(pdf_path)
    insert_stmt = text(
        f"""
        insert into {schema}.tabula_extracted_rows (
          source_pdf, source_pdf_path, source_pdf_sha256, table_index, row_data
        ) values (
          :source_pdf, :source_pdf_path, :source_pdf_sha256, :table_index, cast(:row_data as jsonb)
        )
        """
    )
    manifest_stmt = text(
        f"""
        insert into {schema}.tabula_ingestion_windows (
          source_pdf, source_pdf_sha256, page_start, page_end
        ) values (
          :source_pdf, :source_pdf_sha256, :page_start, :page_end
        )
        on conflict (source_pdf_sha256, page_start, page_end) do nothing
        """
    )

    with engine.begin() as conn:
        for i, df in enumerate(tables):
            meta_df = add_common_metadata(df, pdf_path, i)
            records = meta_df.fillna("").to_dict(orient="records")
            payload = [
                {
                    "source_pdf": rec.get("_source_pdf", pdf_path.name),
                    "source_pdf_path": rec.get("_source_pdf_path", str(pdf_path)),
                    "source_pdf_sha256": rec.get("_source_pdf_sha256", pdf_sha256),
                    "table_index": int(rec.get("_table_index", i)),
                    "row_data": json.dumps(rec, ensure_ascii=False),
                }
                for rec in records
            ]
            for chunk in _chunked(payload, 5000):
                conn.execute(insert_stmt, chunk)
                rows_inserted += len(chunk)
        if page_start is not None and page_end is not None:
            conn.execute(
                manifest_stmt,
                {
                    "source_pdf": pdf_path.name,
                    "source_pdf_sha256": pdf_sha256,
                    "page_start": page_start,
                    "page_end": page_end,
                },
            )
    return rows_inserted


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Extract tables from a PDF using Tabula and ingest to Postgres")
    p.add_argument("--pdf", required=True, help="Absolute path to PDF")
    p.add_argument("--pages", default="all", help="Tabula pages expression (default: all)")
    p.add_argument("--mode", choices=["lattice", "stream"], default="lattice", help="Tabula mode")
    p.add_argument("--sample", action="store_true", help="Write sample rows to JSON and exit")
    p.add_argument("--sample-rows", type=int, default=15, help="Rows per table in sample mode")
    p.add_argument("--sample-out", default=".sisyphus/extracts/tabula_sample.json", help="Sample output JSON path")
    p.add_argument("--require-result-headers", action="store_true", help="Enforce final-result header gate")
    p.add_argument("--ingest", action="store_true", help="Ingest full extracted tables into Postgres staging")
    p.add_argument("--db-url", default=os.getenv("DATABASE_URL"), help="SQLAlchemy DB URL")
    p.add_argument("--schema", default="neetcounselling2025", help="Target schema (default neetcounselling2025)")
    p.add_argument("--page-start", type=int, help="Chunk window start page for resume tracking")
    p.add_argument("--page-end", type=int, help="Chunk window end page for resume tracking")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    pdf_path = Path(args.pdf).expanduser().resolve()
    cfg = ExtractConfig(pdf_path=pdf_path, pages=args.pages, mode=args.mode)

    tables = extract_tables(cfg)
    if not tables:
        raise RuntimeError("Tabula extracted zero valid tables. Table-only rule blocked ingestion.")

    if args.require_result_headers:
        if not any(enforce_result_header_gate(df) for df in tables):
            raise RuntimeError("Required final-result headers not found in extracted tables.")

    if args.sample:
        out = Path(args.sample_out).expanduser().resolve()
        write_sample_json(tables, out, args.sample_rows, pdf_path)
        print(f"Sample extracted: {out}")

    if args.ingest:
        if not args.db_url:
            raise RuntimeError("--db-url or DATABASE_URL is required for --ingest")
        engine = create_engine(args.db_url)
        inserted = ingest_tables(
            engine,
            args.schema,
            tables,
            pdf_path,
            page_start=args.page_start,
            page_end=args.page_end,
        )
        print(f"Ingested rows: {inserted}")

    if not args.sample and not args.ingest:
        print(f"Valid tables extracted: {len(tables)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
