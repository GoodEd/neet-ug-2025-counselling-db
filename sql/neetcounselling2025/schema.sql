--
-- PostgreSQL database dump
--

\restrict kb2mCagAkPRi8PwFDoZdir6yD5qSXqLWUJGhslKfJjHfUDcaTR1gStOc7jKzsCe

-- Dumped from database version 16.11
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: neetcounselling2025; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA neetcounselling2025;


--
-- Name: fn_available_options_by_rank(integer, text, boolean, text[], text[], boolean, text[], integer); Type: FUNCTION; Schema: neetcounselling2025; Owner: -
--

CREATE FUNCTION neetcounselling2025.fn_available_options_by_rank(p_rank integer, p_candidate_category text DEFAULT 'OPEN'::text, p_is_pwd boolean DEFAULT false, p_program_codes text[] DEFAULT NULL::text[], p_round_keys text[] DEFAULT NULL::text[], p_include_after_stray boolean DEFAULT true, p_quota_labels text[] DEFAULT ARRAY['All India'::text, 'Open Seat Quota'::text], p_max_rows integer DEFAULT 100) RETURNS TABLE(round_key text, stage_order integer, institution_name text, full_address text, state_name text, mcc_institute_code integer, program_code text, quota_label text, allotted_category text, is_pwd boolean, opening_rank integer, closing_rank integer, allotment_count integer)
    LANGUAGE sql STABLE
    AS $$
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


--
-- Name: fn_normalize_candidate_category(text); Type: FUNCTION; Schema: neetcounselling2025; Owner: -
--

CREATE FUNCTION neetcounselling2025.fn_normalize_candidate_category(p_input text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
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


--
-- Name: sp_refresh_allotment_quality(); Type: FUNCTION; Schema: neetcounselling2025; Owner: -
--

CREATE FUNCTION neetcounselling2025.sp_refresh_allotment_quality() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = '{}'
  where data_quality_flags is null;

  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'MISSING_MCC_CODE');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'UNKNOWN_STATE');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'RARE_QUOTA');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'NONCANONICAL_CATEGORY');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'PLACEHOLDER_CATEGORY');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'CANDIDATE_CATEGORY_ANOMALY');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'RECOVERABLE_MCC');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'MCC_CONFLICT');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'QUOTA_VARIANT');

  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = '{}'
  where data_quality_flags = '{NULL}';

  update neetcounselling2025.allotment_result_effective ar
  set mcc_institute_code = i.mcc_institute_code
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and ar.mcc_institute_code is null
    and i.mcc_institute_code is not null;

  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_append(data_quality_flags, 'MISSING_MCC_CODE')
  where mcc_institute_code is null;

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'UNKNOWN_STATE')
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and i.state_name = 'Unknown';

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'RARE_QUOTA')
  from neetcounselling2025.quota q
  where ar.quota_id = q.quota_id
    and q.quota_label in (
      select quota_label from (
        select q2.quota_label, count(*) as cnt
        from neetcounselling2025.allotment_result_effective ar2
        join neetcounselling2025.quota q2 on ar2.quota_id = q2.quota_id
        group by q2.quota_label
        having count(*) < 10
      ) rare
    );

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'NONCANONICAL_CATEGORY')
  from neetcounselling2025.result_category rc
  where ar.allotted_result_category_id = rc.result_category_id
    and rc.normalized_code not in ('OPEN', 'EWS', 'OBC', 'SC', 'ST', '-');

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'PLACEHOLDER_CATEGORY')
  from neetcounselling2025.result_category rc
  where ar.allotted_result_category_id = rc.result_category_id
    and rc.normalized_code = '-';

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'CANDIDATE_CATEGORY_ANOMALY')
  from neetcounselling2025.result_category rc
  where ar.candidate_result_category_id = rc.result_category_id
    and rc.normalized_code not in ('OPEN', 'EWS', 'OBC', 'SC', 'ST', '-');

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'RECOVERABLE_MCC')
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and i.mcc_institute_code is null
    and exists (
      select 1 from neetcounselling2025.institution_alias ia
      where ia.institution_id = i.institution_id
        and ia.alias_raw ~ '\(\d{6}\)'
    );

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'MCC_CONFLICT')
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and exists (
      select 1 from neetcounselling2025.institution_alias ia1
      join neetcounselling2025.institution_alias ia2 on ia1.institution_id = ia2.institution_id
      where ia1.institution_id = i.institution_id
        and ia1.alias_raw ~ '\(\d{6}\)'
        and ia2.alias_raw ~ '\(\d{6}\)'
        and (regexp_match(ia1.alias_raw, '\((\d{6})\)'))[1] <> (regexp_match(ia2.alias_raw, '\((\d{6})\)'))[1]
    );

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'QUOTA_VARIANT')
  from neetcounselling2025.quota q
  where ar.quota_id = q.quota_id
    and exists (
      select 1 from neetcounselling2025.quota q2
      where q2.quota_id <> q.quota_id
        and regexp_replace(lower(regexp_replace(q.quota_label, '[^a-zA-Z0-9]', '', 'g')), '\s+', '') =
            regexp_replace(lower(regexp_replace(q2.quota_label, '[^a-zA-Z0-9]', '', 'g')), '\s+', '')
    );
