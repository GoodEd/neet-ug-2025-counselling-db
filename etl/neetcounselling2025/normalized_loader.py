#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine, text


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = "neetcounselling2025"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from etl.neetcounselling2025.tabula_extract_ingest import ExtractConfig, extract_tables, ingest_tables

RESULT_PDFS: dict[str, dict[str, str]] = {
    "Final Result for Round-I of NEET UG Counselling 2025 - 20250813289226788.pdf": {"doc_type": "final_allotment_result", "round_key": "R1"},
    "Final Result for Round 2 of UG Counselling 2025 - 202509182057444522.pdf": {"doc_type": "final_allotment_result", "round_key": "R2"},
    "Final Allotment Result for Round 3 of UG Counselling 2025 - 202510231856675154.pdf": {"doc_type": "final_allotment_result", "round_key": "R3"},
    "Final Allotment Result for Stray Vacacy Round UG 2025 - 2025111596488171.pdf": {"doc_type": "final_allotment_result", "round_key": "STRAY"},
    "Final Result for Special Stray Round of UG counselling 2025 - 202512231822103663.pdf": {"doc_type": "final_allotment_result", "round_key": "SPECIAL_STRAY"},
    "Final Result of UG Counselling Round 5 for BDS ⁄ B.Sc Nursing 2025 - 202601031185987538.pdf": {"doc_type": "final_allotment_result", "round_key": "R5_BDS_BSCN"},
}

SEAT_PDFS: dict[str, dict[str, str]] = {
    "FINAL SEAT MATRIX FOR AIIMS⁄BHU⁄JIMPER ROUND 1 UG 2025 (MBBS & BDS) - NMC AIIMS BHU JIMPMER Seats Per Category - 2025 - 2025072378.pdf": {"doc_type": "final_seat_matrix", "round_key": "R1"},
    "FINAL SEAT MATRIX FOR ALL INDIA QUOTA EXCEPT CENTRAL UNIVERSITY ROUND 1 UG 2025 (MBBS & BDS) - NMC NON CENTRAL UNIVERSITY ALL INDIA QUOTA SEATS Per Category - 2025 - 2025080440.pdf": {"doc_type": "final_seat_matrix", "round_key": "R1"},
    "FINAL SEAT MATRIX FOR CENTRAL UNIVERSITIES (DU⁄IP⁄BHU⁄JAMIA⁄AMU) ROUND 1 UG 2025 (MBBS & BDS) - NMC OTHER CENTRAL UNIVERSITIES QUOTA SEATS Per Category - 2025 - 2025072341.pdf": {"doc_type": "final_seat_matrix", "round_key": "R1"},
    "FINAL SEAT MATRIX FOR DEEMED UNIVERSITIES ROUND 1 UG 2025 (MBBS & BDS) - NMC DEEMED UNIVERSITIES SEATS Per Category - 2025 - 2025072244.pdf": {"doc_type": "final_seat_matrix", "round_key": "R1"},
    "FINAL SEAT MATRIX FOR ESIC IP ROUND 1 UG 2025 (MBBS & BDS) - 2025072276.pdf": {"doc_type": "final_seat_matrix", "round_key": "R1"},
    "FINAL SEAT MATRIX FOR B.SC NURSING ROUND 1 UG 2025 - 2025072473.pdf": {"doc_type": "final_seat_matrix", "round_key": "R1"},
    "SEAT MATRIX STRAY ROUND UG 2025 - 202511061324228354.pdf": {"doc_type": "final_seat_matrix", "round_key": "STRAY"},
    "SEAT MATRIX UG MBBS SPECIAL STRAY ROUND UG 2025 - 20251219617527714.pdf": {"doc_type": "final_seat_matrix", "round_key": "SPECIAL_STRAY"},
    "Seat Matrix for NEET UG (BDS B.Sc Nursing) -2025 Round 5 Counselling - 2026010176307210.pdf": {"doc_type": "final_seat_matrix", "round_key": "R5_BDS_BSCN"},
}

ALL_IN_SCOPE_PDFS = {**RESULT_PDFS, **SEAT_PDFS}
METADATA_KEYS = {"_source_pdf", "_source_pdf_path", "_source_pdf_sha256", "_table_index"}
RESULT_HEADERS = {"rank", "allotted quota", "allotted institute", "course", "alloted category", "candidate category", "remarks"}
SEAT_HEADERS = {"statename", "institute", "quota", "branch", "category", "totalseats"}
SEAT_HEADERS_WIDE = {"institute", "program", "quota", "totalseats"}
WIDE_CATEGORY_COLS = {"open", "open pwd", "general- ews", "general- ews pwd", "obc", "obc pwd", "sc", "sc pwd", "st", "st pwd"}


