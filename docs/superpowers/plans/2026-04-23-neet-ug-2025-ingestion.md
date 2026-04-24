# NEET UG 2025 Counselling Ingestion Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest 2025 MCC NEET UG counselling PDFs into PostgreSQL schema `neetcounselling2025` so the application can answer “for rank X and user category Y, which colleges, courses, quotas, and rounds were available?” across MBBS, BDS, B.Sc Nursing, regular rounds, stray round, and special-stray/after-stray stages.

**Architecture:** Build a four-layer pipeline: (1) source-document registry plus extracted page text, (2) normalized dimensions for institutions, quotas, categories, programs, and rounds, (3) round-aware seat inventory and allotment facts, and (4) derived cutoffs plus SQL functions for app queries. Use `pdftotext -layout` for text-native PDFs and fall back to OCR (`pdftoppm` + `tesseract`) for scanned PDFs.

**Tech Stack:** PostgreSQL 15+, Python 3.x ETL, `pdftotext`, `pdftoppm`, `tesseract`, SQL migrations, pytest.

---

## Chunk 1: Source shapes and ingestion rules

### What local extraction already confirmed

- Seat matrix, clear vacancy, virtual vacancy, newly-added-seat, stray seat, and special-stray seat PDFs all share the same business shape: `StateName`, `Institute`/`InstituteType`, `Quota`, `Branch`, `Category`, `TotalSeats`.
- Final result PDFs across Round 1, stray, special stray, and Round 5 (BDS/B.Sc Nursing) share the same business shape: `Rank`, `Allotted Quota`, `Allotted Institute`, `Course`, `Alloted Category`, `Candidate Category`, `Remarks`.
- Stray and special stray are not just notices; they are full data-bearing rounds and must be first-class rows in the round model.
- BDS and B.Sc Nursing are present in both seat and result PDFs and cannot be treated as afterthoughts.
- The “college list” PDF was created by a scanner app and does not yield text with `pdftotext`, so the ETL must support OCR fallback. Institution master data can still be bootstrapped from seat/result PDFs even if this specific document remains low quality.
- Round-revision notices exist. They do not become business facts themselves, but they must mark some result documents as withdrawn/superseded so only active result files feed cutoffs.

### Core ingestion rule

Treat every PDF as one of these document families:

1. `seat_matrix`
2. `vacancy_clear`
3. `vacancy_virtual`
4. `seat_addition`
5. `allotment_result`
6. `revision_notice`
7. `schedule_or_notice`

Only families 1-5 produce seat/result facts. Families 6-7 only affect metadata and document status.

---

## Chunk 2: Target PostgreSQL schema (`neetcounselling2025`)

### 2.1 Control and raw-extraction tables

#### `source_document`
Tracks every PDF and whether it is authoritative.

| Column | Type | Notes |
|---|---|---|
| `document_id` | `bigserial primary key` | Surrogate key |
| `file_name` | `text not null` | Original PDF name |
| `absolute_path` | `text not null unique` | Local path used for extraction |
| `sha256` | `text not null unique` | Detect duplicates/reloads |
| `counselling_year` | `int not null default 2025` | Fixed for this dataset |
| `doc_family` | `text not null` | `seat_matrix`, `vacancy_clear`, `allotment_result`, etc. |
| `round_id` | `bigint null references counselling_round(round_id)` | Null for general notices |
| `doc_status` | `text not null default 'active'` | `active`, `withdrawn`, `superseded`, `informational` |
| `published_on` | `date null` | From notice text / filename when available |
| `page_count` | `int null` | From `pdfinfo` |
| `is_scanned` | `boolean not null default false` | True for OCR path |
| `extraction_method` | `text not null` | `pdftotext_layout`, `ocr_tesseract`, etc. |
| `extraction_status` | `text not null default 'pending'` | `pending`, `done`, `failed` |
| `superseded_by_document_id` | `bigint null references source_document(document_id)` | For revised results |
| `notes` | `text null` | Parsing remarks |
| `created_at` | `timestamptz not null default now()` | Audit |

#### `document_page_text`
Stores extracted page text so the parser can be re-run without reopening PDFs.

