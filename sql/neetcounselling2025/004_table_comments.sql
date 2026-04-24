-- ============================================================
-- Dimension tables
-- ============================================================

COMMENT ON TABLE neetcounselling2025.counselling_round IS
'Each row is one phase of NEET UG 2025 counselling. '
'stage_order determines the chronological sequence. '
'is_after_stray marks rounds that happen after the stray vacancy round '
'(i.e. SPECIAL_STRAY), which have different eligibility rules.';

COMMENT ON COLUMN neetcounselling2025.counselling_round.round_key IS
'Short code used as a join key across all tables (R1, R2, R3, STRAY, SPECIAL_STRAY, R5_BDS_BSCN).';
COMMENT ON COLUMN neetcounselling2025.counselling_round.stage_order IS
'Chronological order of the round. 1 = first, 6 = last.';
COMMENT ON COLUMN neetcounselling2025.counselling_round.round_type IS
'REGULAR = standard rounds; STRAY = stray vacancy round; SPECIAL_STRAY = post-stray special round.';
COMMENT ON COLUMN neetcounselling2025.counselling_round.is_after_stray IS
'True only for SPECIAL_STRAY. Marks rounds where candidates who upgraded in stray are eligible.';


COMMENT ON TABLE neetcounselling2025.program IS
'Medical programmes offered under NEET UG counselling: MBBS, BDS, B.Sc Nursing. '
'program_code is the short identifier used in queries; program_label is the display name.';

COMMENT ON COLUMN neetcounselling2025.program.program_code IS
'Short canonical code: MBBS, BDS, BSCN.';
COMMENT ON COLUMN neetcounselling2025.program.program_label IS
'Human-readable name: MBBS, BDS, B.Sc Nursing.';


COMMENT ON TABLE neetcounselling2025.quota IS
'Seat reservation buckets defined by MCC for NEET UG counselling. '
'Each quota determines which candidates can compete for which seats '
'(e.g. All India is open to all states; Deemed/Paid is for private deemed universities; '
'NRI is for non-resident Indians; DU/IP quotas are university-specific). '
'quota_code is reserved for a future short code; currently NULL for all rows.';

COMMENT ON COLUMN neetcounselling2025.quota.quota_label IS
'Full canonical name of the quota as it appears in official MCC documents. '
'Deduplicated — OCR space-artifact variants have been merged into this canonical label.';
COMMENT ON COLUMN neetcounselling2025.quota.quota_code IS
'Reserved short code (e.g. AIQ, NRI). Not yet populated.';


COMMENT ON TABLE neetcounselling2025.result_category IS
'Lookup table for the category label printed in allotment result PDFs. '
'Two category columns exist on each allotment row: the allotted category '
'(the seat type the candidate was given) and the candidate category '
'(the candidate''s own reservation status). '
'raw_label is the verbatim text from the PDF; normalized_code maps it to a '
'canonical value (OPEN, OBC, EWS, SC, ST, or -); is_pwd=true means the '
'candidate or seat is under the PwD sub-quota.';

COMMENT ON COLUMN neetcounselling2025.result_category.raw_label IS
'Verbatim category label from the PDF, e.g. "Open", "General", "OBC PwD", "GNYes".';
COMMENT ON COLUMN neetcounselling2025.result_category.normalized_code IS
'Canonical code: OPEN, OBC, EWS, SC, ST, or - (unknown/placeholder).';
COMMENT ON COLUMN neetcounselling2025.result_category.is_pwd IS
'True when the label indicates a Person with Disability sub-quota seat or candidate.';


COMMENT ON TABLE neetcounselling2025.seat_category IS
'Lookup table for seat category codes as printed in seat matrix PDFs. '
'These describe how seats are reserved within an institution''s quota bucket. '
'raw_label is the verbatim PDF code (e.g. OP NO, BC PH, EW NO); '
'normalized_code maps to OPEN/OBC/EWS/SC/ST; is_pwd=true for PH-suffix codes.';