@dataclass(frozen=True)
class InstitutionDetails:
    display_name: str
    normalized_name: str
    full_address: str
    state_name: str
    mcc_institute_code: int | None


def normalize_spaces(value: str) -> str:
    return " ".join(value.replace("\r", " ").replace("\n", " ").split()).strip()


def normalize_key(value: str) -> str:
    return normalize_spaces(value).lower()


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def round_key_for_pdf_name(file_name: str) -> str:
    if file_name not in ALL_IN_SCOPE_PDFS:
        raise KeyError(f"Unsupported in-scope PDF: {file_name}")
    return ALL_IN_SCOPE_PDFS[file_name]["round_key"]


def normalize_program(raw: str) -> str:
    value = normalize_key(raw)
    if "mbbs" in value:
        return "MBBS"
    if "b.sc" in value and "nurs" in value:
        return "BSCN"
    if "nurs" in value:
        return "BSCN"
    if "bds" in value:
        return "BDS"
    raise ValueError(f"Unsupported program label: {raw}")


PWD_TOKENS = ["pwd", "ph", "pw"]


def _strip_pwd_tokens(value: str) -> tuple[str, bool]:
    is_pwd = any(token in value for token in PWD_TOKENS)
    cleaned = value
    for token in PWD_TOKENS:
        cleaned = cleaned.replace(token, " ")
    cleaned = " ".join(cleaned.split())
    return cleaned, is_pwd


def normalize_result_category(raw: str) -> tuple[str, bool]:
    value = normalize_key(raw)
    if value == "-":
        return ("-", False)
    cleaned, is_pwd = _strip_pwd_tokens(value)
    if cleaned in {"open", "general", "gn", "gnyes"}:
        return ("OPEN", is_pwd)
    if cleaned in {"ews", "ew", "general- ews", "general ews"}:
        return ("EWS", is_pwd)
    if cleaned in {"obc", "bc", "obc-ncl", "other backward class (obc-ncl)"} or cleaned.startswith("bc"):
        return ("OBC", is_pwd)
    if cleaned.startswith("sc"):
        return ("SC", is_pwd)
    if cleaned.startswith("st"):
        return ("ST", is_pwd)
    return (normalize_spaces(raw).upper(), is_pwd)


def normalize_seat_category(raw: str) -> tuple[str, bool]:
    value = normalize_key(raw)
    cleaned, is_pwd = _strip_pwd_tokens(value)
    if cleaned.startswith("ew") or cleaned in {"general- ews", "general ews"}:
        return ("EWS", is_pwd)
    if cleaned.startswith("op") or cleaned.startswith("open") or cleaned == "general":
        return ("OPEN", is_pwd)
    if cleaned.startswith("bc") or cleaned.startswith("obc"):
        return ("OBC", is_pwd)
    if cleaned.startswith("sc"):
        return ("SC", is_pwd)
    if cleaned.startswith("st"):
        return ("ST", is_pwd)
    return (normalize_spaces(raw).upper(), is_pwd)


def extract_institution_details(raw: str) -> InstitutionDetails:
    cleaned = normalize_spaces(raw)
    code_match = re.search(r"\((\d{6})\)\s*$", cleaned)
    mcc_code = int(code_match.group(1)) if code_match else None
    without_code = normalize_spaces(re.sub(r"\(\d{6}\)\s*$", "", cleaned))
    parts = [part.strip() for part in without_code.split(",") if part.strip()]
    state_name = parts[-2] if len(parts) >= 2 else parts[-1]
    display_name = ", ".join(parts[:2]) if len(parts) >= 2 else parts[0]
    normalized_name = normalize_key(display_name)
    return InstitutionDetails(
        display_name=display_name,
        normalized_name=normalized_name,
        full_address=without_code,
        state_name=state_name,
        mcc_institute_code=mcc_code,
    )


