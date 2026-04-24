#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = "neetcounselling2025"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from etl.neetcounselling2025.normalized_loader import (
    RESULT_PDFS,
    METADATA_KEYS,
    normalize_spaces,
    normalize_key,
)


def clean_field(value: Any) -> str:
    if value is None:
        return ""
    cleaned = normalize_spaces(str(value))
    if cleaned == "-":
        return ""
    return cleaned


def clean_rank(value: str) -> int | None:
    cleaned = re.sub(r"[,\s]", "", value)
    if cleaned.isdigit():
        return int(cleaned)
    return None


def build_institution_cache(engine, schema: str) -> dict:
    cache = {
        "by_name": {},
        "by_alias": {},
        "all_names": [],
        "name_to_id": {},
    }
    with engine.begin() as conn:
        rows = conn.execute(text(f"SELECT institution_id, institution_name_normalized FROM {schema}.institution")).fetchall()
        for r in rows:
            cache["by_name"][r.institution_name_normalized] = r.institution_id
            cache["all_names"].append(r.institution_name_normalized)
            cache["name_to_id"][r.institution_name_normalized] = r.institution_id

        rows = conn.execute(text(f"SELECT institution_id, alias_normalized FROM {schema}.institution_alias")).fetchall()
        for r in rows:
            cache["by_alias"][r.alias_normalized] = r.institution_id

    return cache


def match_institute(institute_raw: str, cache: dict) -> tuple[int | None, str]:
    if not institute_raw or not institute_raw.strip():
        return None, ""

    normalized = normalize_key(institute_raw)

    if normalized in cache["by_name"]:
        return cache["by_name"][normalized], "exact_name"

    if normalized in cache["by_alias"]:
        return cache["by_alias"][normalized], "exact_alias"

    for name in cache["all_names"]:
        if normalized in name or name in normalized:
            if len(name) > 10 and len(normalized) > 10:
                return cache["name_to_id"][name], "fuzzy_contains"

    return None, ""


def parse_row_direct(row_data: dict[str, Any], pdf_name: str, round_key: str = "") -> tuple[dict[str, Any] | None, list[str]]:
    flags: list[str] = []

    values = []
    for i in range(20):
        key = str(i)
        if key in row_data and key not in METADATA_KEYS:
            values.append(clean_field(row_data[key]))

    if not values:
        return None, ["NO_DATA"]

    first_val = normalize_key(values[0]) if values else ""
    header_keywords = {"rank", "allotted", "quota", "institute", "course", "category", "remarks", "name", "air", "s.no", "serial", "abbrevation", "description"}
    if any(kw in first_val for kw in header_keywords):
        return None, ["HEADER_ROW"]

    val_count = len(values)

    if round_key == "R2" and val_count >= 13:
        serial_no = values[0]
        rank_raw = values[1]
        quota = values[6]
        institute = values[7]
        course = values[8]
        allotted_cat = values[9]
        candidate_cat = values[10]
        remarks = values[12]

        if not quota:
            return None, ["R1_RETAINED"]

    elif round_key == "R3" and val_count >= 15:
        serial_no = ""
        rank_raw = values[0]
        quota = values[9]
        institute = values[10]
        course = values[11]
        allotted_cat = values[12]
        candidate_cat = values[13]
        remarks = values[15] if val_count > 15 else ""

        if not quota:
            return None, ["R2_RETAINED"]

    elif val_count == 8:
        serial_no = values[0]
        rank_raw = values[1]
        quota = values[2]
        institute = values[3]
        course = values[4]
        allotted_cat = values[5]
        candidate_cat = values[6]
        remarks = values[7]

    elif val_count >= 16:
        serial_no = values[0]
        rank_raw = ""
        quota = values[1]
        institute = values[2]
        course = values[3]
        allotted_cat = ""
        candidate_cat = ""
        remarks = values[4]
        flags.append("ROUND3_STATUS_ONLY")

    elif val_count >= 13:
        serial_no = values[0]
        rank_raw = values[1]
        quota = values[6]
        institute = values[7]
        course = values[8]
        allotted_cat = values[9]
        candidate_cat = values[10]
        remarks = values[12]

        if not quota:
            return None, ["PREV_ROUND_RETAINED"]

    elif val_count >= 9:
        serial_no = values[0]
        rank_raw = values[1] if values[1].isdigit() else ""
        quota = values[2] if rank_raw else values[1]
        institute = values[3] if rank_raw else values[2]
        course = values[4] if rank_raw else values[3]
        remarks = values[5] if rank_raw else values[4]
        allotted_cat = ""
        candidate_cat = ""

        if not rank_raw:
            flags.append("NO_RANK")

    else:
        return None, ["UNSUPPORTED_FORMAT"]

    rank_cleaned = clean_rank(rank_raw)

    if not institute:
        flags.append("MISSING_INSTITUTE")
    if not quota:
        flags.append("MISSING_QUOTA")
    if not allotted_cat and not candidate_cat:
        flags.append("MISSING_CATEGORY")
    if rank_raw and not rank_cleaned:
        flags.append("INVALID_RANK")

    return {
        "serial_no": serial_no or None,
        "candidate_rank": rank_raw or None,
        "candidate_rank_cleaned": rank_cleaned,
        "candidate_name": None,
        "allotted_quota_raw": quota or None,
        "allotted_quota_cleaned": quota or None,
        "allotted_institute_raw": institute or None,
        "allotted_institute_cleaned": institute or None,
        "course_name_raw": course or None,
        "course_name_cleaned": course or None,
        "allotted_category_raw": allotted_cat or None,
        "allotted_category_cleaned": allotted_cat or None,
        "candidate_category_raw": candidate_cat or None,
        "candidate_category_cleaned": candidate_cat or None,
        "remarks_raw": remarks or None,
        "remarks_cleaned": remarks or None,
        "admitted_round": None,
        "roll_number": None,
    }, flags


