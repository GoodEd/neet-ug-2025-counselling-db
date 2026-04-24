import os
import sys
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    pytest.skip("DATABASE_URL not set", allow_module_level=True)


@pytest.fixture
def engine():
    return create_engine(DB_URL)


class TestQualityFlags:
    """Regression tests for data quality flag counts after all migrations."""

    def test_zero_mcc_conflict(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*)
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE 'MCC_CONFLICT' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 0, f"Expected 0 MCC_CONFLICT, got {count}"

    def test_zero_missing_mcc_code(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*)
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE 'MISSING_MCC_CODE' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 0, f"Expected 0 MISSING_MCC_CODE, got {count}"

    def test_zero_quota_variant(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*)
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE 'QUOTA_VARIANT' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 0, f"Expected 0 QUOTA_VARIANT, got {count}"

    def test_zero_placeholder_category(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*)
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE 'PLACEHOLDER_CATEGORY' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 0, f"Expected 0 PLACEHOLDER_CATEGORY, got {count}"

    def test_rare_quota_expected_count(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*)
                    FROM neetcounselling2025.allotment_result_effective
                    WHERE 'RARE_QUOTA' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 45, f"Expected 45 RARE_QUOTA rows, got {count}"


class TestInstitutionMccCodes:
    """Regression tests for institution MCC code correctness post-migration."""

    def test_kasturba_manipal_mcc(self, engine):
        with engine.begin() as conn:
            row = conn.execute(
                text("""
                    SELECT institution_id, mcc_institute_code
                    FROM neetcounselling2025.institution
                    WHERE institution_id = 1569
                """)
            ).fetchone()
        assert row.mcc_institute_code == 200340, f"Expected 200340, got {row.mcc_institute_code}"

    def test_kasturba_mangalore_mcc(self, engine):
        with engine.begin() as conn:
            row = conn.execute(
                text("""
                    SELECT institution_id, mcc_institute_code
                    FROM neetcounselling2025.institution
                    WHERE institution_id = 2315
                """)
            ).fetchone()
        assert row.mcc_institute_code == 200339, f"Expected 200339, got {row.mcc_institute_code}"

    def test_chengalpattu_mcc(self, engine):
        with engine.begin() as conn:
            row = conn.execute(
                text("""
                    SELECT institution_id, mcc_institute_code
                    FROM neetcounselling2025.institution
                    WHERE institution_id = 1589
                """)
            ).fetchone()
        assert row.mcc_institute_code == 200258, f"Expected 200258, got {row.mcc_institute_code}"

    def test_thanjavur_mcc(self, engine):
        with engine.begin() as conn:
            row = conn.execute(
                text("""
                    SELECT institution_id, mcc_institute_code
                    FROM neetcounselling2025.institution
                    WHERE institution_id = 2291
                """)
            ).fetchone()
        assert row.mcc_institute_code == 200281, f"Expected 200281, got {row.mcc_institute_code}"

    def test_no_duplicate_mcc_codes(self, engine):
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
        assert len(rows) == 0, f"Duplicate MCC codes: {rows}"

    def test_orphan_institution_2112_deleted(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.institution
                    WHERE institution_id = 2112
                """)
            ).scalar()
        assert count == 0, "Orphan institution 2112 should be deleted"

    def test_institution_has_mcc_or_null_intentionally(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT i.institution_id, i.institution_name
                    FROM neetcounselling2025.institution i
                    WHERE i.mcc_institute_code IS NULL
                      AND EXISTS (
                        SELECT 1 FROM neetcounselling2025.allotment_result_effective ae
                        WHERE ae.institution_id = i.institution_id
                      )
                """)
            ).fetchall()
        assert len(rows) == 0, f"Institutions with allotments but no MCC: {rows}"