def update_institution_if_better(conn, schema: str, institution_id: int, details: InstitutionDetails) -> None:
    updates: list[str] = []
    params: dict[str, Any] = {"institution_id": institution_id}
    if details.mcc_institute_code is not None:
        updates.append("mcc_institute_code = COALESCE(mcc_institute_code, :mcc_code)")
        params["mcc_code"] = details.mcc_institute_code
    if details.state_name and details.state_name != "Unknown":
        updates.append("state_name = COALESCE(NULLIF(state_name, 'Unknown'), :state_name)")
        params["state_name"] = details.state_name
    if details.full_address and details.full_address != "Unknown":
        updates.append("full_address = COALESCE(NULLIF(full_address, ''), :full_address)")
        params["full_address"] = details.full_address
    if not updates:
        return
    sql = f"update {schema}.institution set {', '.join(updates)} where institution_id = :institution_id"
    conn.execute(text(sql), params)


def _is_header_row(headers: list[str]) -> bool:
    normalized = {normalize_key(h) for h in headers if h}
    return bool(RESULT_HEADERS & normalized) or bool(SEAT_HEADERS & normalized)


def _extract_values(row_data: dict[str, Any]) -> list[str]:
    return [normalize_spaces(str(v)) for k, v in row_data.items() if k not in METADATA_KEYS]


def reconstruct_tables(rows: list[dict[str, Any]]) -> list[list[dict[str, str]]]:
    grouped: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[int(row["table_index"])].append(row)

    known_headers: dict[int, list[str]] = {}

    parsed_tables: list[list[dict[str, str]]] = []
    for table_index in sorted(grouped):
        raw_rows = grouped[table_index]
        first_values = _extract_values(raw_rows[0]["row_data"])
        col_count = len(first_values)

        if _is_header_row(first_values):
            headers = first_values
            known_headers[col_count] = headers
            data_rows_start = raw_rows[1:]
        elif len(raw_rows) >= 2 and _is_header_row(_extract_values(raw_rows[1]["row_data"])):
            headers = _extract_values(raw_rows[1]["row_data"])
            known_headers[col_count] = headers
            data_rows_start = raw_rows[2:]
        elif len(raw_rows) >= 3 and _is_header_row(_extract_values(raw_rows[2]["row_data"])):
            headers = _extract_values(raw_rows[2]["row_data"])
            known_headers[col_count] = headers
            data_rows_start = raw_rows[3:]
        elif col_count in known_headers:
            headers = known_headers[col_count]
            data_rows_start = raw_rows
        else:
            continue

        table_rows: list[dict[str, str]] = []
        for raw in data_rows_start:
            row_values = _extract_values(raw["row_data"])
            converted: dict[str, str] = {}
            for idx in range(min(len(headers), len(row_values))):
                h = headers[idx]
                if h and h not in converted:
                    converted[h] = row_values[idx]
            if any(converted.values()):
                table_rows.append(converted)
        if table_rows:
            parsed_tables.append(table_rows)
    return parsed_tables


def table_kind(table_rows: list[dict[str, str]]) -> str | None:
    if not table_rows:
        return None
    headers = {normalize_key(header) for header in table_rows[0].keys()}
    if RESULT_HEADERS.issubset(headers):
        return "result"
    if SEAT_HEADERS.issubset(headers):
        return "seat"
    if SEAT_HEADERS_WIDE.issubset(headers) and headers & WIDE_CATEGORY_COLS:
        return "seat_wide"
    return None


def unpivot_wide_seat_row(row: dict[str, str]) -> list[dict[str, str]]:
    out = []
    for col, val in row.items():
        col_norm = normalize_key(col)
        if col_norm not in WIDE_CATEGORY_COLS:
            continue
        if not val.strip().isdigit() or int(val.strip()) == 0:
            continue
        out.append({
            "Institute": row.get("Institute", ""),
            "Branch": row.get("Program", ""),
            "Quota": row.get("Quota", ""),
            "Category": col,
            "TotalSeats": val.strip(),
            "StateName": "",
        })
    return out


COMPARISON_ROUND_PDFS = {
    "Final Result for Round-I of NEET UG Counselling 2025 - 20250813289226788.pdf",
    "Final Result for Round 2 of UG Counselling 2025 - 202509182057444522.pdf",
    "Final Allotment Result for Round 3 of UG Counselling 2025 - 202510231856675154.pdf",
    "Final Allotment Result for Stray Vacacy Round UG 2025 - 2025111596488171.pdf",
    "Final Result for Special Stray Round of UG counselling 2025 - 202512231822103663.pdf",
    "Final Result of UG Counselling Round 5 for BDS ⁄ B.Sc Nursing 2025 - 202601031185987538.pdf",
}