| Column | Type | Notes |
|---|---|---|
| `document_page_text_id` | `bigserial primary key` | Surrogate key |
| `document_id` | `bigint not null references source_document(document_id)` | Parent PDF |
| `page_no` | `int not null` | 1-based page number |
| `extraction_method` | `text not null` | Same family as source method |
| `page_text` | `text not null` | Full extracted page text |
| `char_count` | `int not null` | Simple completeness check |
| `created_at` | `timestamptz not null default now()` | Audit |

Unique key: `(`document_id`, `page_no`, `extraction_method`)`

#### `parsed_document_row`
Stores parser output before business normalization.

| Column | Type | Notes |
|---|---|---|
| `parsed_row_id` | `bigserial primary key` | Surrogate key |
| `document_id` | `bigint not null references source_document(document_id)` | Parent PDF |
| `page_no` | `int null` | Source page |
| `row_kind` | `text not null` | `seat_inventory`, `allotment_result`, `legend`, `notice` |
| `row_no` | `int not null` | Sequence within document |
| `raw_row_text` | `text not null` | Exact raw row/string |
| `raw_fields` | `jsonb not null` | Parsed but unnormalized columns |
| `parse_status` | `text not null default 'parsed'` | `parsed`, `partial`, `failed` |
| `parse_error` | `text null` | Error details if partial/failed |
| `row_hash` | `text not null` | Idempotent reload key |
| `created_at` | `timestamptz not null default now()` | Audit |

Unique key: `(`document_id`, `row_kind`, `row_no`)`

#### `document_status_resolution`
Deterministic mapping for revision/withdrawal notices to concrete result documents.

| Column | Type | Notes |
|---|---|---|
| `document_status_resolution_id` | `bigserial primary key` | Surrogate key |
| `notice_document_id` | `bigint not null references source_document(document_id)` | Revision/withdrawal notice |
| `target_document_id` | `bigint not null references source_document(document_id)` | Result PDF to be deactivated |
| `replacement_document_id` | `bigint null references source_document(document_id)` | Revised replacement result |
| `resolution_rule` | `text not null` | `EXPLICIT_MANUAL`, `ROUND_DATE_LATEST_ACTIVE`, etc. |
| `resolution_confidence` | `text not null` | `high`, `medium`, `low` |
| `resolved_by` | `text not null` | `system` or operator ID |
| `resolved_at` | `timestamptz not null default now()` | Audit |
| `notes` | `text null` | Why this mapping was chosen |

Unique key: `(`notice_document_id`, `target_document_id`)`

### 2.2 Reference dimensions

#### `counselling_round`

| Column | Type | Notes |
|---|---|---|
| `round_id` | `bigserial primary key` | Surrogate key |
| `round_key` | `text not null unique` | Examples: `R1`, `R2`, `R3`, `STRAY`, `SPECIAL_STRAY`, `R5_BDS_BSCN` |
| `round_number` | `int null` | 1/2/3/5 where applicable |
| `round_type` | `text not null` | `REGULAR`, `STRAY`, `SPECIAL_STRAY` |
| `stage_order` | `int not null` | Sort order for app |
| `stage_label` | `text not null` | Human label |
| `program_scope` | `text not null` | `UG_MAIN`, `BDS_BSCN_ONLY`, `NURSING_ONLY` |
| `is_after_stray` | `boolean not null default false` | True for special-stray/after-stray |
| `notes` | `text null` | Extra round notes |

#### `institution`
Canonical college/institute master. Use MCC-style numeric code from trailing parentheses where present.

| Column | Type | Notes |
|---|---|---|
| `institution_id` | `bigserial primary key` | Surrogate key |
| `mcc_institute_code` | `int null unique` | Extract from `(200447)` etc. |
| `state_name` | `text not null` | Canonical state |
| `institution_name` | `text not null` | Best canonical display name |
| `institution_name_normalized` | `text not null` | Whitespace/punctuation-normalized match key |
| `institute_type_raw` | `text null` | From seat docs where present |
| `address_raw` | `text null` | Full text after name |
| `source_first_document_id` | `bigint null references source_document(document_id)` | Provenance |
| `is_active` | `boolean not null default true` | Soft active flag |
| `created_at` | `timestamptz not null default now()` | Audit |
| `updated_at` | `timestamptz not null default now()` | Audit |

