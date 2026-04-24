create table if not exists neetcounselling2025.allotment_raw_parsed (
  id bigserial primary key,
  source_tabula_row_id bigint not null references neetcounselling2025.tabula_extracted_rows(id),
  source_pdf text not null,
  round_key text not null,
  
  -- Parsed raw fields
  serial_no text,
  candidate_rank text,
  candidate_name text,
  allotted_quota_raw text,
  allotted_institute_raw text,
  course_name_raw text,
  allotted_category_raw text,
  candidate_category_raw text,
  remarks_raw text,
  admitted_round text,
  roll_number text,
  additional_remarks text,
  
  -- Cleaned fields
  candidate_rank_cleaned int,
  allotted_quota_cleaned text,
  allotted_institute_cleaned text,
  course_name_cleaned text,
  allotted_category_cleaned text,
  candidate_category_cleaned text,
  remarks_cleaned text,
  
  -- Foreign key to normalized institution
  institute_id bigint references neetcounselling2025.institution(institution_id),
  institute_match_method text,
  
  -- Data quality flags
  data_quality_flags text[] not null default '{}',
  
  -- Timestamps
  parsed_at timestamptz not null default now()
);

create index if not exists idx_allotment_raw_parsed_pdf
  on neetcounselling2025.allotment_raw_parsed(source_pdf);

create index if not exists idx_allotment_raw_parsed_round
  on neetcounselling2025.allotment_raw_parsed(round_key);

create index if not exists idx_allotment_raw_parsed_institute
  on neetcounselling2025.allotment_raw_parsed(institute_id);

create index if not exists idx_allotment_raw_parsed_flags
  on neetcounselling2025.allotment_raw_parsed using gin(data_quality_flags);