def ensure_required_documents_staged(engine, schema: str) -> None:
    existing_stmt = text(f"select distinct source_pdf from {schema}.tabula_extracted_rows")
    with engine.begin() as conn:
        existing = {row[0] for row in conn.execute(existing_stmt).fetchall()}
    missing = [pdf for pdf in ALL_IN_SCOPE_PDFS if pdf not in existing]
    for pdf_name in missing:
        pdf_path = ROOT / pdf_name
        no_header = pdf_name in COMPARISON_ROUND_PDFS
        tables = extract_tables(ExtractConfig(pdf_path=pdf_path, pages="all", mode="lattice", no_header=no_header))
        ingest_tables(engine, schema, tables, pdf_path)


def restage_comparison_round_pdfs(engine, schema: str) -> None:
    delete_stmt = text(f"delete from {schema}.tabula_extracted_rows where source_pdf = :pdf_name")
    delete_windows_stmt = text(
        f"delete from {schema}.tabula_ingestion_windows where source_pdf = :pdf_name"
    )
    for pdf_name in COMPARISON_ROUND_PDFS:
        pdf_path = ROOT / pdf_name
        if not pdf_path.exists():
            print(f"  Skipping (not found): {pdf_name}")
            continue
        print(f"  Re-staging {pdf_name} with no_header=True ...")
        with engine.begin() as conn:
            conn.execute(delete_stmt, {"pdf_name": pdf_name})
            conn.execute(delete_windows_stmt, {"pdf_name": pdf_name})
        tables = extract_tables(ExtractConfig(pdf_path=pdf_path, pages="all", mode="lattice", no_header=True))
        count = ingest_tables(engine, schema, tables, pdf_path)
        print(f"    Ingested {count} rows")



def apply_migration(engine, migration_path: Path) -> None:
    sql = migration_path.read_text(encoding="utf-8")
    with engine.begin() as conn:
        conn.execute(text(sql))


def register_source_documents(engine, schema: str) -> None:
    stmt = text(
        f"""
        insert into {schema}.source_document (file_name, absolute_path, sha256, doc_type, round_key)
        values (:file_name, :absolute_path, :sha256, :doc_type, :round_key)
        on conflict (file_name) do update set
          absolute_path = excluded.absolute_path,
          sha256 = excluded.sha256,
          doc_type = excluded.doc_type,
          round_key = excluded.round_key,
          is_active = true
        """
    )
    payload = []
    for file_name, meta in ALL_IN_SCOPE_PDFS.items():
        path = ROOT / file_name
        payload.append(
            {
                "file_name": file_name,
                "absolute_path": str(path),
                "sha256": file_sha256(path),
                "doc_type": meta["doc_type"],
                "round_key": meta["round_key"],
            }
        )
    with engine.begin() as conn:
        conn.execute(stmt, payload)


def get_dimension_id(conn, schema: str, table: str, unique_col: str, unique_val: Any, insert_cols: dict[str, Any]) -> int:
    select_stmt = text(f"select {table}_id from {schema}.{table} where {unique_col} = :value")
    found = conn.execute(select_stmt, {"value": unique_val}).scalar_one_or_none()
    if found is not None:
        return int(found)

    cols = ", ".join(insert_cols.keys())
    params = ", ".join(f":{key}" for key in insert_cols)
    insert_stmt = text(f"insert into {schema}.{table} ({cols}) values ({params}) returning {table}_id")
    return int(conn.execute(insert_stmt, insert_cols).scalar_one())


def get_round_id(conn, schema: str, round_key: str) -> int:
    return int(conn.execute(text(f"select round_id from {schema}.counselling_round where round_key=:round_key"), {"round_key": round_key}).scalar_one())


def get_program_id(conn, schema: str, program_code: str) -> int:
    return int(conn.execute(text(f"select program_id from {schema}.program where program_code=:program_code"), {"program_code": program_code}).scalar_one())


def fetch_staged_rows(conn, schema: str, pdf_name: str) -> list[dict[str, Any]]:
    rows = conn.execute(
        text(
            f"""
            select id, table_index, row_data
            from {schema}.tabula_extracted_rows
            where source_pdf = :pdf_name
            order by id
            """
        ),
        {"pdf_name": pdf_name},
    ).fetchall()
    return [{"id": row.id, "table_index": row.table_index, "row_data": row.row_data} for row in rows]