#### `institution_alias`
Mandatory because seat PDFs and result PDFs often spell the same institute differently.

| Column | Type | Notes |
|---|---|---|
| `institution_alias_id` | `bigserial primary key` | Surrogate key |
| `institution_id` | `bigint not null references institution(institution_id)` | Canonical institution |
| `alias_raw` | `text not null` | Raw extracted label |
| `alias_normalized` | `text not null` | Match key |
| `alias_source` | `text not null` | `seat_matrix`, `result`, `manual_override`, etc. |
| `document_id` | `bigint null references source_document(document_id)` | Provenance |
| `created_at` | `timestamptz not null default now()` | Audit |

Recommended unique key: `(`institution_id`, `alias_normalized`)`

#### `program`

| Column | Type | Notes |
|---|---|---|
| `program_id` | `smallserial primary key` | Small reference set |
| `program_code` | `text not null unique` | `MBBS`, `BDS`, `BSCN` |
| `branch_label` | `text not null unique` | `MBBS (MBBS)`, `BDS (BDS)`, `B.Sc. Nursing (BSCN)` |
| `degree_name` | `text not null` | Human label |
| `is_active` | `boolean not null default true` | Soft active flag |

#### `quota`
Normalized quota master across seat and result documents.

| Column | Type | Notes |
|---|---|---|
| `quota_id` | `bigserial primary key` | Surrogate key |
| `quota_code` | `text null unique` | `AI`, `SO`, `PS`, `IP`, `DU`, `EN`, etc. when known |
| `quota_label` | `text not null unique` | `All India`, `Open Seat Quota`, `Deemed/Paid Seats Quota`, etc. |
| `quota_group` | `text not null` | Reporting group |
| `is_paid_quota` | `boolean not null default false` | True for deemed/paid |
| `is_nri_quota` | `boolean not null default false` | True for NRI/foreign variants |
| `notes` | `text null` | For B.Sc Nursing CW/IP variants |

#### `quota_alias`

| Column | Type | Notes |
|---|---|---|
| `quota_alias_id` | `bigserial primary key` | Surrogate key |
| `quota_id` | `bigint not null references quota(quota_id)` | Canonical quota |
| `alias_label` | `text not null unique` | Raw label or abbreviation expansion |

#### `seat_category`
Represents seat-side reservation buckets from seat/vacancy documents, e.g. `BC NO`, `OP PH`.

| Column | Type | Notes |
|---|---|---|
| `seat_category_id` | `bigserial primary key` | Surrogate key |
| `raw_label` | `text not null unique` | Exact PDF value |
| `base_category_code` | `text not null` | `BC`, `EW`, `OP`, `SC`, `ST` |
| `seat_subtype_code` | `text not null` | `NO`, `PH` |
| `is_pwd` | `boolean not null default false` | Derived from subtype |
| `display_label` | `text not null` | App-friendly label |

#### `allotment_category`
Represents the allotted seat bucket from result PDFs.

| Column | Type | Notes |
|---|---|---|
| `allotment_category_id` | `bigserial primary key` | Surrogate key |
| `raw_label` | `text not null unique` | `Open`, `OBC`, `EWS`, `SC`, `ST`, etc. |
| `normalized_code` | `text not null` | App/filter key |
| `is_pwd` | `boolean not null default false` | If present in result docs |
| `display_label` | `text not null` | Human label |

#### `candidate_category`
Represents the candidate’s own category from result PDFs.

| Column | Type | Notes |
|---|---|---|
| `candidate_category_id` | `bigserial primary key` | Surrogate key |
| `raw_label` | `text not null unique` | `General`, `OBC`, `EWS`, `SC`, `ST`, etc. |
| `normalized_code` | `text not null` | `GN`, `BC`, `EW`, `SC`, `ST` |
| `is_pwd` | `boolean not null default false` | If present |
| `display_label` | `text not null` | Human label |

### 2.3 Business fact tables

#### `seat_snapshot`
One document can create one snapshot of a specific kind within a round.