def main() -> int:
    import os
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("Error: DATABASE_URL environment variable not set", file=sys.stderr)
        return 1
    engine = create_engine(db_url)

    print("Building institution cache...")
    inst_cache = build_institution_cache(engine, SCHEMA)
    print(f"  Cached {len(inst_cache['by_name'])} institutions and {len(inst_cache['by_alias'])} aliases")

    print("Parsing raw allotment rows into allotment_raw_parsed...")

    total_inserted = 0
    total_skipped = 0

    for pdf_name in RESULT_PDFS:
        round_key = RESULT_PDFS[pdf_name]["round_key"]
        print(f"  Processing {pdf_name[:60]} ...")

        with engine.begin() as conn:
            staged = conn.execute(
                text("""
                    SELECT id, row_data
                    FROM neetcounselling2025.tabula_extracted_rows
                    WHERE source_pdf = :pdf_name
                    ORDER BY id
                """),
                {"pdf_name": pdf_name},
            ).fetchall()

        batch: list[dict] = []
        skipped = 0
        for raw in staged:
            extracted, flags = parse_row_direct(raw.row_data, pdf_name, round_key)
            if extracted is None:
                skipped += 1
                continue

            institute_id, match_method = match_institute(extracted["allotted_institute_cleaned"] or "", inst_cache)

            if not institute_id and extracted["allotted_institute_cleaned"]:
                flags.append("INSTITUTE_NOT_MATCHED")

            batch.append({
                "source_tabula_row_id": raw.id,
                "source_pdf": pdf_name,
                "round_key": round_key,
                **extracted,
                "institute_id": institute_id,
                "institute_match_method": match_method,
                "data_quality_flags": flags,
            })

        BATCH_SIZE = 2000
        if batch:
            inserted = 0
            for i in range(0, len(batch), BATCH_SIZE):
                chunk = batch[i:i + BATCH_SIZE]
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
                              course_name_cleaned, allotted_category_cleaned, candidate_category_cleaned, remarks_cleaned,
                              institute_id, institute_match_method, data_quality_flags
                            ) VALUES (
                              :source_tabula_row_id, :source_pdf, :round_key,
                              :serial_no, :candidate_rank, :candidate_name,
                              :allotted_quota_raw, :allotted_institute_raw, :course_name_raw,
                              :allotted_category_raw, :candidate_category_raw, :remarks_raw,
                              :admitted_round, :roll_number,
                              :candidate_rank_cleaned, :allotted_quota_cleaned, :allotted_institute_cleaned,
                              :course_name_cleaned, :allotted_category_cleaned, :candidate_category_cleaned, :remarks_cleaned,
                              :institute_id, :institute_match_method, :data_quality_flags
                            )
                        """),
                        chunk,
                    )
                inserted += len(chunk)
            total_inserted += inserted
            total_skipped += skipped
            print(f"    Inserted {inserted} rows, skipped {skipped}")

    print(f"\\nDone. Total inserted: {total_inserted}, total skipped: {total_skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