def _cached_dim_id(
    conn,
    schema: str,
    cache: dict[tuple, int],
    table: str,
    unique_col: str,
    unique_val: Any,
    insert_cols: dict[str, Any],
) -> int:
    key = (table, unique_val)
    if key in cache:
        return cache[key]
    dim_id = get_dimension_id(conn, schema, table, unique_col, unique_val, insert_cols)
    cache[key] = dim_id
    return dim_id


def load_allotment_results(engine, schema: str) -> None:
    dim_cache: dict[tuple, int] = {}
    for pdf_name in RESULT_PDFS:
        print(f"  Loading results from {pdf_name[:60]} ...")
        with engine.begin() as conn:
            source_document_id = int(conn.execute(text(f"select document_id from {schema}.source_document where file_name=:file_name"), {"file_name": pdf_name}).scalar_one())
            round_id = get_round_id(conn, schema, RESULT_PDFS[pdf_name]["round_key"])
            staged = fetch_staged_rows(conn, schema, pdf_name)
        tables = reconstruct_tables(staged)
        batch: list[dict] = []
        with engine.begin() as conn:
            for table_rows in tables:
                if table_kind(table_rows) != "result":
                    continue
                for row in table_rows:
                    rank_raw = row.get("Rank", "")
                    if not rank_raw.isdigit():
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
                            "source_document_id": source_document_id,
                        },
                    )
                    quota_id = _cached_dim_id(
                        conn, schema, dim_cache, "quota",
                        "quota_label", row["Allotted Quota"],
                        {"quota_label": row["Allotted Quota"], "quota_code": None},
                    )
                    allotted_code, allotted_pwd = normalize_result_category(row["Alloted Category"])
                    allotted_category_id = _cached_dim_id(
                        conn, schema, dim_cache, "result_category",
                        "raw_label", row["Alloted Category"],
                        {
                            "raw_label": row["Alloted Category"],
                            "normalized_code": allotted_code,
                            "is_pwd": allotted_pwd,
                        },
                    )
                    candidate_category_raw = row.get("Candidate Category") or row.get("candidate Category", "")
                    candidate_code, candidate_pwd = normalize_result_category(candidate_category_raw)
                    candidate_category_id = _cached_dim_id(
                        conn, schema, dim_cache, "result_category",
                        "raw_label", candidate_category_raw,
                        {
                            "raw_label": candidate_category_raw,
                            "normalized_code": candidate_code,
                            "is_pwd": candidate_pwd,
                        },
                    )
                    try:
                        program_id = get_program_id(conn, schema, normalize_program(row["Course"]))
                    except (ValueError, KeyError):
                        continue
                    batch.append({
                        "source_document_id": source_document_id,
                        "round_id": round_id,
                        "candidate_rank": int(rank_raw),
                        "institution_id": institution_id,
                        "program_id": program_id,
                        "quota_id": quota_id,
                        "allotted_result_category_id": allotted_category_id,
                        "candidate_result_category_id": candidate_category_id,
                        "remarks": row.get("Remarks") or None,
                        "mcc_institute_code": institution.mcc_institute_code,
                    })
            if batch:
                conn.execute(
                    text(
                        f"""
                        insert into {schema}.allotment_result_effective (
                          source_document_id, round_id, candidate_rank, institution_id, program_id, quota_id,
                          allotted_result_category_id, candidate_result_category_id, remarks, mcc_institute_code
                        ) values (
                          :source_document_id, :round_id, :candidate_rank, :institution_id, :program_id, :quota_id,
                          :allotted_result_category_id, :candidate_result_category_id, :remarks, :mcc_institute_code
                        ) on conflict do nothing
                        """
                    ),
                    batch,
                )
                print(f"    Inserted {len(batch)} rows")


