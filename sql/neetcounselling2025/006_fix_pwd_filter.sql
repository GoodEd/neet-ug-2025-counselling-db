DROP FUNCTION IF EXISTS neetcounselling2025.fn_available_options_by_rank(int, text, text[], text[], boolean, text);

CREATE FUNCTION neetcounselling2025.fn_available_options_by_rank(
  p_rank                int,
  p_candidate_category  text,
  p_is_pwd              boolean  DEFAULT false,
  p_program_codes       text[]   DEFAULT NULL,
  p_round_keys          text[]   DEFAULT NULL,
  p_include_after_stray boolean  DEFAULT true,
  p_quota_label         text     DEFAULT 'All India'
)
RETURNS TABLE (
  round_key        text,
  stage_order      int,
  institution_name text,
  full_address     text,
  state_name       text,
  mcc_institute_code int,
  program_code     text,
  quota_label      text,
  allotted_category text,
  is_pwd           boolean,
  opening_rank     int,
  closing_rank     int,
  allotment_count  int
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
    rc_allotted.raw_label   AS allotted_category,
    rc_allotted.is_pwd,
    c.opening_rank,
    c.closing_rank,
    c.allotment_count
  FROM neetcounselling2025.round_cutoff c
  JOIN neetcounselling2025.counselling_round cr
    ON cr.round_id = c.round_id
  JOIN neetcounselling2025.institution i
    ON i.institution_id = c.institution_id
  JOIN neetcounselling2025.program p
    ON p.program_id = c.program_id
  JOIN neetcounselling2025.quota q
    ON q.quota_id = c.quota_id
  JOIN neetcounselling2025.result_category rc_allotted
    ON rc_allotted.result_category_id = c.allotted_result_category_id
  WHERE c.closing_rank >= p_rank
    AND rc_allotted.normalized_code IN (
      '-',
      'OPEN',
      neetcounselling2025.fn_normalize_candidate_category(p_candidate_category)
    )
    AND (p_is_pwd OR NOT rc_allotted.is_pwd)
    AND (p_program_codes       IS NULL OR p.program_code  = ANY(p_program_codes))
    AND (p_round_keys          IS NULL OR cr.round_key    = ANY(p_round_keys))
    AND (p_include_after_stray OR cr.is_after_stray = FALSE)
    AND (p_quota_label         IS NULL OR q.quota_label   = p_quota_label)
  ORDER BY cr.stage_order, c.closing_rank, i.institution_name;
$$;