class TestKasturbaSplit:
    """Regression tests for multi-campus Kasturba split."""

    def test_manipal_has_no_mangalore_aliases(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT alias_raw
                    FROM neetcounselling2025.institution_alias
                    WHERE institution_id = 1569
                      AND (alias_raw ILIKE '%mangalore%' OR alias_raw ILIKE '%200339%')
                """)
            ).fetchall()
        assert len(rows) == 0, f"Manipal institution has Mangalore aliases: {rows}"

    def test_mangalore_has_mangalore_aliases(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.institution_alias
                    WHERE institution_id = 2315
                """)
            ).scalar()
        assert count >= 2, f"Mangalore institution should have aliases, got {count}"

    def test_manipal_allotment_count(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE institution_id = 1569
                """)
            ).scalar()
        assert count == 315, f"Expected 315 Manipal allotments, got {count}"

    def test_mangalore_allotment_count(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE institution_id = 2315
                """)
            ).scalar()
        assert count == 255, f"Expected 255 Mangalore allotments, got {count}"

    def test_kasturba_total_allotments_unchanged(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE institution_id IN (1569, 2315)
                """)
            ).scalar()
        assert count == 570, f"Expected 570 total Kasturba allotments, got {count}"

    def test_kasturba_has_no_conflict_flags(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE institution_id IN (1569, 2315)
                      AND 'MCC_CONFLICT' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 0, f"Kasturba campuses should have 0 MCC_CONFLICT, got {count}"


class TestChengalpattuThanjavurSplit:
    """Regression tests for Chengalpattu/Thanjavur MCC separation."""

    def test_thanjavur_aliases_moved(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT alias_raw
                    FROM neetcounselling2025.institution_alias
                    WHERE institution_id = 1589
                      AND alias_raw ILIKE '%thanjavur%'
                """)
            ).fetchall()
        assert len(rows) == 0, f"Thanjavur aliases still on Chengalpattu: {rows}"

    def test_chengalpattu_allotment_count(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE institution_id = 1589
                """)
            ).scalar()
        assert count == 60, f"Expected 60 Chengalpattu allotments, got {count}"

    def test_thanjavur_no_conflict_flags(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE institution_id = 2291
                      AND 'MCC_CONFLICT' = ANY(data_quality_flags)
                """)
            ).scalar()
        assert count == 0, f"Thanjavur should have 0 MCC_CONFLICT, got {count}"


class TestFnAvailableOptionsByRank:
    """Regression tests for fn_available_options_by_rank function contract."""

    def test_function_exists(self, engine):
        with engine.begin() as conn:
            row = conn.execute(
                text("""
                    SELECT prosrc FROM pg_proc
                    WHERE proname = 'fn_available_options_by_rank'
                      AND pronamespace = 'neetcounselling2025'::regnamespace
                """)
            ).fetchone()
        assert row is not None, "fn_available_options_by_rank does not exist"

    def test_default_args_returns_results(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT * FROM neetcounselling2025.fn_available_options_by_rank(15000)
                    LIMIT 5
                """)
            ).fetchall()
        assert len(rows) > 0, "Default args should return results for rank 15000"

    def test_default_args_respects_max_rows(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.fn_available_options_by_rank(5000)
                """)
            ).scalar()
        assert count == 100, f"Default p_max_rows=100 should return 100 rows, got {count}"

    def test_custom_max_rows(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.fn_available_options_by_rank(5000, 'OPEN', false, null, null, true, null, 10)
                """)
            ).scalar()
        assert count == 10, f"Custom p_max_rows=10 should return 10 rows, got {count}"

    def test_order_by_opening_rank_ascending(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT opening_rank FROM neetcounselling2025.fn_available_options_by_rank(5000)
                    LIMIT 5
                """)
            ).fetchall()
        opening_ranks = [r.opening_rank for r in rows]
        assert opening_ranks == sorted(opening_ranks), f"Results not ordered by opening_rank: {opening_ranks}"

    def test_default_quota_filters_deemed(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT quota_label
                    FROM neetcounselling2025.fn_available_options_by_rank(15000)
                """)
            ).fetchall()
        labels = {r.quota_label for r in rows}
        assert 'Deemed/Paid Seats Quota' not in labels, "Default should exclude Deemed/Paid"
        assert 'All India' in labels or 'Open Seat Quota' in labels, "Default should include AIQ/Open Seat"

    def test_explicit_quota_includes_deemed(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT quota_label
                    FROM neetcounselling2025.fn_available_options_by_rank(
                        15000, 'OPEN', false, null, null, true,
                        ARRAY['All India', 'Open Seat Quota', 'Deemed/Paid Seats Quota']
                    )
                """)
            ).fetchall()
        labels = {r.quota_label for r in rows}
        assert 'Deemed/Paid Seats Quota' in labels, "Explicit quota array should include Deemed/Paid"

    def test_candidate_category_filter(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT allotted_category, is_pwd
                    FROM neetcounselling2025.fn_available_options_by_rank(5000, 'SC')
                """)
            ).fetchall()
        for r in rows:
            assert r.allotted_category.upper().replace('PWD', 'PwD') in ('OPEN', 'SC', 'OPEN PwD', 'SC PwD', '-'), f"Unexpected category for SC filter: {r.allotted_category}"

    def test_mbbs_only_filter(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT program_code
                    FROM neetcounselling2025.fn_available_options_by_rank(
                        15000, 'OPEN', false, ARRAY['MBBS']
                    )
                """)
            ).fetchall()
        assert len(rows) == 1, f"Expected only MBBS, got: {[r.program_code for r in rows]}"
        assert rows[0].program_code == 'MBBS'

    def test_round_filter(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT round_key
                    FROM neetcounselling2025.fn_available_options_by_rank(
                        15000, 'OPEN', false, null, ARRAY['R1', 'R2']
                    )
                """)
            ).fetchall()
        labels = {r.round_key for r in rows}
        assert 'R3' not in labels, "Round filter should exclude R3"
        assert labels <= {'R1', 'R2'}, f"Unexpected rounds: {labels}"

    def test_pwd_filter(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT is_pwd
                    FROM neetcounselling2025.fn_available_options_by_rank(
                        15000, 'OPEN', true
                    )
                """)
            ).fetchall()
        assert any(r.is_pwd for r in rows), "PwD filter should include PwD rows"

    def test_after_stray_excluded_by_default(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT round_key
                    FROM neetcounselling2025.fn_available_options_by_rank(
                        15000, 'OPEN', false, null, null, false
                    )
                """)
            ).fetchall()
        labels = {r.round_key for r in rows}
        assert 'SPECIAL_STRAY' not in labels, "After-stray rounds should be excluded with p_include_after_stray=false"


class TestRoundCutoff:
    """Regression tests for round_cutoff table integrity."""

    def test_round_cutoff_exists(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("SELECT count(*) FROM neetcounselling2025.round_cutoff")
            ).scalar()
        assert count > 0, "round_cutoff table should have data"

    def test_opening_rank_le_closing_rank(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT round_cutoff_id, opening_rank, closing_rank
                    FROM neetcounselling2025.round_cutoff
                    WHERE opening_rank > closing_rank
                    LIMIT 5
                """)
            ).fetchall()
        assert len(rows) == 0, f"opening_rank > closing_rank found: {rows}"

    def test_no_zero_allotment_count(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT round_cutoff_id, allotment_count
                    FROM neetcounselling2025.round_cutoff
                    WHERE allotment_count = 0
                    LIMIT 5
                """)
            ).fetchall()
        assert len(rows) == 0, f"Zero allotment_count found: {rows}"

    def test_unique_round_inst_quota_category(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT round_id, institution_id, program_id, quota_id, allotted_result_category_id, count(*)
                    FROM neetcounselling2025.round_cutoff
                    GROUP BY round_id, institution_id, program_id, quota_id, allotted_result_category_id
                    HAVING count(*) > 1
                    LIMIT 5
                """)
            ).fetchall()
        assert len(rows) == 0, f"Duplicate round_cutoff composites found: {rows}"