| Column | Type | Notes |
|---|---|---|
| `seat_snapshot_id` | `bigserial primary key` | Surrogate key |
| `document_id` | `bigint not null references source_document(document_id)` | Back to PDF |
| `round_id` | `bigint not null references counselling_round(round_id)` | Round/stage |
| `snapshot_kind` | `text not null` | `FINAL_SEAT_MATRIX`, `CLEAR_VACANCY`, `VIRTUAL_VACANCY`, `NEWLY_ADDED`, `STRAY_SEAT_MATRIX`, `SPECIAL_STRAY_SEAT_MATRIX` |
| `snapshot_sequence` | `int not null` | Order within round for addenda/revisions |
| `effective_on` | `date null` | Publication/effective date |
| `is_active` | `boolean not null default true` | False if superseded |
| `notes` | `text null` | Audit comments |

#### `seat_snapshot_row`

| Column | Type | Notes |
|---|---|---|
| `seat_snapshot_row_id` | `bigserial primary key` | Surrogate key |
| `seat_snapshot_id` | `bigint not null references seat_snapshot(seat_snapshot_id)` | Parent snapshot |
| `institution_id` | `bigint not null references institution(institution_id)` | College |
| `program_id` | `smallint not null references program(program_id)` | MBBS/BDS/BSCN |
| `quota_id` | `bigint not null references quota(quota_id)` | Quota |
| `seat_category_id` | `bigint not null references seat_category(seat_category_id)` | Seat reservation bucket |
| `total_seats` | `int not null` | Number of seats in that bucket |
| `state_name_raw` | `text not null` | Raw value for audit |
| `institute_type_raw` | `text null` | Only present in some files |
| `institute_raw` | `text not null` | Raw institute text |
| `branch_raw` | `text not null` | Raw branch label |
| `category_raw` | `text not null` | Raw seat category |
| `row_hash` | `text not null` | Idempotence |

Recommended unique key: `(`seat_snapshot_id`, `institution_id`, `program_id`, `quota_id`, `seat_category_id`)`

#### `allotment_result`

| Column | Type | Notes |
|---|---|---|
| `allotment_result_id` | `bigserial primary key` | Surrogate key |
| `document_id` | `bigint not null references source_document(document_id)` | Back to PDF |
| `round_id` | `bigint not null references counselling_round(round_id)` | Round/stage |
| `serial_no` | `int null` | PDF serial number |
| `candidate_rank` | `int not null` | Core ranking field for the app |
| `institution_id` | `bigint not null references institution(institution_id)` | Allotted institution |
| `program_id` | `smallint not null references program(program_id)` | Course/program |
| `quota_id` | `bigint not null references quota(quota_id)` | Allotted quota |
| `allotment_category_id` | `bigint not null references allotment_category(allotment_category_id)` | Seat bucket on result |
| `candidate_category_id` | `bigint not null references candidate_category(candidate_category_id)` | Candidate’s category |
| `remarks` | `text null` | Usually `Allotted` |
| `institute_raw` | `text not null` | Raw result text |
| `course_raw` | `text not null` | Raw course text |
| `row_hash` | `text not null` | Idempotence |
| `is_active` | `boolean not null default true` | False if source result withdrawn |

Recommended unique key: `(`document_id`, `serial_no`, `candidate_rank`, `institution_id`, `program_id`, `quota_id`)`

#### `allotment_cutoff`
Pre-aggregated query table for rank-based app lookups.

| Column | Type | Notes |
|---|---|---|
| `allotment_cutoff_id` | `bigserial primary key` | Surrogate key |
| `round_id` | `bigint not null references counselling_round(round_id)` | Round/stage |
| `institution_id` | `bigint not null references institution(institution_id)` | College |
| `program_id` | `smallint not null references program(program_id)` | MBBS/BDS/BSCN |
| `quota_id` | `bigint not null references quota(quota_id)` | Quota |
| `allotment_category_id` | `bigint not null references allotment_category(allotment_category_id)` | Allotted seat bucket |
| `candidate_category_id` | `bigint not null references candidate_category(candidate_category_id)` | Candidate category |
| `opening_rank` | `int not null` | Min rank in that bucket |
| `closing_rank` | `int not null` | Max rank in that bucket |
| `allotment_count` | `int not null` | Number of allotted rows |
| `result_document_id` | `bigint not null references source_document(document_id)` | Provenance |
| `refreshed_at` | `timestamptz not null default now()` | Audit |