def load_seat_matrix_rows(engine, schema: str) -> None:
    dim_cache: dict[tuple, int] = {}
    for pdf_name in SEAT_PDFS:
        print(f"  Loading seats from {pdf_name[:60]} ...")
        with engine.begin() as conn:
            source_document_id = int(conn.execute(text(f"select document_id from {schema}.source_document where file_name=:file_name"), {"file_name": pdf_name}).scalar_one())
            round_id = get_round_id(conn, schema, SEAT_PDFS[pdf_name]["round_key"])
            staged = fetch_staged_rows(conn, schema, pdf_name)
        tables = reconstruct_tables(staged)
        batch: list[dict] = []
        with engine.begin() as conn:
            for table_rows in tables:
                kind = table_kind(table_rows)
                if kind == "seat_wide":
                    table_rows = [narrow for wide_row in table_rows for narrow in unpivot_wide_seat_row(wide_row)]
                    kind = "seat"
                if kind != "seat":
                    continue
                for row in table_rows:
                    seats_raw = row.get("TotalSeats", "")
                    if not seats_raw.isdigit():
                        continue
                    institution = extract_institution_details(row["Institute"])
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
                    alias_key = normalize_key(row["Institute"])
                    _cached_dim_id(
                        conn, schema, dim_cache, "institution_alias",
                        "alias_normalized", alias_key,
                        {
                            "institution_id": institution_id,
                            "alias_raw": row["Institute"],
                            "alias_normalized": alias_key,
                            "source_document_id": source_document_id,
                        },
                    )
                    quota_id = _cached_dim_id(
                        conn, schema, dim_cache, "quota",
                        "quota_label", row["Quota"],
                        {"quota_label": row["Quota"], "quota_code": None},
                    )
                    seat_code, seat_pwd = normalize_seat_category(row["Category"])
                    seat_category_id = _cached_dim_id(
                        conn, schema, dim_cache, "seat_category",
                        "raw_label", row["Category"],
                        {
                            "raw_label": row["Category"],
                            "normalized_code": seat_code,
                            "is_pwd": seat_pwd,
                        },
                    )
                    try:
                        program_id = get_program_id(conn, schema, normalize_program(row["Branch"]))
                    except (ValueError, KeyError):
                        continue
                    batch.append({
                        "source_document_id": source_document_id,
                        "round_id": round_id,
                        "institution_id": institution_id,
                        "program_id": program_id,
                        "quota_id": quota_id,
                        "seat_category_id": seat_category_id,
                        "total_seats": int(seats_raw),
                    })
            if batch:
                conn.execute(
                    text(
                        f"""
                        insert into {schema}.final_seat_matrix_row (
                          source_document_id, round_id, institution_id, program_id, quota_id, seat_category_id, total_seats
                        ) values (
                          :source_document_id, :round_id, :institution_id, :program_id, :quota_id, :seat_category_id, :total_seats
                        ) on conflict do nothing
                        """
                    ),
                    batch,
                )
                print(f"    Inserted {len(batch)} rows")


def refresh_round_cutoffs(engine, schema: str) -> None:
    with engine.begin() as conn:
        conn.execute(text(f"select {schema}.sp_refresh_round_cutoffs()"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Load normalized NEET counselling schema from staged Tabula rows")
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--schema", default=SCHEMA)
    parser.add_argument("--apply-migration", action="store_true")
    parser.add_argument("--stage-documents", action="store_true")
    parser.add_argument("--register-documents", action="store_true")
    parser.add_argument("--restage-comparison-rounds", action="store_true")
    parser.add_argument("--load-results", action="store_true")
    parser.add_argument("--load-seats", action="store_true")
    parser.add_argument("--refresh-cutoffs", action="store_true")
    parser.add_argument("--refresh-quality", action="store_true")
    parser.add_argument("--all", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    engine = create_engine(args.db_url)
    if args.all or args.apply_migration:
        apply_migration(engine, ROOT / "sql" / "neetcounselling2025" / "001_normalized_foundation.sql")
        apply_migration(engine, ROOT / "sql" / "neetcounselling2025" / "003_allotment_quality.sql")
    if args.all or args.stage_documents:
        ensure_required_documents_staged(engine, args.schema)
    if args.all or args.register_documents:
        register_source_documents(engine, args.schema)
    if args.restage_comparison_rounds:
        restage_comparison_round_pdfs(engine, args.schema)
    if args.all or args.load_results:
        load_allotment_results(engine, args.schema)
    if args.all or args.load_seats:
        load_seat_matrix_rows(engine, args.schema)
    if args.all or args.load_results or args.load_seats:
        with engine.begin() as conn:
            conn.execute(text(f"select {args.schema}.sp_refresh_allotment_quality()"))
            print("  Quality flags refreshed")
    if args.all or args.refresh_cutoffs:
        refresh_round_cutoffs(engine, args.schema)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