class TestAllotmentResultEffective:
    """Regression tests for the core effective table."""

    def test_total_rows(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("SELECT count(*) FROM neetcounselling2025.allotment_result_effective")
            ).scalar()
        assert count == 52478, f"Expected 52478 total rows, got {count}"

    def test_mcc_code_backfilled(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE mcc_institute_code IS NULL
                """)
            ).scalar()
        assert count == 0, f"Expected 0 rows with NULL mcc_institute_code, got {count}"

    def test_no_negative_candidate_rank(self, engine):
        with engine.begin() as conn:
            count = conn.execute(
                text("""
                    SELECT count(*) FROM neetcounselling2025.allotment_result_effective
                    WHERE candidate_rank < 0
                """)
            ).scalar()
        assert count == 0, f"Found {count} rows with negative candidate_rank"

    def test_institution_fk_integrity(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT ae.institution_id
                    FROM neetcounselling2025.allotment_result_effective ae
                    LEFT JOIN neetcounselling2025.institution i ON ae.institution_id = i.institution_id
                    WHERE i.institution_id IS NULL
                """)
            ).fetchall()
        assert len(rows) == 0, f"Orphan institution_id in allotments: {rows}"

    def test_round_fk_integrity(self, engine):
        with engine.begin() as conn:
            rows = conn.execute(
                text("""
                    SELECT DISTINCT ae.round_id
                    FROM neetcounselling2025.allotment_result_effective ae
                    LEFT JOIN neetcounselling2025.counselling_round cr ON ae.round_id = cr.round_id
                    WHERE cr.round_id IS NULL
                """)
            ).fetchall()
        assert len(rows) == 0, f"Orphan round_id in allotments: {rows}"


class TestPdfExtractionTool:
    """Tests for update_mcc_from_pdf.py behaviors."""

    def test_get_mcc_map_returns_dict(self):
        pytest.skip("PDF extraction requires tabula-java environment setup")
        from etl.neetcounselling2025.update_mcc_from_pdf import get_mcc_map
        mcc_map = get_mcc_map()
        assert isinstance(mcc_map, dict)
        assert len(mcc_map) > 0
        for k, v in mcc_map.items():
            assert isinstance(k, str)
            assert v.isdigit()
            assert len(v) == 6