Recommended unique key: `(`round_id`, `institution_id`, `program_id`, `quota_id`, `allotment_category_id`, `candidate_category_id`)`

---

## Chunk 3: Relationship model and normalization rules

### Relationship summary

- `counselling_round 1:N source_document`
- `source_document 1:N document_page_text`
- `source_document 1:N parsed_document_row`
- `institution 1:N institution_alias`
- `source_document 1:N seat_snapshot`
- `seat_snapshot 1:N seat_snapshot_row`
- `institution/program/quota/seat_category` are shared dimensions for `seat_snapshot_row`
- `source_document 1:N allotment_result`
- `institution/program/quota/allotment_category/candidate_category` are shared dimensions for `allotment_result`
- `allotment_result -> allotment_cutoff` is many-to-one aggregation by round + institution + program + quota + allotted category + candidate category

### Normalization rules

1. **Institution identity**
   - Prefer trailing numeric MCC code from seat/vacancy PDFs as canonical identity.
   - When result PDFs omit the code, resolve via `institution_alias` on normalized name + state.
   - Keep raw text in fact tables for audit; never discard the original institute string.

2. **Program identity**
   - Map `MBBS (MBBS)` -> `MBBS`
   - Map `BDS (BDS)` -> `BDS`
   - Map `B.Sc. Nursing (BSCN)` -> `BSCN`

3. **Quota identity**
   - Store both the full text label and, where available from legends, the short code (`AI`, `SO`, `PS`, `IP`, `EN`, etc.).
   - Do not hard-code only MBBS-style quotas; B.Sc Nursing Delhi NCR / IP CW / ESI-IP quota rows must remain first-class quota values.

4. **Category identity**
   - Keep seat-side categories (`BC NO`, `OP PH`) separate from result-side allotted categories (`Open`, `OBC`, `EWS`) because they are related but not text-identical.
   - Keep candidate category as a separate dimension because the app’s main filter is user category.

5. **Round identity**
   - Treat `STRAY` and `SPECIAL_STRAY` as distinct rounds.
   - Model special stray as `is_after_stray = true` so downstream queries can group it as “after stray” without losing the explicit source label.
   - Model Round 5 BDS/B.Sc Nursing separately from Round 1/2/3 MBBS-centric counselling.

6. **Revision handling**
   - Keep withdrawn/superseded result PDFs in `source_document`, but exclude them from downstream cutoffs by `doc_status != 'active'`.
   - Record supersession links instead of deleting old documents.

---

## Chunk 4: Ingestion sequence

### Step A: Register source PDFs
- Hash every PDF.
- Classify it into a document family.
- Assign a round where applicable.
- Capture whether the file is scanned or text-native.

### Step B: Extract page text
- First attempt: `pdftotext -layout`.
- If output is blank/near-blank or only form-feed characters, mark the file as scanned and re-run through `pdftoppm` + `tesseract`.
- Persist extracted text in `document_page_text`.

### Step C: Parse raw rows
- Parse seat/vacancy/addition/special-stray matrices into `parsed_document_row(row_kind='seat_inventory')`.
- Parse result PDFs into `parsed_document_row(row_kind='allotment_result')`.
- Parse legends only if useful for building quota/category alias maps.
- Parse revision notices into `parsed_document_row(row_kind='notice')` only for audit.

### Step D: Upsert dimensions
- Upsert rounds.
- Upsert programs.
- Upsert quotas and quota aliases.
- Upsert seat categories, allotted categories, and candidate categories.
- Upsert institutions and aliases.

### Step E: Build business facts
- For seat-like documents, create one `seat_snapshot` and many `seat_snapshot_row` records.
- For result documents, create `allotment_result` rows.
- For revision/withdrawal notices, resolve mappings in `document_status_resolution` first, then update `source_document.doc_status` and `superseded_by_document_id`.

### Deterministic revision mapping rule (mandatory)
When a notice says a previously published result is withdrawn/revised:

1. Resolve `notice_document_id` (the notice itself).
2. Resolve `target_document_id` as the latest active `allotment_result` document for the same `round_id` with `published_on <= notice.published_on`.
3. Resolve `replacement_document_id` as the next active `allotment_result` document for the same `round_id` with `published_on >= notice.published_on` (if available).
4. Persist this mapping in `document_status_resolution`.
5. Mark `target_document_id` as `withdrawn` or `superseded` and set `superseded_by_document_id = replacement_document_id` when present.

If multiple candidates tie under step 2 or 3, do not guess: create a row with `resolution_rule='EXPLICIT_MANUAL'`, `resolution_confidence='low'`, and require operator confirmation before cutoff refresh.

### Step F: Build derived cutoffs
- Aggregate active `allotment_result` rows into `allotment_cutoff`.
- Use `min(candidate_rank)` as opening rank and `max(candidate_rank)` as closing rank for each grouping.

### Step G: Validate before publish
- Seat rows should never have negative or null `total_seats`.
- Results should never have null `candidate_rank`.
- Institutions in results must resolve to a canonical institution.
- Only active result documents may feed cutoffs.

---

## Chunk 5: How each PDF family maps into tables

### Family 1: Final seat matrices / stray seat matrices / special-stray seat matrices
- Target tables: `source_document`, `document_page_text`, `parsed_document_row`, `seat_snapshot`, `seat_snapshot_row`
- Key mapping:
  - `StateName` -> `institution.state_name` + `seat_snapshot_row.state_name_raw`
  - `InstituteType` -> `institution.institute_type_raw` when present
  - `Institute` -> `institution`, `institution_alias`, `seat_snapshot_row.institute_raw`
  - `Quota` -> `quota`
  - `Branch` -> `program`
  - `Category` -> `seat_category`
  - `TotalSeats` -> `seat_snapshot_row.total_seats`

### Family 2: Clear vacancy / virtual vacancy / newly added seats
- Use the same parser and target tables as seat matrices.
- Differentiate only by `seat_snapshot.snapshot_kind`.
- This preserves the timeline of how seats changed within a round instead of flattening everything into one number.

### Family 3: Final result / allotment PDFs
- Target tables: `source_document`, `document_page_text`, `parsed_document_row`, `allotment_result`, `allotment_cutoff`
- Key mapping:
  - `Rank` -> `allotment_result.candidate_rank`
  - `Allotted Quota` -> `quota`
  - `Allotted Institute` -> `institution` + `institution_alias`
  - `Course` -> `program`
  - `Alloted Category` -> `allotment_category`
  - `Candidate Category` -> `candidate_category`
  - `Remarks` -> `allotment_result.remarks`

### Family 4: Revision/clarification notices
- Target tables: `source_document`, `parsed_document_row`
- Business effect: mark the prior result document as `withdrawn` or `superseded` and block it from cutoff refreshes.

---

## Chunk 6: Function and view plan for application queries

### Required derived view

#### `vw_roundwise_cutoffs`
Readable view on top of `allotment_cutoff` joined to institution, program, quota, and round metadata.

Suggested columns:
- `round_key`
- `stage_label`
- `round_type`
- `is_after_stray`
- `institution_id`
- `mcc_institute_code`
- `institution_name`
- `state_name`
- `program_code`
- `quota_label`
- `allotment_category`
- `candidate_category`
- `opening_rank`
- `closing_rank`
- `allotment_count`

### Required SQL functions

#### `fn_normalize_candidate_category(p_input text)`
Purpose: map user input like `general`, `obc`, `ews`, `sc`, `st` into canonical category codes used by the warehouse.

