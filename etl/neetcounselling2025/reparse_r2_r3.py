#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = "neetcounselling2025"
sys.path.insert(0, str(ROOT))

from etl.neetcounselling2025.normalized_loader import (
    RESULT_PDFS,
    fetch_staged_rows,
    reconstruct_tables,
    table_kind,
    load_allotment_results,
    refresh_round_cutoffs,
)
from etl.neetcounselling2025.parse_allotment_raw import (
    parse_row_direct,
    match_institute,
    build_institution_cache,
)

TARGET_PDFS = {
    k: v for k, v in RESULT_PDFS.items() if v["round_key"] in ("R2", "R3")
}

DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    raise SystemExit("DATABASE_URL not set")


def delete_existing(engine, schema: str) -> None:
    with engine.begin() as conn:
        for pdf_name, meta in TARGET_PDFS.items():
            round_key = meta["round_key"]
            doc_id = conn.execute(
                text(f"SELECT document_id FROM {schema}.source_document WHERE file_name = :n"),
                {"n": pdf_name},
            ).scalar_one_or_none()
            if not doc_id:
                print(f"  WARNING: source_document not found for {pdf_name[:50]}")
                continue

            deleted_eff = conn.execute(
                text(f"DELETE FROM {schema}.allotment_result_effective WHERE source_document_id = :d"),
                {"d": doc_id},
            ).rowcount
            deleted_raw = conn.execute(
                text(f"DELETE FROM {schema}.allotment_raw_parsed WHERE source_pdf = :n"),
                {"n": pdf_name},
            ).rowcount
            print(f"  {round_key}: deleted {deleted_eff} effective rows, {deleted_raw} raw rows")


def reparse_raw(engine, schema: str) -> None:
    inst_cache = build_institution_cache(engine, schema)
    print(f"  Institution cache: {len(inst_cache['by_name'])} names, {len(inst_cache['by_alias'])} aliases")

    for pdf_name, meta in TARGET_PDFS.items():
        round_key = meta["round_key"]
        print(f"  Re-parsing {round_key}: {pdf_name[:60]}")

        with engine.begin() as conn:
            staged = conn.execute(
                text("SELECT id, row_data FROM neetcounselling2025.tabula_extracted_rows WHERE source_pdf = :p ORDER BY id"),
                {"p": pdf_name},
            ).fetchall()

        batch = []
        skipped = 0
        for raw in staged:
            extracted, flags = parse_row_direct(raw.row_data, pdf_name, round_key)
            if extracted is None:
                skipped += 1
                continue
            inst_id, method = match_institute(extracted["allotted_institute_cleaned"] or "", inst_cache)
            if not inst_id and extracted["allotted_institute_cleaned"]:
                flags.append("INSTITUTE_NOT_MATCHED")
            batch.append({
                "source_tabula_row_id": raw.id,
                "source_pdf": pdf_name,
                "round_key": round_key,
                **extracted,
                "institute_id": inst_id,
                "institute_match_method": method,
                "data_quality_flags": flags,
            })

        if batch:
            with engine.begin() as conn:
                conn.execute(
                    text("""
                        INSERT INTO neetcounselling2025.allotment_raw_parsed (
                          source_tabula_row_id, source_pdf, round_key,
                          serial_no, candidate_rank, candidate_name,
                          allotted_quota_raw, allotted_institute_raw, course_name_raw,
                          allotted_category_raw, candidate_category_raw, remarks_raw,
                          admitted_round, roll_number,
                          candidate_rank_cleaned, allotted_quota_cleaned, allotted_institute_cleaned,
                          course_name_cleaned, allotted_category_cleaned, candidate_category_cleaned,
                          remarks_cleaned, institute_id, institute_match_method, data_quality_flags
                        ) VALUES (
                          :source_tabula_row_id, :source_pdf, :round_key,
                          :serial_no, :candidate_rank, :candidate_name,
                          :allotted_quota_raw, :allotted_institute_raw, :course_name_raw,
                          :allotted_category_raw, :candidate_category_raw, :remarks_raw,
                          :admitted_round, :roll_number,
                          :candidate_rank_cleaned, :allotted_quota_cleaned, :allotted_institute_cleaned,
                          :course_name_cleaned, :allotted_category_cleaned, :candidate_category_cleaned,
                          :remarks_cleaned, :institute_id, :institute_match_method, :data_quality_flags
                        )
                    """),
                    batch,
                )
            print(f"    Inserted {len(batch)} raw rows, skipped {skipped}")


