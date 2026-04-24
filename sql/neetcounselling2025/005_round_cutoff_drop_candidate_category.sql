TRUNCATE neetcounselling2025.round_cutoff RESTART IDENTITY;

ALTER TABLE neetcounselling2025.round_cutoff
  DROP CONSTRAINT round_cutoff_candidate_result_category_id_fkey,
  DROP CONSTRAINT round_cutoff_round_id_institution_id_program_id_quota_id_al_key,
  DROP COLUMN candidate_result_category_id,
  ADD CONSTRAINT round_cutoff_unique_key
    UNIQUE (round_id, institution_id, program_id, quota_id, allotted_result_category_id);

DROP INDEX IF EXISTS neetcounselling2025.idx_round_cutoff_lookup;

CREATE INDEX idx_round_cutoff_lookup
  ON neetcounselling2025.round_cutoff(allotted_result_category_id, closing_rank, round_id, program_id);

CREATE OR REPLACE FUNCTION neetcounselling2025.sp_refresh_round_cutoffs()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  TRUNCATE TABLE neetcounselling2025.round_cutoff RESTART IDENTITY;

  INSERT INTO neetcounselling2025.round_cutoff (
    round_id, institution_id, program_id, quota_id, allotted_result_category_id,
    opening_rank, closing_rank, allotment_count
  )
  SELECT
    round_id, institution_id, program_id, quota_id, allotted_result_category_id,
    MIN(candidate_rank),
    MAX(candidate_rank),
    COUNT(*)
  FROM neetcounselling2025.allotment_result_effective
  GROUP BY round_id, institution_id, program_id, quota_id, allotted_result_category_id;
END;
$$;

DROP FUNCTION IF EXISTS neetcounselling2025.fn_available_options_by_rank(int, text, text[], text[], boolean, text);

CREATE FUNCTION neetcounselling2025.fn_available_options_by_rank(
  p_rank int,
  p_candidate_category text,
  p_program_codes text[] DEFAULT NULL,
  p_round_keys text[] DEFAULT NULL,
  p_include_after_stray boolean DEFAULT true,
  p_quota_label text DEFAULT 'All India'
)
RETURNS TABLE (
  round_key text,
  stage_order int,
  institution_name text,
  full_address text,
  state_name text,
  mcc_institute_code int,
  program_code text,
  quota_label text,
  allotted_category text,
  opening_rank int,
  closing_rank int,
  allotment_count int
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    cr.round_key,
    cr.stage_order,
    i.institution_name,
    i.full_address,
    i.state_name,
    i.mcc_institute_code,
    p.program_code,
    q.quota_label,
    rc_allotted.raw_label AS allotted_category,
    c.opening_rank,
    c.closing_rank,
    c.allotment_count
  FROM neetcounselling2025.round_cutoff c
  JOIN neetcounselling2025.counselling_round cr ON cr.round_id = c.round_id
  JOIN neetcounselling2025.institution i ON i.institution_id = c.institution_id
  JOIN neetcounselling2025.program p ON p.program_id = c.program_id
  JOIN neetcounselling2025.quota q ON q.quota_id = c.quota_id
  JOIN neetcounselling2025.result_category rc_allotted
    ON rc_allotted.result_category_id = c.allotted_result_category_id
  WHERE c.closing_rank >= p_rank
    AND rc_allotted.normalized_code IN (
      '-',
      'OPEN',
      neetcounselling2025.fn_normalize_candidate_category(p_candidate_category)
    )
    AND (p_program_codes IS NULL OR p.program_code = ANY(p_program_codes))
    AND (p_round_keys IS NULL OR cr.round_key = ANY(p_round_keys))
    AND (p_include_after_stray OR cr.is_after_stray = FALSE)
    AND (p_quota_label IS NULL OR q.quota_label = p_quota_label)
  ORDER BY cr.stage_order, c.closing_rank, i.institution_name;
$$;

SELECT neetcounselling2025.sp_refresh_round_cutoffs();

COMMENT ON TABLE neetcounselling2025.round_cutoff IS
'Opening and closing ranks for each (round, institution, program, quota, allotted_category) combination. '
'Derived from allotment_result_effective: the lowest rank allotted is the opening rank, '
'the highest rank allotted is the closing rank. '
'candidate_result_category_id was removed — allotted_category already captures the seat type '
'a candidate competed for; all candidates eligible for that seat type (Open, OBC, etc.) '
'are reflected in the single closing rank across all of them. '
'allotment_count is the total candidates allotted in this combination for the round.';

COMMENT ON COLUMN neetcounselling2025.round_cutoff.allotted_result_category_id IS
'The seat category under which these cutoff ranks apply (Open, OBC, EWS, SC, ST, PwD variants, or - for no-category rows). '
'An OBC candidate is eligible for Open + OBC allotted seats; use fn_available_options_by_rank() which handles this logic.';
