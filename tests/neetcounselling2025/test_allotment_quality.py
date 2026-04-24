import os
import sys
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from etl.neetcounselling2025.normalized_loader import (
    normalize_result_category,
    normalize_seat_category,
)

DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    pytest.skip("DATABASE_URL not set", allow_module_level=True)


@pytest.fixture
def engine():
    return create_engine(DB_URL)


class TestCategoryNormalization:
    def test_pwd_stripped_from_open(self):
        assert normalize_result_category("Open PwD") == ("OPEN", True)
        assert normalize_result_category("OPEN PH") == ("OPEN", True)

    def test_pwd_stripped_from_obc(self):
        assert normalize_result_category("OBC PwD") == ("OBC", True)
        assert normalize_result_category("BC PH") == ("OBC", True)

    def test_pwd_stripped_from_ews(self):
        assert normalize_result_category("EWS PwD") == ("EWS", True)

    def test_general_ews_maps_to_ews(self):
        assert normalize_seat_category("General- EWS") == ("EWS", False)
        assert normalize_seat_category("General- EWS PwD") == ("EWS", True)

    def test_gn_and_gnyes_map_to_open(self):
        assert normalize_result_category("GN") == ("OPEN", False)
        assert normalize_result_category("GNYES") == ("OPEN", False)

    def test_placeholder_dash(self):
        assert normalize_result_category("-") == ("-", False)

    def test_no_pwd_for_plain_open(self):
        assert normalize_result_category("OPEN") == ("OPEN", False)
        assert normalize_result_category("General") == ("OPEN", False)


class TestRefreshAllotmentQuality:
    def test_refresh_is_idempotent(self, engine):
        with engine.begin() as conn:
            conn.execute(text("SELECT neetcounselling2025.sp_refresh_allotment_quality()"))
            first = conn.execute(
                text("""
                    SELECT unnest(data_quality_flags) as flag, count(*) as cnt
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE data_quality_flags != '{}'
                    GROUP BY flag
                    ORDER BY flag
                """)
            ).fetchall()

            conn.execute(text("SELECT neetcounselling2025.sp_refresh_allotment_quality()"))
            second = conn.execute(
                text("""
                    SELECT unnest(data_quality_flags) as flag, count(*) as cnt
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE data_quality_flags != '{}'
                    GROUP BY flag
                    ORDER BY flag
                """)
            ).fetchall()

        assert first == second, f"Flag counts changed between runs: {first} vs {second}"

    def test_mcc_code_backfill(self, engine):
        with engine.begin() as conn:
            before = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE mcc_institute_code IS NOT NULL
                """)
            ).scalar()

            conn.execute(text("SELECT neetcounselling2025.sp_refresh_allotment_quality()"))

            after = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE mcc_institute_code IS NOT NULL
                """)
            ).scalar()

        assert after >= before

    def test_institution_mcc_is_unique(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT mcc_institute_code, count(*) as cnt
                    FROM neetcounselling2025.institution
                    WHERE mcc_institute_code IS NOT NULL
                    GROUP BY mcc_institute_code
                    HAVING count(*) > 1
                """)
            ).fetchall()

        assert len(rows) == 0, f"Duplicate MCC codes found: {rows}"

    def test_no_noncanonical_categories(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT rc.normalized_code, count(*) as cnt
                    FROM neetcounselling2025.allotment_result_effective ar
                    JOIN neetcounselling2025.result_category rc ON ar.allotted_result_category_id = rc.result_category_id
                    WHERE rc.normalized_code NOT IN ('OPEN', 'EWS', 'OBC', 'SC', 'ST', '-')
                    GROUP BY rc.normalized_code
                """)
            ).fetchall()

        assert len(rows) == 0, f"Noncanonical categories still present: {rows}"

    def test_placeholder_category_flagged(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE data_quality_flags @> ARRAY['PLACEHOLDER_CATEGORY']
                """)
            ).scalar()

        assert rows > 0, "PLACEHOLDER_CATEGORY flag should be present for '-' categories"

    def test_no_recoverable_mcc_institutions(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.institution i
                    WHERE i.mcc_institute_code IS NULL
                      AND EXISTS (
                        SELECT 1 FROM neetcounselling2025.institution_alias ia
                        WHERE ia.institution_id = i.institution_id
                          AND ia.alias_raw ~ '\\(\\d{6}\\)'
                      )
                """)
            ).scalar()

        assert rows == 0, f"Found {rows} institutions with recoverable MCC codes still NULL"

    def test_no_noncanonical_candidate_categories(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT rc.normalized_code, count(*) as cnt
                    FROM neetcounselling2025.allotment_result_effective ar
                    JOIN neetcounselling2025.result_category rc ON ar.candidate_result_category_id = rc.result_category_id
                    WHERE rc.normalized_code NOT IN ('OPEN', 'EWS', 'OBC', 'SC', 'ST', '-')
                    GROUP BY rc.normalized_code
                """)
            ).fetchall()

        assert len(rows) == 0, f"Noncanonical candidate categories found: {rows}"


class TestInstituteMatching:
    def test_institute_id_populated_from_allotted_institute(self, engine):
        with engine.begin() as conn:
            row = conn.execute(
                text("""
                    SELECT ar.institution_id, i.institution_name, i.mcc_institute_code
                    FROM neetcounselling2025.allotment_result_effective ar
                    JOIN neetcounselling2025.institution i ON ar.institution_id = i.institution_id
                    WHERE ar.candidate_rank = 1
                    LIMIT 1
                """)
            ).fetchone()

        assert row is not None
        assert row.institution_id is not None
        assert row.institution_name is not None
        assert row.mcc_institute_code is not None
