CREATE OR REPLACE FUNCTION api.neet_colleges_text(
    p_rank integer,
    p_candidate_category text DEFAULT 'OPEN',
    p_quota_label text DEFAULT NULL
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    WITH results AS (
        SELECT *
        FROM neetcounselling2025.fn_available_options_by_rank(
            p_rank,
            p_candidate_category,
            false,
            null,
            null,
            true,
            CASE WHEN p_quota_label IS NOT NULL THEN ARRAY[p_quota_label] ELSE ARRAY['All India', 'Open Seat Quota'] END,
            30
        )
    )
    SELECT 
        CASE 
            WHEN COUNT(*) = 0 THEN 
                'No colleges found for Rank ' || p_rank || ' (' || p_candidate_category || ').'
            ELSE
                'Available Colleges for Rank ' || p_rank || ' (' || p_candidate_category || ')' || E'\n\n' ||
                STRING_AGG(
                    '• ' || institution_name || E'\n' ||
                    '  Program: ' || COALESCE(program_code, '-') || ' | Quota: ' || COALESCE(quota_label, '-') || E'\n' ||
                    '  Cutoff: ' || opening_rank || ' → ' || closing_rank || ' | ' || COALESCE(round_key, '-'),
                    E'\n\n'
                    ORDER BY opening_rank, closing_rank
                )
        END
    FROM results;
$$;

GRANT EXECUTE ON FUNCTION api.neet_colleges_text(integer, text, text) TO PUBLIC;
