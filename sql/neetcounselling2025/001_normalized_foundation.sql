create schema if not exists neetcounselling2025;

create table if not exists neetcounselling2025.source_document (
  document_id bigserial primary key,
  file_name text not null unique,
  absolute_path text not null unique,
  sha256 text not null unique,
  doc_type text not null,
  round_key text not null,
  published_on date null,
  is_active boolean not null default true,
  notes text null,
  created_at timestamptz not null default now()
);

create table if not exists neetcounselling2025.counselling_round (
  round_id bigserial primary key,
  round_key text not null unique,
  stage_order int not null,
  round_type text not null,
  is_after_stray boolean not null default false
);

create table if not exists neetcounselling2025.program (
  program_id smallserial primary key,
  program_code text not null unique,
  program_label text not null
);

create table if not exists neetcounselling2025.institution (
  institution_id bigserial primary key,
  mcc_institute_code int null,
  institution_name text not null,
  institution_name_normalized text not null unique,
  full_address text null,
  state_name text not null
);

create table if not exists neetcounselling2025.institution_alias (
  institution_alias_id bigserial primary key,
  institution_id bigint not null references neetcounselling2025.institution(institution_id),
  alias_raw text not null,
  alias_normalized text not null,
  source_document_id bigint null references neetcounselling2025.source_document(document_id),
  unique (institution_id, alias_normalized)
);

create table if not exists neetcounselling2025.quota (
  quota_id bigserial primary key,
  quota_label text not null unique,
  quota_code text null
);

create table if not exists neetcounselling2025.result_category (
  result_category_id bigserial primary key,
  raw_label text not null unique,
  normalized_code text not null,
  is_pwd boolean not null default false
);

create table if not exists neetcounselling2025.seat_category (
  seat_category_id bigserial primary key,
  raw_label text not null unique,
  normalized_code text not null,
  is_pwd boolean not null default false
);

create table if not exists neetcounselling2025.allotment_result_effective (
  allotment_result_effective_id bigserial primary key,
  source_document_id bigint not null references neetcounselling2025.source_document(document_id),
  round_id bigint not null references neetcounselling2025.counselling_round(round_id),
  candidate_rank int not null,
  institution_id bigint not null references neetcounselling2025.institution(institution_id),
  program_id smallint not null references neetcounselling2025.program(program_id),
  quota_id bigint not null references neetcounselling2025.quota(quota_id),
  allotted_result_category_id bigint not null references neetcounselling2025.result_category(result_category_id),
  candidate_result_category_id bigint not null references neetcounselling2025.result_category(result_category_id),
  remarks text null,
  mcc_institute_code int null,
  data_quality_flags text[] not null default '{}',
  unique (source_document_id, candidate_rank, institution_id, program_id, quota_id, allotted_result_category_id, candidate_result_category_id)
);

create table if not exists neetcounselling2025.final_seat_matrix_row (
  final_seat_matrix_row_id bigserial primary key,
  source_document_id bigint not null references neetcounselling2025.source_document(document_id),
  round_id bigint not null references neetcounselling2025.counselling_round(round_id),
  institution_id bigint not null references neetcounselling2025.institution(institution_id),
  program_id smallint not null references neetcounselling2025.program(program_id),
  quota_id bigint not null references neetcounselling2025.quota(quota_id),
  seat_category_id bigint not null references neetcounselling2025.seat_category(seat_category_id),
  total_seats int not null,
  unique (source_document_id, institution_id, program_id, quota_id, seat_category_id)
);

create table if not exists neetcounselling2025.round_cutoff (
  round_cutoff_id bigserial primary key,
  round_id bigint not null references neetcounselling2025.counselling_round(round_id),
  institution_id bigint not null references neetcounselling2025.institution(institution_id),
  program_id smallint not null references neetcounselling2025.program(program_id),
  quota_id bigint not null references neetcounselling2025.quota(quota_id),
  allotted_result_category_id bigint not null references neetcounselling2025.result_category(result_category_id),
  opening_rank int not null,
  closing_rank int not null,
  allotment_count int not null,
  unique (round_id, institution_id, program_id, quota_id, allotted_result_category_id)
);

create index if not exists idx_allotment_result_effective_rank
  on neetcounselling2025.allotment_result_effective(candidate_rank);

create index if not exists idx_round_cutoff_lookup
  on neetcounselling2025.round_cutoff(allotted_result_category_id, closing_rank, round_id, program_id);

insert into neetcounselling2025.counselling_round(round_key, stage_order, round_type, is_after_stray)
values
  ('R1', 1, 'REGULAR', false),
  ('R2', 2, 'REGULAR', false),
  ('R3', 3, 'REGULAR', false),
  ('STRAY', 4, 'STRAY', false),
  ('SPECIAL_STRAY', 5, 'SPECIAL_STRAY', true),
  ('R5_BDS_BSCN', 6, 'REGULAR', false)
on conflict (round_key) do update set
  stage_order = excluded.stage_order,
  round_type = excluded.round_type,
  is_after_stray = excluded.is_after_stray;

insert into neetcounselling2025.program(program_code, program_label)
values
  ('MBBS', 'MBBS'),
  ('BDS', 'BDS'),
  ('BSCN', 'B.Sc Nursing')
on conflict (program_code) do update set
  program_label = excluded.program_label;

create or replace function neetcounselling2025.fn_normalize_candidate_category(p_input text)
returns text
language sql
immutable
as $$
  select case upper(trim(coalesce(p_input, '')))
    when 'OPEN' then 'OPEN'
    when 'GENERAL' then 'OPEN'
    when 'GN' then 'OPEN'
    when 'EWS' then 'EWS'
    when 'EW' then 'EWS'
    when 'OBC' then 'OBC'
    when 'BC' then 'OBC'
    when 'OBC-NCL' then 'OBC'
    when 'SC' then 'SC'
    when 'ST' then 'ST'
    else upper(trim(coalesce(p_input, '')))
  end;
$$;

create or replace function neetcounselling2025.sp_refresh_round_cutoffs()
returns void
language plpgsql
as $$
begin
  truncate table neetcounselling2025.round_cutoff restart identity;

  insert into neetcounselling2025.round_cutoff (
    round_id, institution_id, program_id, quota_id, allotted_result_category_id,
    opening_rank, closing_rank, allotment_count
  )
  select
    round_id, institution_id, program_id, quota_id, allotted_result_category_id,
    min(candidate_rank),
    max(candidate_rank),
    count(*)
  from neetcounselling2025.allotment_result_effective
  group by round_id, institution_id, program_id, quota_id, allotted_result_category_id;
end;
$$;

create or replace function neetcounselling2025.fn_available_options_by_rank(
  p_rank                int,
  p_candidate_category  text,
  p_is_pwd              boolean  default false,
  p_program_codes       text[]   default null,
  p_round_keys          text[]   default null,
  p_include_after_stray boolean  default true,
  p_quota_label         text     default 'All India'
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
    and (p_quota_label         is null or q.quota_label  = p_quota_label)
  order by cr.stage_order, c.closing_rank, i.institution_name;
$$;