#### `fn_available_options_by_rank(
  p_rank int,
  p_candidate_category text,
  p_program_codes text[] default null,
  p_round_keys text[] default null,
  p_include_after_stray boolean default true
)`
Purpose: main app function.

Return columns should include at least:
- `round_key`
- `stage_label`
- `institution_id`
- `mcc_institute_code`
- `institution_name`
- `state_name`
- `program_code`
- `quota_label`
- `allotment_category`
- `candidate_category`
- `opening_rank`
- `closing_rank`
- `available_for_rank boolean`

Core rule:
- Normalize the input category.
- Filter `vw_roundwise_cutoffs` to that candidate category.
- Return rows where `closing_rank >= p_rank`.
- Order by `stage_order`, then tighter closing rank, then institution.

#### `fn_roundwise_cutoff_history(
  p_institution_code int,
  p_program_code text,
  p_candidate_category text default null
)`
Purpose: show how the same college/program moved across rounds.

#### `sp_refresh_allotment_cutoffs()`
Purpose: rebuild `allotment_cutoff` from active result rows after every ETL load.

### Why the app query should use candidate category, not only seat category

The result PDFs contain both the allotted seat bucket and the candidate’s own category. That makes `candidate_category` the correct primary app filter. Example: an OBC candidate may get an open seat; if we only query seat category we will misrepresent what an OBC user could actually reach. Using cutoffs grouped by `candidate_category` keeps the answer aligned with the user’s question.

---

## Chunk 7: Implementation task breakdown

### Task 1: Create raw document and extraction layer

**Files:**
- Create: `sql/neetcounselling2025/001_raw_control.sql`
- Create: `etl/neetcounselling2025/extract_pdf_text.py`
- Create: `tests/neetcounselling2025/test_extract_pdf_text.py`

- [ ] Create `source_document`, `document_page_text`, and `parsed_document_row`.
- [ ] Implement extractor with `pdftotext -layout` first and OCR fallback.
- [ ] Add a regression test that confirms blank `pdftotext` output triggers OCR mode.
- [ ] Verify Task 1:
  - Run: `pytest tests/neetcounselling2025/test_extract_pdf_text.py -q`
  - Expected: all tests pass; at least one assertion proves OCR fallback was invoked on a scanned sample.

### Task 2: Create round and reference dimensions

**Files:**
- Create: `sql/neetcounselling2025/002_reference_dimensions.sql`
- Create: `etl/neetcounselling2025/normalize_dimensions.py`
- Create: `tests/neetcounselling2025/test_normalize_dimensions.py`

- [ ] Create `counselling_round`, `institution`, `institution_alias`, `program`, `quota`, `quota_alias`, `seat_category`, `allotment_category`, and `candidate_category`.
- [ ] Seed round keys for `R1`, `R2`, `R3`, `STRAY`, `SPECIAL_STRAY`, and `R5_BDS_BSCN`.
- [ ] Add normalization tests for institute-code extraction, quota normalization, and category normalization.
- [ ] Verify Task 2:
  - Run: `pytest tests/neetcounselling2025/test_normalize_dimensions.py -q`
  - Expected: all tests pass; fixture checks confirm all six round keys exist and category/quota normalization maps are populated.

### Task 3: Load seat, vacancy, and newly-added-seat snapshots

**Files:**
- Create: `sql/neetcounselling2025/003_seat_inventory.sql`
- Create: `etl/neetcounselling2025/load_seat_snapshots.py`
- Create: `tests/neetcounselling2025/test_load_seat_snapshots.py`

- [ ] Create `seat_snapshot` and `seat_snapshot_row`.
- [ ] Reuse one parser for final seat matrix, clear vacancy, virtual vacancy, newly added seats, stray seat matrix, and special-stray seat matrix.
- [ ] Preserve `snapshot_kind` and `snapshot_sequence` so round timelines are queryable later.
- [ ] Verify Task 3:
  - Run: `pytest tests/neetcounselling2025/test_load_seat_snapshots.py -q`
  - Expected: all tests pass; output confirms at least one row each for `FINAL_SEAT_MATRIX`, `CLEAR_VACANCY`, `STRAY_SEAT_MATRIX`, and `SPECIAL_STRAY_SEAT_MATRIX`.

### Task 4: Load allotment results and handle withdrawn files

**Files:**
- Create: `sql/neetcounselling2025/004_allotment_results.sql`
- Create: `etl/neetcounselling2025/load_allotment_results.py`
- Create: `etl/neetcounselling2025/apply_document_status_updates.py`
- Create: `tests/neetcounselling2025/test_load_allotment_results.py`

- [ ] Create `allotment_result`.
- [ ] Map result institute names to canonical institutions via aliases.
- [ ] Create `document_status_resolution` and implement deterministic notice-to-result mapping.
- [ ] Update `source_document.doc_status` only via `document_status_resolution` mappings when revision notices withdraw or supersede a result file.
- [ ] Verify Task 4:
  - Run: `pytest tests/neetcounselling2025/test_load_allotment_results.py -q`
  - Run: `psql -U learner -d learner_development -h neetprep-staging.cvvtorjqg7t7.ap-south-1.rds.amazonaws.com -c "select doc_status, count(*) from neetcounselling2025.source_document group by 1 order by 1;"`
  - Expected: tests pass; at least one non-`active` result document appears only when backed by a `document_status_resolution` row.

### Task 5: Build cutoffs and app-facing SQL functions

**Files:**
- Create: `sql/neetcounselling2025/005_cutoffs_and_functions.sql`
- Create: `tests/neetcounselling2025/test_cutoff_functions.py`

- [ ] Create `allotment_cutoff` and `vw_roundwise_cutoffs`.
- [ ] Implement `fn_normalize_candidate_category`, `fn_available_options_by_rank`, `fn_roundwise_cutoff_history`, and `sp_refresh_allotment_cutoffs()`.
- [ ] Add tests covering MBBS, BDS, B.Sc Nursing, stray, and special-stray rows.
- [ ] Verify Task 5:
  - Run: `pytest tests/neetcounselling2025/test_cutoff_functions.py -q`
  - Run: `psql -U learner -d learner_development -h neetprep-staging.cvvtorjqg7t7.ap-south-1.rds.amazonaws.com -c "select * from neetcounselling2025.fn_available_options_by_rank(70000, 'OBC', array['MBBS','BDS','BSCN'], null, true) limit 20;"`
  - Expected: tests pass; function returns non-empty, round-ordered rows with opening/closing rank fields.

### Task 6: Add end-to-end ingestion command and verification suite

**Files:**
- Create: `etl/neetcounselling2025/run_full_ingestion.py`
- Create: `tests/neetcounselling2025/test_end_to_end_ingestion.py`
- Create: `sql/neetcounselling2025/README.md`

- [ ] Build one command that loads documents, extracts text, parses rows, writes facts, and refreshes cutoffs.
- [ ] Add an end-to-end test using representative PDFs from Round 1, stray, special stray, and Round 5 BDS/B.Sc Nursing.
- [ ] Document rerun, idempotency, and superseded-document handling.
- [ ] Verify Task 6:
  - Run: `python etl/neetcounselling2025/run_full_ingestion.py --year 2025 --schema neetcounselling2025`
  - Run: `pytest tests/neetcounselling2025/test_end_to_end_ingestion.py -q`
  - Expected: ingestion completes without fatal errors; end-to-end tests pass; rerun does not duplicate facts (idempotent counts stable).

---

## Chunk 8: Validation checklist

- Validate that MBBS, BDS, and B.Sc Nursing each produce rows in both seat and allotment fact tables.
- Validate that `STRAY` and `SPECIAL_STRAY` both appear in `counselling_round` and in `allotment_cutoff`.
- Validate that scanned PDFs are marked `is_scanned = true` and are still represented in `source_document` even if they are not the primary data source.
- Validate that a withdrawn Round 2 result file does not contribute to `allotment_cutoff` after status update.
- Validate that `fn_available_options_by_rank()` returns sensible rows for:
  - one MBBS General rank
  - one MBBS OBC rank
  - one BDS rank in Round 5
  - one B.Sc Nursing rank
  - one after-stray/special-stray case

---

## Recommendation on source priority

For institution master creation, use this priority order:

1. Seat matrix / vacancy / newly added seat PDFs
2. Allotment result PDFs
3. Scanned college-list PDF (OCR/manual assist only)

This avoids making the whole pipeline depend on the weakest source document.

---

## Ready-for-build summary

The schema should be built around **institutions + programs + quotas + seat categories + rounds**, with **seat snapshots** and **allotment results** as the two core fact families. The app-facing layer should not query PDFs or raw rows directly; it should query `allotment_cutoff` through `fn_available_options_by_rank()` so a user’s rank and category can be answered quickly and consistently.
