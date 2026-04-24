drop function if exists neetcounselling2025.fn_available_options_by_rank(
  int, text, boolean, text[], text[], boolean, text
);

drop function if exists neetcounselling2025.fn_available_options_by_rank(
  int, text, boolean, text[], text[], boolean, text[]
);

create or replace function neetcounselling2025.fn_available_options_by_rank(
  p_rank                int,
  p_candidate_category  text     default 'OPEN',
  p_is_pwd              boolean  default false,
  p_program_codes       text[]   default null,
  p_round_keys          text[]   default null,
  p_include_after_stray boolean  default true,
  p_quota_labels        text[]   default ARRAY['All India', 'Open Seat Quota'],
  p_max_rows            int      default 100
)
returns table (
  round_key          text,
  stage_order        int,
  institution_name   text,
  full_address       text,
  state_name         text,
  mcc_institute_code int,
  program_code       text,
  quota_label        text,
  allotted_category  text,
  is_pwd             boolean,
  opening_rank       int,
  closing_rank       int,
  allotment_count    int
)
language sql
stable
as $$
  select
    cr.round_key,
    cr.stage_order,
    i.institution_name,
    i.full_address,
    i.state_name,
    i.mcc_institute_code,
    p.program_code,
    q.quota_label,
    rc_allotted.raw_label  as allotted_category,
    rc_allotted.is_pwd,
    c.opening_rank,
    c.closing_rank,
    c.allotment_count
  from neetcounselling2025.round_cutoff c
  join neetcounselling2025.counselling_round cr on cr.round_id = c.round_id
  join neetcounselling2025.institution i on i.institution_id = c.institution_id
  join neetcounselling2025.program p on p.program_id = c.program_id
  join neetcounselling2025.quota q on q.quota_id = c.quota_id
  join neetcounselling2025.result_category rc_allotted
    on rc_allotted.result_category_id = c.allotted_result_category_id
  where c.closing_rank >= p_rank
    and rc_allotted.normalized_code in (
      '-',
      'OPEN',
      neetcounselling2025.fn_normalize_candidate_category(p_candidate_category)
    )
    and (p_is_pwd or not rc_allotted.is_pwd)
    and (p_program_codes       is null or p.program_code = any(p_program_codes))
    and (p_round_keys          is null or cr.round_key   = any(p_round_keys))
    and (p_include_after_stray or cr.is_after_stray = false)
    and (p_quota_labels        is null or q.quota_label = any(p_quota_labels))
  order by c.opening_rank asc, c.closing_rank asc, i.institution_name asc
  limit p_max_rows;
$$;
