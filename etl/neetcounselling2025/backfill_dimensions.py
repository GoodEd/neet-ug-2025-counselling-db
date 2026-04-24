#!/usr/bin/env python3
"""Backfill existing dimension tables with corrected normalization and institution enrichment."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = "neetcounselling2025"
sys.path.insert(0, str(ROOT))

from etl.neetcounselling2025.normalized_loader import (
    normalize_result_category,
    normalize_seat_category,
)

DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    raise SystemExit("DATABASE_URL not set")


def backfill_result_categories(engine, schema: str) -> None:
    with engine.begin() as conn:
        rows = conn.execute(
            text(f"select result_category_id, raw_label from {schema}.result_category")
        ).fetchall()
    updates = []
    for row in rows:
        code, is_pwd = normalize_result_category(row.raw_label)
        updates.append({
            "result_category_id": row.result_category_id,
            "normalized_code": code,
            "is_pwd": is_pwd,
        })
    with engine.begin() as conn:
        conn.execute(
            text(
                f"""
                update {schema}.result_category
                set normalized_code = :normalized_code, is_pwd = :is_pwd
                where result_category_id = :result_category_id
                """
            ),
            updates,
        )
    print(f"  Updated {len(updates)} result_category rows")


def backfill_seat_categories(engine, schema: str) -> None:
    with engine.begin() as conn:
        rows = conn.execute(
            text(f"select seat_category_id, raw_label from {schema}.seat_category")
        ).fetchall()
    updates = []
    for row in rows:
        code, is_pwd = normalize_seat_category(row.raw_label)
        updates.append({
            "seat_category_id": row.seat_category_id,
            "normalized_code": code,
            "is_pwd": is_pwd,
        })
    with engine.begin() as conn:
        conn.execute(
            text(
                f"""
                update {schema}.seat_category
                set normalized_code = :normalized_code, is_pwd = :is_pwd
                where seat_category_id = :seat_category_id
                """
            ),
            updates,
        )
    print(f"  Updated {len(updates)} seat_category rows")


def backfill_institution_mcc_from_aliases(engine, schema: str) -> None:
    with engine.begin() as conn:
        rows = conn.execute(
            text(
                f"""
                select i.institution_id,
                       (regexp_match(ia.alias_raw, '\\((\\d{{6}})\\)'))[1]::int as mcc
                from {schema}.institution i
                join {schema}.institution_alias ia on i.institution_id = ia.institution_id
                where i.mcc_institute_code is null
                  and ia.alias_raw ~ '\\(\\d{{6}}\\)'
                """
            )
        ).fetchall()

    existing_mcc = set()
    with engine.begin() as conn:
        for row in conn.execute(text(f"select mcc_institute_code from {schema}.institution where mcc_institute_code is not null")).fetchall():
            existing_mcc.add(row[0])

    updates = []
    seen = set()
    for row in rows:
        if row.mcc in existing_mcc or row.mcc in seen:
            continue
        updates.append({"institution_id": row.institution_id, "mcc": row.mcc})
        seen.add(row.mcc)

    if updates:
        with engine.begin() as conn:
            conn.execute(
                text(f"update {schema}.institution set mcc_institute_code = :mcc where institution_id = :institution_id"),
                updates,
            )
    print(f"  Backfilled institution MCC codes: {len(updates)} rows")


def refresh_allotment_mcc(engine, schema: str) -> None:
    with engine.begin() as conn:
        result = conn.execute(
            text(
                f"""
                update {schema}.allotment_result_effective ar
                set mcc_institute_code = i.mcc_institute_code
                from {schema}.institution i
                where ar.institution_id = i.institution_id
                  and ar.mcc_institute_code is null
                  and i.mcc_institute_code is not null
                """
            )
        )
        print(f"  Refreshed allotment MCC codes: {result.rowcount} rows")


def main() -> int:
    engine = create_engine(DB_URL)
    print("Backfilling result_category...")
    backfill_result_categories(engine, SCHEMA)
    print("Backfilling seat_category...")
    backfill_seat_categories(engine, SCHEMA)
    print("Backfilling institution MCC from aliases...")
    backfill_institution_mcc_from_aliases(engine, SCHEMA)
    print("Refreshing allotment MCC codes...")
    refresh_allotment_mcc(engine, SCHEMA)
    print("Running quality refresh...")
    with engine.begin() as conn:
        conn.execute(text(f"select {SCHEMA}.sp_refresh_allotment_quality()"))
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