COMMENT ON COLUMN neetcounselling2025.seat_category.raw_label IS
'Verbatim seat category code from the seat matrix PDF, e.g. "OP NO", "BC PH", "EW NO".';
COMMENT ON COLUMN neetcounselling2025.seat_category.normalized_code IS
'Canonical code: OPEN, OBC, EWS, SC, or ST.';
COMMENT ON COLUMN neetcounselling2025.seat_category.is_pwd IS
'True for PH-suffix codes (BC PH, OP PH, etc.) which denote PwD reserved seats.';


COMMENT ON TABLE neetcounselling2025.source_document IS
'Registry of every PDF ingested into the pipeline. '
'doc_type distinguishes allotment result PDFs (final_allotment_result) from '
'seat matrix PDFs (final_seat_matrix). sha256 is used to detect re-ingestion '
'of the same file. is_active=false marks documents superseded by a corrected re-upload.';

COMMENT ON COLUMN neetcounselling2025.source_document.sha256 IS
'SHA-256 hash of the PDF file. Used to prevent duplicate ingestion.';
COMMENT ON COLUMN neetcounselling2025.source_document.doc_type IS
'final_allotment_result = allotment data source; final_seat_matrix = seat count source.';
COMMENT ON COLUMN neetcounselling2025.source_document.round_key IS
'Links the document to a counselling_round via round_key.';
COMMENT ON COLUMN neetcounselling2025.source_document.is_active IS
'False if this document was superseded by a corrected version and should be ignored.';


-- ============================================================
-- Entity tables
-- ============================================================

COMMENT ON TABLE neetcounselling2025.institution IS
'Canonical list of medical colleges and institutions participating in NEET UG '
'2025 All India Quota counselling. Each institution has a unique MCC 6-digit code. '
'Deduplication: 33 duplicate institutions (same MCC code, different name variants) '
'were merged; their FK references were remapped to the surviving canonical row.';

COMMENT ON COLUMN neetcounselling2025.institution.mcc_institute_code IS
'Official 6-digit institute code assigned by MCC. NULL for a small number of institutions '
'not yet matched to an official code.';
COMMENT ON COLUMN neetcounselling2025.institution.institution_name IS
'Primary name as seen in the source PDF (the most complete version found).';
COMMENT ON COLUMN neetcounselling2025.institution.institution_name_normalized IS
'Lowercase, punctuation-stripped version of institution_name used for fuzzy matching.';
COMMENT ON COLUMN neetcounselling2025.institution.state_name IS
'State or UT where the institution is located, as declared in MCC documents.';
COMMENT ON COLUMN neetcounselling2025.institution.clean_name IS
'Manually curated or algorithmically cleaned display name. May be NULL if not yet set.';
COMMENT ON COLUMN neetcounselling2025.institution.full_address IS
'Full postal address of the institution when available from source documents.';


COMMENT ON TABLE neetcounselling2025.institution_alias IS
'Every distinct raw name variant seen for an institution across all ingested PDFs. '
'Used during ETL to match new text strings to existing institution_id values. '
'One institution can have many aliases due to OCR variation, abbreviation, and '
'round-to-round naming differences.';

COMMENT ON COLUMN neetcounselling2025.institution_alias.alias_raw IS
'Verbatim institution name as extracted from the PDF.';
COMMENT ON COLUMN neetcounselling2025.institution_alias.alias_normalized IS
'Lowercase, punctuation-stripped version of alias_raw used for matching.';
COMMENT ON COLUMN neetcounselling2025.institution_alias.source_document_id IS
'The document where this alias was first seen. NULL if origin document is unknown.';


-- ============================================================
-- Fact tables
-- ============================================================

COMMENT ON TABLE neetcounselling2025.allotment_result_effective IS
'Primary fact table. One row per candidate allotment from an official MCC result PDF. '
'Contains the round, rank, institution, program, quota, and category of each allotment. '
'Two category FKs exist per row: allotted_result_category_id (the seat type given) and '
'candidate_result_category_id (the candidate''s own category). '
'mcc_institute_code is denormalised from institution for query convenience. '
'data_quality_flags is an array of issue codes set by sp_refresh_allotment_quality(); '
'an empty array means the row passed all quality checks.';

COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.source_document_id IS
'The allotment result PDF this row was extracted from.';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.round_id IS
'Which counselling round this allotment belongs to.';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.candidate_rank IS
'NEET UG 2025 rank of the candidate who received this allotment.';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.institution_id IS
'FK to institution. Resolved by matching the raw institute name via institution_alias.';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.program_id IS
'FK to program (MBBS, BDS, B.Sc Nursing).';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.quota_id IS
'FK to quota. OCR variants were deduplicated; all rows point to canonical quota rows.';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.allotted_result_category_id IS
'The seat category the candidate was allotted under (e.g. OBC seat, Open PwD seat).';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.candidate_result_category_id IS
'The candidate''s own reservation category (e.g. their personal OBC/SC/EWS status).';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.remarks IS
'Allotment status from the PDF: typically "Allotted" or "Upgraded".';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.mcc_institute_code IS
'Denormalised copy of institution.mcc_institute_code for fast filtering without a join.';
COMMENT ON COLUMN neetcounselling2025.allotment_result_effective.data_quality_flags IS
'Array of issue codes. Empty = clean row. Possible values: MISSING_MCC_CODE, '
'PLACEHOLDER_CATEGORY, QUOTA_VARIANT, MCC_CONFLICT, UNKNOWN_STATE, RARE_QUOTA, '
'NONCANONICAL_CATEGORY, RECOVERABLE_MCC, CANDIDATE_CATEGORY_ANOMALY.';


COMMENT ON TABLE neetcounselling2025.final_seat_matrix_row IS
'Total seat counts per (institution, program, quota, seat_category) combination '
'as published in the official MCC seat matrix PDFs before counselling. '
'Used to answer "how many seats were available" for a given combination. '
'round_id indicates which round''s seat matrix this count applies to '
'(seat counts can change between rounds due to additions/removals).';

COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.source_document_id IS
'The seat matrix PDF this count was extracted from.';
COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.round_id IS
'The counselling round for which this seat count was published.';
COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.institution_id IS
'FK to institution.';
COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.program_id IS
'FK to program (MBBS, BDS, B.Sc Nursing).';
COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.quota_id IS
'FK to quota. Determines which quota bucket these seats belong to.';
COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.seat_category_id IS
'FK to seat_category. The reservation sub-bucket (OP NO, BC PH, EW NO, etc.).';
COMMENT ON COLUMN neetcounselling2025.final_seat_matrix_row.total_seats IS
'Number of seats available in this combination for this round.';


COMMENT ON TABLE neetcounselling2025.round_cutoff IS
'Opening and closing ranks for each (round, institution, program, quota, '
'allotted_category, candidate_category) combination. '
'Derived from allotment_result_effective: the lowest rank allotted is the opening rank, '
'the highest rank allotted is the closing rank. '
'Used to answer "what rank was needed to get a seat here under this quota and category". '
'allotment_count is the number of candidates allotted in this combination for the round.';

COMMENT ON COLUMN neetcounselling2025.round_cutoff.round_id IS
'The counselling round this cutoff applies to.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.institution_id IS
'FK to institution.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.program_id IS
'FK to program.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.quota_id IS
'FK to quota.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.allotted_result_category_id IS
'The seat category under which these cutoff ranks apply.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.candidate_result_category_id IS
'The candidate category eligible for these cutoff ranks.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.opening_rank IS
'Lowest (best) rank allotted in this combination — the rank of the first candidate to get this seat.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.closing_rank IS
'Highest (worst) rank allotted in this combination — the rank of the last candidate to get this seat.';
COMMENT ON COLUMN neetcounselling2025.round_cutoff.allotment_count IS
'Total number of candidates allotted in this combination for this round.';
