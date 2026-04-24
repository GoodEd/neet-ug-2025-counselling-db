#!/usr/bin/env python3
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

MERGE_GROUPS: list[dict] = [
    {
        "canonical_id": 6023,
        "clean_label": "Deemed/Paid Seats Quota",
        "dirty_ids": [6046, 6055],
    },
    {
        "canonical_id": 6027,
        "clean_label": "Delhi NCR Children/Widows of Personnel of the Armed Forces (CW) DU Quota",
        "dirty_ids": [6050, 6058],
    },
    {
        "canonical_id": 6028,
        "clean_label": "Delhi NCR Children/Widows of Personnel of the Armed Forces (CW) IP Quota",
        "dirty_ids": [6051, 6059],
    },
    {
        "canonical_id": 6025,
        "clean_label": "Employees State Insurance Scheme(ESI)",
        "dirty_ids": [6049, 6057],
    },
    {
        "canonical_id": 6063,
        "clean_label": "Employees State Insurance Scheme Nursing Quota (ESI-IP Quota Nursing)",
        "dirty_ids": [6034, 6060],
    },
    {
        "canonical_id": 6048,
        "clean_label": "Internal - Puducherry UT Domicile",
        "dirty_ids": [6024, 6056],
    },
    {
        "canonical_id": 6038,
        "clean_label": "Non-Resident Indian",
        "dirty_ids": [6052],
    },
    {
        "canonical_id": 6040,
        "clean_label": "Non-Resident Indian(AMU)Quota",
        "dirty_ids": [6053, 6061],
    },
    {
        "canonical_id": 6045,
        "clean_label": "Non-Resident Indian(Jamia)Quota",
        "dirty_ids": [6054, 6062],
    },
]


def _remap_allotments(conn, schema: str, dirty_id: int, canonical_id: int) -> int:
    r = conn.execute(
        text(
            f"UPDATE {schema}.allotment_result_effective "
            "SET quota_id = :canonical_id WHERE quota_id = :dirty_id"
        ),
        {"canonical_id": canonical_id, "dirty_id": dirty_id},
    )
    return r.rowcount


def _delete_shadowed_cutoffs(conn, schema: str, dirty_id: int, canonical_id: int) -> int:
    r = conn.execute(
        text(
            f"""
            DELETE FROM {schema}.round_cutoff rc_dirty
            WHERE rc_dirty.quota_id = :dirty_id
              AND EXISTS (
                SELECT 1 FROM {schema}.round_cutoff rc_canon
                WHERE rc_canon.quota_id = :canonical_id
                  AND rc_canon.round_id = rc_dirty.round_id
                  AND rc_canon.institution_id = rc_dirty.institution_id
                  AND rc_canon.program_id = rc_dirty.program_id
                  AND rc_canon.allotted_result_category_id = rc_dirty.allotted_result_category_id
                  AND rc_canon.candidate_result_category_id = rc_dirty.candidate_result_category_id
              )
            """
        ),
        {"canonical_id": canonical_id, "dirty_id": dirty_id},
    )
    return r.rowcount


def _remap_cutoffs(conn, schema: str, dirty_id: int, canonical_id: int) -> int:
    r = conn.execute(
        text(
            f"UPDATE {schema}.round_cutoff SET quota_id = :canonical_id "
            "WHERE quota_id = :dirty_id"
        ),
        {"canonical_id": canonical_id, "dirty_id": dirty_id},
    )
    return r.rowcount


def _delete_shadowed_seat_matrix_rows(conn, schema: str, dirty_id: int, canonical_id: int) -> int:
    r = conn.execute(
        text(
            f"""
            DELETE FROM {schema}.final_seat_matrix_row sm_dirty
            WHERE sm_dirty.quota_id = :dirty_id
              AND EXISTS (
                SELECT 1 FROM {schema}.final_seat_matrix_row sm_canon
                WHERE sm_canon.quota_id = :canonical_id
                  AND sm_canon.source_document_id = sm_dirty.source_document_id
                  AND sm_canon.institution_id = sm_dirty.institution_id
                  AND sm_canon.program_id = sm_dirty.program_id
                  AND sm_canon.seat_category_id = sm_dirty.seat_category_id
              )
            """
        ),
        {"canonical_id": canonical_id, "dirty_id": dirty_id},
    )
    return r.rowcount


def _remap_seat_matrix_rows(conn, schema: str, dirty_id: int, canonical_id: int) -> int:
    r = conn.execute(
        text(
            f"UPDATE {schema}.final_seat_matrix_row SET quota_id = :canonical_id "
            "WHERE quota_id = :dirty_id"
        ),
        {"canonical_id": canonical_id, "dirty_id": dirty_id},
    )
    return r.rowcount


def absorb_dirty_quota(conn, schema: str, dirty_id: int, canonical_id: int) -> dict[str, int]:
    return {
        "allotment_updated": _remap_allotments(conn, schema, dirty_id, canonical_id),
        "cutoff_conflicts_deleted": _delete_shadowed_cutoffs(conn, schema, dirty_id, canonical_id),
        "cutoff_updated": _remap_cutoffs(conn, schema, dirty_id, canonical_id),
        "seat_matrix_conflicts_deleted": _delete_shadowed_seat_matrix_rows(conn, schema, dirty_id, canonical_id),
        "seat_matrix_updated": _remap_seat_matrix_rows(conn, schema, dirty_id, canonical_id),
    }


def merge_group(conn, schema: str, group: dict) -> dict[str, int]:
    canonical_id = group["canonical_id"]
    totals: dict[str, int] = {
        "allotment_updated": 0,
        "cutoff_conflicts_deleted": 0,
        "cutoff_updated": 0,
        "seat_matrix_conflicts_deleted": 0,
        "seat_matrix_updated": 0,
    }

    for dirty_id in group["dirty_ids"]:
        stats = absorb_dirty_quota(conn, schema, dirty_id, canonical_id)
        for k, v in stats.items():
            totals[k] += v
        conn.execute(
            text(f"DELETE FROM {schema}.quota WHERE quota_id = :dirty_id"),
            {"dirty_id": dirty_id},
        )

    conn.execute(
        text(f"UPDATE {schema}.quota SET quota_label = :label WHERE quota_id = :cid"),
        {"label": group["clean_label"], "cid": canonical_id},
    )

    return totals


def main() -> int:
    engine = create_engine(DB_URL)
    dirty_count = sum(len(g["dirty_ids"]) for g in MERGE_GROUPS)
    print(f"Processing {len(MERGE_GROUPS)} merge groups ({dirty_count} dirty quota rows)")

    totals: dict[str, int] = {
        "allotment_updated": 0,
        "cutoff_conflicts_deleted": 0,
        "cutoff_updated": 0,
        "seat_matrix_conflicts_deleted": 0,
        "seat_matrix_updated": 0,
        "quotas_deleted": 0,
    }

    with engine.begin() as conn:
        for group in MERGE_GROUPS:
            print(f"\n  [{group['canonical_id']}] '{group['clean_label']}' <-- {group['dirty_ids']}")
            stats = merge_group(conn, SCHEMA, group)
            totals["quotas_deleted"] += len(group["dirty_ids"])
            for k, v in stats.items():
                totals[k] += v
                if v:
                    print(f"      {k}: {v}")

    print("\n--- Totals ---")
    for k, v in totals.items():
        print(f"  {k}: {v}")

    with engine.begin() as conn:
        remaining = conn.execute(text(f"SELECT COUNT(*) FROM {SCHEMA}.quota")).scalar()
        print(f"\nQuota table rows remaining: {remaining}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