def reload_effective(engine, schema: str) -> None:
    from etl.neetcounselling2025.normalized_loader import (
        fetch_staged_rows, reconstruct_tables, table_kind,
        extract_institution_details, normalize_key, normalize_program,
        normalize_result_category, get_round_id, get_program_id,
        update_institution_if_better, _cached_dim_id,
    )

    dim_cache: dict[tuple, int] = {}
    for pdf_name, meta in TARGET_PDFS.items():
        round_key = meta["round_key"]
        print(f"  Loading {round_key} into allotment_result_effective ...")

        with engine.begin() as conn:
            doc_id = int(conn.execute(
                text(f"SELECT document_id FROM {schema}.source_document WHERE file_name = :n"),
                {"n": pdf_name},
            ).scalar_one())
            round_id = get_round_id(conn, schema, round_key)
            staged = fetch_staged_rows(conn, schema, pdf_name)

        tables = reconstruct_tables(staged)
        batch = []

        with engine.begin() as conn:
            for table_rows in tables:
                if table_kind(table_rows) != "result":
                    continue
                for row in table_rows:
                    rank_raw = row.get("Rank", "")
                    if not rank_raw.isdigit():
                        continue
                    if row.get("Allotted Quota", "").strip() in ("-", ""):
                        continue
                    institution = extract_institution_details(row["Allotted Institute"])
                    institution_id = _cached_dim_id(
                        conn, schema, dim_cache, "institution",
                        "institution_name_normalized", institution.normalized_name,
                        {
                            "mcc_institute_code": institution.mcc_institute_code,
                            "institution_name": institution.display_name,
                            "institution_name_normalized": institution.normalized_name,
                            "full_address": institution.full_address,
                            "state_name": institution.state_name,
                        },
                    )
                    update_institution_if_better(conn, schema, institution_id, institution)
                    alias_key = normalize_key(row["Allotted Institute"])
                    _cached_dim_id(
                        conn, schema, dim_cache, "institution_alias",
                        "alias_normalized", alias_key,
                        {
                            "institution_id": institution_id,
                            "alias_raw": row["Allotted Institute"],
                            "alias_normalized": alias_key,
                            "source_document_id": doc_id,
                        },
                    )
                    quota_id = _cached_dim_id(
                        conn, schema, dim_cache, "quota",
                        "quota_label", row["Allotted Quota"],
                        {"quota_label": row["Allotted Quota"], "quota_code": None},
                    )
                    allotted_code, allotted_pwd = normalize_result_category(row.get("Alloted Category", ""))
                    allotted_cat_id = _cached_dim_id(
                        conn, schema, dim_cache, "result_category",
                        "raw_label", row.get("Alloted Category", ""),
                        {
                            "raw_label": row.get("Alloted Category", ""),
                            "normalized_code": allotted_code,
                            "is_pwd": allotted_pwd,
                        },
                    )
                    cand_cat_raw = row.get("Candidate Category") or row.get("candidate Category", "")
                    cand_code, cand_pwd = normalize_result_category(cand_cat_raw)
                    cand_cat_id = _cached_dim_id(
                        conn, schema, dim_cache, "result_category",
                        "raw_label", cand_cat_raw,
                        {"raw_label": cand_cat_raw, "normalized_code": cand_code, "is_pwd": cand_pwd},
                    )
                    try:
                        program_id = get_program_id(conn, schema, normalize_program(row["Course"]))
                    except (ValueError, KeyError):
                        continue
                    batch.append({
                        "source_document_id": doc_id,
                        "round_id": round_id,
                        "candidate_rank": int(rank_raw),
                        "institution_id": institution_id,
                        "program_id": program_id,
                        "quota_id": quota_id,
                        "allotted_result_category_id": allotted_cat_id,
                        "candidate_result_category_id": cand_cat_id,
                        "remarks": row.get("Remarks") or None,
                        "mcc_institute_code": institution.mcc_institute_code,
                    })

            if batch:
                conn.execute(
                    text(f"""
                        INSERT INTO {schema}.allotment_result_effective (
                          source_document_id, round_id, candidate_rank, institution_id, program_id, quota_id,
                          allotted_result_category_id, candidate_result_category_id, remarks, mcc_institute_code
                        ) VALUES (
                          :source_document_id, :round_id, :candidate_rank, :institution_id, :program_id, :quota_id,
                          :allotted_result_category_id, :candidate_result_category_id, :remarks, :mcc_institute_code
                        ) ON CONFLICT DO NOTHING
                    """),
                    batch,
                )
                print(f"    Inserted {len(batch)} effective rows")


def main() -> int:
    engine = create_engine(DB_URL)

    print("Step 1: Deleting existing R2 + R3 data ...")
    delete_existing(engine, SCHEMA)

    print("\nStep 2: Re-parsing tabula rows into allotment_raw_parsed ...")
    reparse_raw(engine, SCHEMA)

    print("\nStep 3: Loading allotment_result_effective ...")
    reload_effective(engine, SCHEMA)

    print("\nStep 4: Refreshing quality flags ...")
    with engine.begin() as conn:
        conn.execute(text(f"SELECT {SCHEMA}.sp_refresh_allotment_quality()"))
    print("  Done.")

    print("\nStep 5: Refreshing round cutoffs ...")
    refresh_round_cutoffs(engine, SCHEMA)
    print("  Done.")

    print("\nVerifying row counts ...")
    with engine.begin() as conn:
        for pdf_name, meta in TARGET_PDFS.items():
            rk = meta["round_key"]
            doc_id = conn.execute(
                text(f"SELECT document_id FROM {SCHEMA}.source_document WHERE file_name = :n"),
                {"n": pdf_name},
            ).scalar_one()
            n = conn.execute(
                text(f"SELECT COUNT(*) FROM {SCHEMA}.allotment_result_effective WHERE source_document_id = :d"),
                {"d": doc_id},
            ).scalar()
            print(f"  {rk}: {n} rows in allotment_result_effective")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