end;
$$;


--
-- Name: sp_refresh_round_cutoffs(); Type: FUNCTION; Schema: neetcounselling2025; Owner: -
--

CREATE FUNCTION neetcounselling2025.sp_refresh_round_cutoffs() RETURNS void
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: allotment_raw_parsed; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.allotment_raw_parsed (
    id bigint NOT NULL,
    source_tabula_row_id bigint NOT NULL,
    source_pdf text NOT NULL,
    round_key text NOT NULL,
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
    candidate_rank_cleaned integer,
    allotted_quota_cleaned text,
    allotted_institute_cleaned text,
    course_name_cleaned text,
    allotted_category_cleaned text,
    candidate_category_cleaned text,
    remarks_cleaned text,
    institute_id bigint,
    institute_match_method text,
    data_quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    parsed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: allotment_raw_parsed_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.allotment_raw_parsed_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: allotment_raw_parsed_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.allotment_raw_parsed_id_seq OWNED BY neetcounselling2025.allotment_raw_parsed.id;


--
-- Name: allotment_result_effective; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.allotment_result_effective (
    allotment_result_effective_id bigint NOT NULL,
    source_document_id bigint NOT NULL,
    round_id bigint NOT NULL,
    candidate_rank integer NOT NULL,
    institution_id bigint NOT NULL,
    program_id smallint NOT NULL,
    quota_id bigint NOT NULL,
    allotted_result_category_id bigint NOT NULL,
    candidate_result_category_id bigint NOT NULL,
    remarks text,
    mcc_institute_code integer,
    data_quality_flags text[] DEFAULT '{}'::text[] NOT NULL
);


--
-- Name: TABLE allotment_result_effective; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.allotment_result_effective IS 'Primary fact table. One row per candidate allotment from an official MCC result PDF. Contains the round, rank, institution, program, quota, and category of each allotment. Two category FKs exist per row: allotted_result_category_id (the seat type given) and candidate_result_category_id (the candidate''s own category). mcc_institute_code is denormalised from institution for query convenience. data_quality_flags is an array of issue codes set by sp_refresh_allotment_quality(); an empty array means the row passed all quality checks.';


--
-- Name: COLUMN allotment_result_effective.source_document_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.source_document_id IS 'The allotment result PDF this row was extracted from.';


--
-- Name: COLUMN allotment_result_effective.round_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.round_id IS 'Which counselling round this allotment belongs to.';


--
-- Name: COLUMN allotment_result_effective.candidate_rank; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.candidate_rank IS 'NEET UG 2025 rank of the candidate who received this allotment.';


--
-- Name: COLUMN allotment_result_effective.institution_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.institution_id IS 'FK to institution. Resolved by matching the raw institute name via institution_alias.';


--
-- Name: COLUMN allotment_result_effective.program_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.program_id IS 'FK to program (MBBS, BDS, B.Sc Nursing).';


--
-- Name: COLUMN allotment_result_effective.quota_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.quota_id IS 'FK to quota. OCR variants were deduplicated; all rows point to canonical quota rows.';


--
-- Name: COLUMN allotment_result_effective.allotted_result_category_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.allotted_result_category_id IS 'The seat category the candidate was allotted under (e.g. OBC seat, Open PwD seat).';


--
-- Name: COLUMN allotment_result_effective.candidate_result_category_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.candidate_result_category_id IS 'The candidate''s own reservation category (e.g. their personal OBC/SC/EWS status).';


--
-- Name: COLUMN allotment_result_effective.remarks; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.remarks IS 'Allotment status from the PDF: typically "Allotted" or "Upgraded".';


--
-- Name: COLUMN allotment_result_effective.mcc_institute_code; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.mcc_institute_code IS 'Denormalised copy of institution.mcc_institute_code for fast filtering without a join.';


--
-- Name: COLUMN allotment_result_effective.data_quality_flags; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.data_quality_flags IS 'Array of issue codes. Empty = clean row. Possible values: MISSING_MCC_CODE, PLACEHOLDER_CATEGORY, QUOTA_VARIANT, MCC_CONFLICT, UNKNOWN_STATE, RARE_QUOTA, NONCANONICAL_CATEGORY, RECOVERABLE_MCC, CANDIDATE_CATEGORY_ANOMALY.';


--
-- Name: allotment_result_effective_allotment_result_effective_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.allotment_result_effective_allotment_result_effective_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: allotment_result_effective_allotment_result_effective_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.allotment_result_effective_allotment_result_effective_id_seq OWNED BY neetcounselling2025.allotment_result_effective.allotment_result_effective_id;


--
-- Name: counselling_round; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.counselling_round (
    round_id bigint NOT NULL,
    round_key text NOT NULL,
    stage_order integer NOT NULL,
    round_type text NOT NULL,
    is_after_stray boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE counselling_round; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.counselling_round IS 'Each row is one phase of NEET UG 2025 counselling. stage_order determines the chronological sequence. is_after_stray marks rounds that happen after the stray vacancy round (i.e. SPECIAL_STRAY), which have different eligibility rules.';


--
-- Name: COLUMN counselling_round.round_key; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.counselling_round.round_key IS 'Short code used as a join key across all tables (R1, R2, R3, STRAY, SPECIAL_STRAY, R5_BDS_BSCN).';


--
-- Name: COLUMN counselling_round.stage_order; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.counselling_round.stage_order IS 'Chronological order of the round. 1 = first, 6 = last.';


--
-- Name: COLUMN counselling_round.round_type; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.counselling_round.round_type IS 'REGULAR = standard rounds; STRAY = stray vacancy round; SPECIAL_STRAY = post-stray special round.';


--
-- Name: COLUMN counselling_round.is_after_stray; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.counselling_round.is_after_stray IS 'True only for SPECIAL_STRAY. Marks rounds where candidates who upgraded in stray are eligible.';


--
-- Name: counselling_round_round_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.counselling_round_round_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: counselling_round_round_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.counselling_round_round_id_seq OWNED BY neetcounselling2025.counselling_round.round_id;


--
-- Name: final_seat_matrix_row; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.final_seat_matrix_row (
    final_seat_matrix_row_id bigint NOT NULL,
    source_document_id bigint NOT NULL,
    round_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    program_id smallint NOT NULL,
    quota_id bigint NOT NULL,
    seat_category_id bigint NOT NULL,
    total_seats integer NOT NULL
);


--
-- Name: TABLE final_seat_matrix_row; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.final_seat_matrix_row IS 'Total seat counts per (institution, program, quota, seat_category) combination as published in the official MCC seat matrix PDFs before counselling. Used to answer "how many seats were available" for a given combination. round_id indicates which round''s seat matrix this count applies to (seat counts can change between rounds due to additions/removals).';


--
-- Name: COLUMN final_seat_matrix_row.source_document_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.source_document_id IS 'The seat matrix PDF this count was extracted from.';


--
-- Name: COLUMN final_seat_matrix_row.round_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.round_id IS 'The counselling round for which this seat count was published.';


--
-- Name: COLUMN final_seat_matrix_row.institution_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.institution_id IS 'FK to institution.';


--
-- Name: COLUMN final_seat_matrix_row.program_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.program_id IS 'FK to program (MBBS, BDS, B.Sc Nursing).';


--
-- Name: COLUMN final_seat_matrix_row.quota_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.quota_id IS 'FK to quota. Determines which quota bucket these seats belong to.';


--
-- Name: COLUMN final_seat_matrix_row.seat_category_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.seat_category_id IS 'FK to seat_category. The reservation sub-bucket (OP NO, BC PH, EW NO, etc.).';


--
-- Name: COLUMN final_seat_matrix_row.total_seats; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.total_seats IS 'Number of seats available in this combination for this round.';


--
-- Name: final_seat_matrix_row_final_seat_matrix_row_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.final_seat_matrix_row_final_seat_matrix_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: final_seat_matrix_row_final_seat_matrix_row_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.final_seat_matrix_row_final_seat_matrix_row_id_seq OWNED BY neetcounselling2025.final_seat_matrix_row.final_seat_matrix_row_id;


--
-- Name: institution; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.institution (
    institution_id bigint NOT NULL,
    mcc_institute_code integer,
    institution_name text NOT NULL,
    institution_name_normalized text NOT NULL,
    state_name text NOT NULL,
    clean_name text,
    full_address text
);


--
-- Name: TABLE institution; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.institution IS 'Canonical list of medical colleges and institutions participating in NEET UG 2025 All India Quota counselling. Each institution has a unique MCC 6-digit code. Deduplication: 33 duplicate institutions (same MCC code, different name variants) were merged; their FK references were remapped to the surviving canonical row.';


--
-- Name: COLUMN institution.mcc_institute_code; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution.mcc_institute_code IS 'Official 6-digit institute code assigned by MCC. NULL for a small number of institutions not yet matched to an official code.';


--
-- Name: COLUMN institution.institution_name; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution.institution_name IS 'Primary name as seen in the source PDF (the most complete version found).';


--
-- Name: COLUMN institution.institution_name_normalized; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution.institution_name_normalized IS 'Lowercase, punctuation-stripped version of institution_name used for fuzzy matching.';


--
-- Name: COLUMN institution.state_name; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution.state_name IS 'State or UT where the institution is located, as declared in MCC documents.';


--
-- Name: COLUMN institution.clean_name; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution.clean_name IS 'Manually curated or algorithmically cleaned display name. May be NULL if not yet set.';


--
-- Name: COLUMN institution.full_address; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution.full_address IS 'Full postal address of the institution when available from source documents.';


--
-- Name: institution_alias; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.institution_alias (
    institution_alias_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    alias_raw text NOT NULL,
    alias_normalized text NOT NULL,
    source_document_id bigint
);


--
-- Name: TABLE institution_alias; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.institution_alias IS 'Every distinct raw name variant seen for an institution across all ingested PDFs. Used during ETL to match new text strings to existing institution_id values. One institution can have many aliases due to OCR variation, abbreviation, and round-to-round naming differences.';


--
-- Name: COLUMN institution_alias.alias_raw; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution_alias.alias_raw IS 'Verbatim institution name as extracted from the PDF.';


--
-- Name: COLUMN institution_alias.alias_normalized; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution_alias.alias_normalized IS 'Lowercase, punctuation-stripped version of alias_raw used for matching.';


--
-- Name: COLUMN institution_alias.source_document_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.institution_alias.source_document_id IS 'The document where this alias was first seen. NULL if origin document is unknown.';


--
-- Name: institution_alias_institution_alias_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.institution_alias_institution_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: institution_alias_institution_alias_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.institution_alias_institution_alias_id_seq OWNED BY neetcounselling2025.institution_alias.institution_alias_id;


--
-- Name: institution_institution_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.institution_institution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: institution_institution_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.institution_institution_id_seq OWNED BY neetcounselling2025.institution.institution_id;


--
-- Name: program; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.program (
    program_id smallint NOT NULL,
    program_code text NOT NULL,
    program_label text NOT NULL
);


--
-- Name: TABLE program; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.program IS 'Medical programmes offered under NEET UG counselling: MBBS, BDS, B.Sc Nursing. program_code is the short identifier used in queries; program_label is the display name.';


--
-- Name: COLUMN program.program_code; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.program.program_code IS 'Short canonical code: MBBS, BDS, BSCN.';


--
-- Name: COLUMN program.program_label; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.program.program_label IS 'Human-readable name: MBBS, BDS, B.Sc Nursing.';


--
-- Name: program_program_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.program_program_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: program_program_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.program_program_id_seq OWNED BY neetcounselling2025.program.program_id;


--
-- Name: quota; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.quota (
    quota_id bigint NOT NULL,
    quota_label text NOT NULL,
    quota_code text
);


--
-- Name: TABLE quota; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.quota IS 'Seat reservation buckets defined by MCC for NEET UG counselling. Each quota determines which candidates can compete for which seats (e.g. All India is open to all states; Deemed/Paid is for private deemed universities; NRI is for non-resident Indians; DU/IP quotas are university-specific). quota_code is reserved for a future short code; currently NULL for all rows.';


--
-- Name: COLUMN quota.quota_label; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.quota.quota_label IS 'Full canonical name of the quota as it appears in official MCC documents. Deduplicated — OCR space-artifact variants have been merged into this canonical label.';


--
-- Name: COLUMN quota.quota_code; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.quota.quota_code IS 'Reserved short code (e.g. AIQ, NRI). Not yet populated.';


--
-- Name: quota_quota_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.quota_quota_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: quota_quota_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.quota_quota_id_seq OWNED BY neetcounselling2025.quota.quota_id;


--
-- Name: result_category; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.result_category (
    result_category_id bigint NOT NULL,
    raw_label text NOT NULL,
    normalized_code text NOT NULL,
    is_pwd boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE result_category; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.result_category IS 'Lookup table for the category label printed in allotment result PDFs. Two category columns exist on each allotment row: the allotted category (the seat type the candidate was given) and the candidate category (the candidate''s own reservation status). raw_label is the verbatim text from the PDF; normalized_code maps it to a canonical value (OPEN, OBC, EWS, SC, ST, or -); is_pwd=true means the candidate or seat is under the PwD sub-quota.';


--
-- Name: COLUMN result_category.raw_label; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.result_category.raw_label IS 'Verbatim category label from the PDF, e.g. "Open", "General", "OBC PwD", "GNYes".';


--
-- Name: COLUMN result_category.normalized_code; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.result_category.normalized_code IS 'Canonical code: OPEN, OBC, EWS, SC, ST, or - (unknown/placeholder).';


--
-- Name: COLUMN result_category.is_pwd; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.result_category.is_pwd IS 'True when the label indicates a Person with Disability sub-quota seat or candidate.';


--
-- Name: result_category_result_category_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.result_category_result_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: result_category_result_category_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.result_category_result_category_id_seq OWNED BY neetcounselling2025.result_category.result_category_id;


--
-- Name: round_cutoff; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.round_cutoff (
    round_cutoff_id bigint NOT NULL,
    round_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    program_id smallint NOT NULL,
    quota_id bigint NOT NULL,
    allotted_result_category_id bigint NOT NULL,
    opening_rank integer NOT NULL,
    closing_rank integer NOT NULL,
    allotment_count integer NOT NULL
);


--
-- Name: TABLE round_cutoff; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.round_cutoff IS 'Opening and closing ranks for each (round, institution, program, quota, allotted_category, candidate_category) combination. Derived from allotment_result_effective: the lowest rank allotted is the opening rank, the highest rank allotted is the closing rank. Used to answer "what rank was needed to get a seat here under this quota and category". allotment_count is the number of candidates allotted in this combination for the round.';


--
-- Name: COLUMN round_cutoff.round_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.round_id IS 'The counselling round this cutoff applies to.';


--
-- Name: COLUMN round_cutoff.institution_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.institution_id IS 'FK to institution.';


--
-- Name: COLUMN round_cutoff.program_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.program_id IS 'FK to program.';


--
-- Name: COLUMN round_cutoff.quota_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.quota_id IS 'FK to quota.';


--
-- Name: COLUMN round_cutoff.allotted_result_category_id; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.allotted_result_category_id IS 'The seat category under which these cutoff ranks apply.';


--
-- Name: COLUMN round_cutoff.opening_rank; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.opening_rank IS 'Lowest (best) rank allotted in this combination — the rank of the first candidate to get this seat.';


--
-- Name: COLUMN round_cutoff.closing_rank; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.closing_rank IS 'Highest (worst) rank allotted in this combination — the rank of the last candidate to get this seat.';


--
-- Name: COLUMN round_cutoff.allotment_count; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.round_cutoff.allotment_count IS 'Total number of candidates allotted in this combination for this round.';


--
-- Name: round_cutoff_round_cutoff_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.round_cutoff_round_cutoff_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: round_cutoff_round_cutoff_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.round_cutoff_round_cutoff_id_seq OWNED BY neetcounselling2025.round_cutoff.round_cutoff_id;


--
-- Name: seat_category; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.seat_category (
    seat_category_id bigint NOT NULL,
    raw_label text NOT NULL,
    normalized_code text NOT NULL,
    is_pwd boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE seat_category; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.seat_category IS 'Lookup table for seat category codes as printed in seat matrix PDFs. These describe how seats are reserved within an institution''s quota bucket. raw_label is the verbatim PDF code (e.g. OP NO, BC PH, EW NO); normalized_code maps to OPEN/OBC/EWS/SC/ST; is_pwd=true for PH-suffix codes.';


--
-- Name: COLUMN seat_category.raw_label; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.seat_category.raw_label IS 'Verbatim seat category code from the seat matrix PDF, e.g. "OP NO", "BC PH", "EW NO".';


--
-- Name: COLUMN seat_category.normalized_code; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.seat_category.normalized_code IS 'Canonical code: OPEN, OBC, EWS, SC, or ST.';


--
-- Name: COLUMN seat_category.is_pwd; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.seat_category.is_pwd IS 'True for PH-suffix codes (BC PH, OP PH, etc.) which denote PwD reserved seats.';


--
-- Name: seat_category_seat_category_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.seat_category_seat_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seat_category_seat_category_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.seat_category_seat_category_id_seq OWNED BY neetcounselling2025.seat_category.seat_category_id;


--
-- Name: seat_matrix_institute_raw; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.seat_matrix_institute_raw (
    id integer NOT NULL,
    raw_name text NOT NULL,
    normalized_name text NOT NULL,
    source_pdf text NOT NULL,
    round_key text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    mcc_code integer
);


--
-- Name: seat_matrix_institute_raw_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.seat_matrix_institute_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seat_matrix_institute_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.seat_matrix_institute_raw_id_seq OWNED BY neetcounselling2025.seat_matrix_institute_raw.id;


--
-- Name: source_document; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.source_document (
    document_id bigint NOT NULL,
    file_name text NOT NULL,
    absolute_path text NOT NULL,
    sha256 text NOT NULL,
    doc_type text NOT NULL,
    round_key text NOT NULL,
    published_on date,
    is_active boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE source_document; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON TABLE neetcounselling2025.source_document IS 'Registry of every PDF ingested into the pipeline. doc_type distinguishes allotment result PDFs (final_allotment_result) from seat matrix PDFs (final_seat_matrix). sha256 is used to detect re-ingestion of the same file. is_active=false marks documents superseded by a corrected re-upload.';


--
-- Name: COLUMN source_document.sha256; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.source_document.sha256 IS 'SHA-256 hash of the PDF file. Used to prevent duplicate ingestion.';


--
-- Name: COLUMN source_document.doc_type; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.source_document.doc_type IS 'final_allotment_result = allotment data source; final_seat_matrix = seat count source.';


--
-- Name: COLUMN source_document.round_key; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.source_document.round_key IS 'Links the document to a counselling_round via round_key.';


--
-- Name: COLUMN source_document.is_active; Type: COMMENT; Schema: neetcounselling2025; Owner: -
--

COMMENT ON COLUMN neetcounselling2025.source_document.is_active IS 'False if this document was superseded by a corrected version and should be ignored.';


--
-- Name: source_document_document_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.source_document_document_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_document_document_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.source_document_document_id_seq OWNED BY neetcounselling2025.source_document.document_id;


--
-- Name: tabula_extracted_rows; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.tabula_extracted_rows (
    id bigint NOT NULL,
    source_pdf text NOT NULL,
    source_pdf_path text NOT NULL,
    source_pdf_sha256 text NOT NULL,
    table_index integer NOT NULL,
    extracted_at timestamp with time zone DEFAULT now() NOT NULL,
    row_data jsonb NOT NULL
);


--
-- Name: tabula_extracted_rows_id_seq; Type: SEQUENCE; Schema: neetcounselling2025; Owner: -
--

CREATE SEQUENCE neetcounselling2025.tabula_extracted_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tabula_extracted_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: neetcounselling2025; Owner: -
--

ALTER SEQUENCE neetcounselling2025.tabula_extracted_rows_id_seq OWNED BY neetcounselling2025.tabula_extracted_rows.id;


--
-- Name: tabula_ingestion_windows; Type: TABLE; Schema: neetcounselling2025; Owner: -
--

CREATE TABLE neetcounselling2025.tabula_ingestion_windows (
    source_pdf text NOT NULL,
    source_pdf_sha256 text NOT NULL,
    page_start integer NOT NULL,
    page_end integer NOT NULL,
    completed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: allotment_raw_parsed id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_raw_parsed ALTER COLUMN id SET DEFAULT nextval('neetcounselling2025.allotment_raw_parsed_id_seq'::regclass);


--
-- Name: allotment_result_effective allotment_result_effective_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective ALTER COLUMN allotment_result_effective_id SET DEFAULT nextval('neetcounselling2025.allotment_result_effective_allotment_result_effective_id_seq'::regclass);


--
-- Name: counselling_round round_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.counselling_round ALTER COLUMN round_id SET DEFAULT nextval('neetcounselling2025.counselling_round_round_id_seq'::regclass);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row ALTER COLUMN final_seat_matrix_row_id SET DEFAULT nextval('neetcounselling2025.final_seat_matrix_row_final_seat_matrix_row_id_seq'::regclass);


--
-- Name: institution institution_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution ALTER COLUMN institution_id SET DEFAULT nextval('neetcounselling2025.institution_institution_id_seq'::regclass);


--
-- Name: institution_alias institution_alias_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution_alias ALTER COLUMN institution_alias_id SET DEFAULT nextval('neetcounselling2025.institution_alias_institution_alias_id_seq'::regclass);


--
-- Name: program program_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.program ALTER COLUMN program_id SET DEFAULT nextval('neetcounselling2025.program_program_id_seq'::regclass);


--
-- Name: quota quota_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.quota ALTER COLUMN quota_id SET DEFAULT nextval('neetcounselling2025.quota_quota_id_seq'::regclass);


--
-- Name: result_category result_category_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.result_category ALTER COLUMN result_category_id SET DEFAULT nextval('neetcounselling2025.result_category_result_category_id_seq'::regclass);


--
-- Name: round_cutoff round_cutoff_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff ALTER COLUMN round_cutoff_id SET DEFAULT nextval('neetcounselling2025.round_cutoff_round_cutoff_id_seq'::regclass);


--
-- Name: seat_category seat_category_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.seat_category ALTER COLUMN seat_category_id SET DEFAULT nextval('neetcounselling2025.seat_category_seat_category_id_seq'::regclass);


--
-- Name: seat_matrix_institute_raw id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.seat_matrix_institute_raw ALTER COLUMN id SET DEFAULT nextval('neetcounselling2025.seat_matrix_institute_raw_id_seq'::regclass);


--
-- Name: source_document document_id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.source_document ALTER COLUMN document_id SET DEFAULT nextval('neetcounselling2025.source_document_document_id_seq'::regclass);


--
-- Name: tabula_extracted_rows id; Type: DEFAULT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.tabula_extracted_rows ALTER COLUMN id SET DEFAULT nextval('neetcounselling2025.tabula_extracted_rows_id_seq'::regclass);


--
-- Name: allotment_raw_parsed allotment_raw_parsed_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_raw_parsed
    ADD CONSTRAINT allotment_raw_parsed_pkey PRIMARY KEY (id);


--
-- Name: allotment_result_effective allotment_result_effective_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_pkey PRIMARY KEY (allotment_result_effective_id);


--
-- Name: allotment_result_effective allotment_result_effective_source_document_id_candidate_ran_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_source_document_id_candidate_ran_key UNIQUE (source_document_id, candidate_rank, institution_id, program_id, quota_id, allotted_result_category_id, candidate_result_category_id);


--
-- Name: counselling_round counselling_round_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.counselling_round
    ADD CONSTRAINT counselling_round_pkey PRIMARY KEY (round_id);


--
-- Name: counselling_round counselling_round_round_key_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.counselling_round
    ADD CONSTRAINT counselling_round_round_key_key UNIQUE (round_key);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_pkey PRIMARY KEY (final_seat_matrix_row_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_source_document_id_institution_id_pro_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_source_document_id_institution_id_pro_key UNIQUE (source_document_id, institution_id, program_id, quota_id, seat_category_id);


--
-- Name: institution_alias institution_alias_institution_id_alias_normalized_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution_alias
    ADD CONSTRAINT institution_alias_institution_id_alias_normalized_key UNIQUE (institution_id, alias_normalized);


--
-- Name: institution_alias institution_alias_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution_alias
    ADD CONSTRAINT institution_alias_pkey PRIMARY KEY (institution_alias_id);


--
-- Name: institution institution_institution_name_normalized_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution
    ADD CONSTRAINT institution_institution_name_normalized_key UNIQUE (institution_name_normalized);


--
-- Name: institution institution_mcc_institute_code_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution
    ADD CONSTRAINT institution_mcc_institute_code_key UNIQUE (mcc_institute_code);


--
-- Name: institution institution_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution
    ADD CONSTRAINT institution_pkey PRIMARY KEY (institution_id);


--
-- Name: program program_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.program
    ADD CONSTRAINT program_pkey PRIMARY KEY (program_id);


--
-- Name: program program_program_code_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.program
    ADD CONSTRAINT program_program_code_key UNIQUE (program_code);


--
-- Name: quota quota_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.quota
    ADD CONSTRAINT quota_pkey PRIMARY KEY (quota_id);


--
-- Name: quota quota_quota_label_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.quota
    ADD CONSTRAINT quota_quota_label_key UNIQUE (quota_label);


--
-- Name: result_category result_category_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.result_category
    ADD CONSTRAINT result_category_pkey PRIMARY KEY (result_category_id);


--
-- Name: result_category result_category_raw_label_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.result_category
    ADD CONSTRAINT result_category_raw_label_key UNIQUE (raw_label);


--
-- Name: round_cutoff round_cutoff_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_pkey PRIMARY KEY (round_cutoff_id);


--
-- Name: round_cutoff round_cutoff_unique_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_unique_key UNIQUE (round_id, institution_id, program_id, quota_id, allotted_result_category_id);


--
-- Name: seat_category seat_category_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.seat_category
    ADD CONSTRAINT seat_category_pkey PRIMARY KEY (seat_category_id);


--
-- Name: seat_category seat_category_raw_label_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.seat_category
    ADD CONSTRAINT seat_category_raw_label_key UNIQUE (raw_label);


--
-- Name: seat_matrix_institute_raw seat_matrix_institute_raw_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.seat_matrix_institute_raw
    ADD CONSTRAINT seat_matrix_institute_raw_pkey PRIMARY KEY (id);


--
-- Name: seat_matrix_institute_raw seat_matrix_institute_raw_raw_name_source_pdf_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.seat_matrix_institute_raw
    ADD CONSTRAINT seat_matrix_institute_raw_raw_name_source_pdf_key UNIQUE (raw_name, source_pdf);


--
-- Name: source_document source_document_absolute_path_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.source_document
    ADD CONSTRAINT source_document_absolute_path_key UNIQUE (absolute_path);


--
-- Name: source_document source_document_file_name_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.source_document
    ADD CONSTRAINT source_document_file_name_key UNIQUE (file_name);


--
-- Name: source_document source_document_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.source_document
    ADD CONSTRAINT source_document_pkey PRIMARY KEY (document_id);


--
-- Name: source_document source_document_sha256_key; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.source_document
    ADD CONSTRAINT source_document_sha256_key UNIQUE (sha256);


--
-- Name: tabula_extracted_rows tabula_extracted_rows_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.tabula_extracted_rows
    ADD CONSTRAINT tabula_extracted_rows_pkey PRIMARY KEY (id);


--
-- Name: tabula_ingestion_windows tabula_ingestion_windows_pkey; Type: CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.tabula_ingestion_windows
    ADD CONSTRAINT tabula_ingestion_windows_pkey PRIMARY KEY (source_pdf_sha256, page_start, page_end);


--
-- Name: idx_allotment_raw_parsed_flags; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_raw_parsed_flags ON neetcounselling2025.allotment_raw_parsed USING gin (data_quality_flags);


--
-- Name: idx_allotment_raw_parsed_institute; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_raw_parsed_institute ON neetcounselling2025.allotment_raw_parsed USING btree (institute_id);


--
-- Name: idx_allotment_raw_parsed_pdf; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_raw_parsed_pdf ON neetcounselling2025.allotment_raw_parsed USING btree (source_pdf);


--
-- Name: idx_allotment_raw_parsed_round; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_raw_parsed_round ON neetcounselling2025.allotment_raw_parsed USING btree (round_key);


--
-- Name: idx_allotment_result_effective_flags; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_result_effective_flags ON neetcounselling2025.allotment_result_effective USING gin (data_quality_flags);


--
-- Name: idx_allotment_result_effective_mcc; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_result_effective_mcc ON neetcounselling2025.allotment_result_effective USING btree (mcc_institute_code);


--
-- Name: idx_allotment_result_effective_rank; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_allotment_result_effective_rank ON neetcounselling2025.allotment_result_effective USING btree (candidate_rank);


--
-- Name: idx_institution_mcc_unique; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE UNIQUE INDEX idx_institution_mcc_unique ON neetcounselling2025.institution USING btree (mcc_institute_code) WHERE (mcc_institute_code IS NOT NULL);


--
-- Name: idx_round_cutoff_lookup; Type: INDEX; Schema: neetcounselling2025; Owner: -
--

CREATE INDEX idx_round_cutoff_lookup ON neetcounselling2025.round_cutoff USING btree (allotted_result_category_id, closing_rank, round_id, program_id);


--
-- Name: allotment_raw_parsed allotment_raw_parsed_institute_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_raw_parsed
    ADD CONSTRAINT allotment_raw_parsed_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES neetcounselling2025.institution(institution_id);


--
-- Name: allotment_raw_parsed allotment_raw_parsed_source_tabula_row_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_raw_parsed
    ADD CONSTRAINT allotment_raw_parsed_source_tabula_row_id_fkey FOREIGN KEY (source_tabula_row_id) REFERENCES neetcounselling2025.tabula_extracted_rows(id);


--
-- Name: allotment_result_effective allotment_result_effective_allotted_result_category_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_allotted_result_category_id_fkey FOREIGN KEY (allotted_result_category_id) REFERENCES neetcounselling2025.result_category(result_category_id);


--
-- Name: allotment_result_effective allotment_result_effective_candidate_result_category_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_candidate_result_category_id_fkey FOREIGN KEY (candidate_result_category_id) REFERENCES neetcounselling2025.result_category(result_category_id);


--
-- Name: allotment_result_effective allotment_result_effective_institution_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES neetcounselling2025.institution(institution_id);


--
-- Name: allotment_result_effective allotment_result_effective_program_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_program_id_fkey FOREIGN KEY (program_id) REFERENCES neetcounselling2025.program(program_id);


--
-- Name: allotment_result_effective allotment_result_effective_quota_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_quota_id_fkey FOREIGN KEY (quota_id) REFERENCES neetcounselling2025.quota(quota_id);


--
-- Name: allotment_result_effective allotment_result_effective_round_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_round_id_fkey FOREIGN KEY (round_id) REFERENCES neetcounselling2025.counselling_round(round_id);


--
-- Name: allotment_result_effective allotment_result_effective_source_document_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.allotment_result_effective
    ADD CONSTRAINT allotment_result_effective_source_document_id_fkey FOREIGN KEY (source_document_id) REFERENCES neetcounselling2025.source_document(document_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_institution_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES neetcounselling2025.institution(institution_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_program_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_program_id_fkey FOREIGN KEY (program_id) REFERENCES neetcounselling2025.program(program_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_quota_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_quota_id_fkey FOREIGN KEY (quota_id) REFERENCES neetcounselling2025.quota(quota_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_round_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_round_id_fkey FOREIGN KEY (round_id) REFERENCES neetcounselling2025.counselling_round(round_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_seat_category_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_seat_category_id_fkey FOREIGN KEY (seat_category_id) REFERENCES neetcounselling2025.seat_category(seat_category_id);


--
-- Name: final_seat_matrix_row final_seat_matrix_row_source_document_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.final_seat_matrix_row
    ADD CONSTRAINT final_seat_matrix_row_source_document_id_fkey FOREIGN KEY (source_document_id) REFERENCES neetcounselling2025.source_document(document_id);


--
-- Name: institution_alias institution_alias_institution_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution_alias
    ADD CONSTRAINT institution_alias_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES neetcounselling2025.institution(institution_id);


--
-- Name: institution_alias institution_alias_source_document_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.institution_alias
    ADD CONSTRAINT institution_alias_source_document_id_fkey FOREIGN KEY (source_document_id) REFERENCES neetcounselling2025.source_document(document_id);


--
-- Name: round_cutoff round_cutoff_allotted_result_category_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_allotted_result_category_id_fkey FOREIGN KEY (allotted_result_category_id) REFERENCES neetcounselling2025.result_category(result_category_id);


--
-- Name: round_cutoff round_cutoff_institution_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES neetcounselling2025.institution(institution_id);


--
-- Name: round_cutoff round_cutoff_program_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_program_id_fkey FOREIGN KEY (program_id) REFERENCES neetcounselling2025.program(program_id);


--
-- Name: round_cutoff round_cutoff_quota_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_quota_id_fkey FOREIGN KEY (quota_id) REFERENCES neetcounselling2025.quota(quota_id);


--
-- Name: round_cutoff round_cutoff_round_id_fkey; Type: FK CONSTRAINT; Schema: neetcounselling2025; Owner: -
--

ALTER TABLE ONLY neetcounselling2025.round_cutoff
    ADD CONSTRAINT round_cutoff_round_id_fkey FOREIGN KEY (round_id) REFERENCES neetcounselling2025.counselling_round(round_id);


--
-- PostgreSQL database dump complete
--

\unrestrict kb2mCagAkPRi8PwFDoZdir6yD5qSXqLWUJGhslKfJjHfUDcaTR1gStOc7jKzsCe

