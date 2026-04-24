#!/usr/bin/env python3
"""Merge duplicate institutions where one has MCC and another has alias with same MCC."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = "neetcounselling2025"
sys.path.insert(0, str(ROOT))

DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    raise SystemExit("DATABASE_URL not set")


def find_duplicate_pairs(engine, schema: str) -> list[dict]:
    with engine.begin() as conn:
        rows = conn.execute(
            text(
                f"""
                select i1.institution_id as canonical_id,
                       i1.institution_name as canonical_name,
                       i1.mcc_institute_code as canonical_mcc,
                       i2.institution_id as duplicate_id,
                       i2.institution_name as duplicate_name
                from {schema}.institution i1
                join {schema}.institution i2 on i1.institution_id <> i2.institution_id
                where i1.mcc_institute_code is not null
                  and i2.mcc_institute_code is null
                  and exists (
                    select 1 from {schema}.institution_alias ia
                    where ia.institution_id = i2.institution_id
                      and ia.alias_raw ~ '\\(\\d{{6}}\\)'
                      and (regexp_match(ia.alias_raw, '\\((\\d{{6}})\\)'))[1]::int = i1.mcc_institute_code
                  )
                order by i1.mcc_institute_code
                """
            )
        ).fetchall()
    return [
        {
            "canonical_id": row.canonical_id,
            "canonical_name": row.canonical_name,
            "canonical_mcc": row.canonical_mcc,
            "duplicate_id": row.duplicate_id,
            "duplicate_name": row.duplicate_name,
        }
        for row in rows
    ]


def merge_institution_pair(conn, schema: str, pair: dict) -> None:
    canonical_id = pair["canonical_id"]
    duplicate_id = pair["duplicate_id"]

    conn.execute(
        text(
            f"""
            update {schema}.allotment_result_effective
            set institution_id = :canonical_id
            where institution_id = :duplicate_id
            """
        ),
        {"canonical_id": canonical_id, "duplicate_id": duplicate_id},
    )

    conn.execute(
        text(
            f"""
            delete from {schema}.round_cutoff
            where institution_id = :duplicate_id
              and exists (
                select 1 from {schema}.round_cutoff rc2
                where rc2.institution_id = :canonical_id
                  and rc2.round_id = {schema}.round_cutoff.round_id
                  and rc2.program_id = {schema}.round_cutoff.program_id
                  and rc2.quota_id = {schema}.round_cutoff.quota_id
                  and rc2.allotted_result_category_id = {schema}.round_cutoff.allotted_result_category_id
                  and rc2.candidate_result_category_id = {schema}.round_cutoff.candidate_result_category_id
              )
            """
        ),
        {"canonical_id": canonical_id, "duplicate_id": duplicate_id},
    )

    conn.execute(
        text(
            f"""
            update {schema}.round_cutoff
            set institution_id = :canonical_id
            where institution_id = :duplicate_id
            """
        ),
        {"canonical_id": canonical_id, "duplicate_id": duplicate_id},
    )

    conn.execute(
        text(
            f"""
            update {schema}.institution_alias
            set institution_id = :canonical_id
            where institution_id = :duplicate_id
            """
        ),
        {"canonical_id": canonical_id, "duplicate_id": duplicate_id},
    )

    conn.execute(
        text(
            f"""
            update {schema}.allotment_raw_parsed
            set institute_id = :canonical_id
            where institute_id = :duplicate_id
            """
        ),
        {"canonical_id": canonical_id, "duplicate_id": duplicate_id},
    )

    conn.execute(
        text(
            f"""
            update {schema}.final_seat_matrix_row sm1
            set total_seats = sm1.total_seats + sm2.total_seats
            from {schema}.final_seat_matrix_row sm2
            where sm1.institution_id = :canonical_id
              and sm2.institution_id = :duplicate_id
              and sm1.source_document_id = sm2.source_document_id
              and sm1.program_id = sm2.program_id
              and sm1.quota_id = sm2.quota_id
              and sm1.seat_category_id = sm2.seat_category_id
            """
        ),
        {"canonical_id": canonical_id, "duplicate_id": duplicate_id},
    )

    conn.execute(
        text(
            f"""
            delete from {schema}.final_seat_matrix_row
            where institution_id = :duplicate_id
            """
        ),
        {"duplicate_id": duplicate_id},
    )

    conn.execute(
        text(f"delete from {schema}.institution where institution_id = :duplicate_id"),
        {"duplicate_id": duplicate_id},
    )


def main() -> int:
    engine = create_engine(DB_URL)
    pairs = find_duplicate_pairs(engine, SCHEMA)
    print(f"Found {len(pairs)} duplicate institution pairs")

    merged = 0
    with engine.begin() as conn:
        for pair in pairs:
            print(f"  Merging '{pair['duplicate_name']}' -> '{pair['canonical_name']}' (MCC {pair['canonical_mcc']})")
            merge_institution_pair(conn, SCHEMA, pair)
            merged += 1

    print(f"Merged {merged} pairs")

    if merged > 0:
        print("Running quality refresh...")
        with engine.begin() as conn:
            conn.execute(text(f"select {SCHEMA}.sp_refresh_allotment_quality()"))
        print("Done.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
