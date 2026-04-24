# NEET UG 2025 Ingestion Plan (V2: Final Seat Matrix + Final Allotment Only)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest only final-seat-matrix and final-allotment data into PostgreSQL schema `neetcounselling2025` so the app can answer: for rank X and candidate category Y, which colleges/programs/rounds were available.

**Hard Scope Decisions (User-Directed):**
- Include only:
  - Final Seat Matrix
  - Final Allotment Result
- Exclude from ingestion logic:
  - Vacancy files (clear/virtual)
  - Newly added seat files
  - Schedules
  - Weeding/Admitted-Joined notices
- Extraction must be **table-first**, with row/column integrity.
- Prefer **Tabula** for extraction (not plain free-text extraction workflow).

---

## 1) Source PDF Mapping (Final-Only)

### 1.1 Round mapping

| Stage | Final Allotment PDF | Final Seat Matrix PDF |
|---|---|---|
| Round 1–3 | **[PDF 1]** (user-preferred source for all allotment till Round 3) | Round-specific final seat matrix where available |
| Stray | `Final Allotment Result for Stray Vacacy Round UG 2025 - 2025111596488171.pdf` | `SEAT MATRIX STRAY ROUND UG 2025 - 202511061324228354.pdf` |
| Special Stray (After Stray) | `Final Result for Special Stray Round of UG counselling 2025 - 202512231822103663.pdf` | `SEAT MATRIX UG MBBS SPECIAL STRAY ROUND UG 2025 - 20251219617527714.pdf` |
| Round 5 (BDS/B.Sc Nursing) | `Final Result of UG Counselling Round 5 for BDS ⁄ B.Sc Nursing 2025 - 202601031185987538.pdf` | `Seat Matrix for NEET UG (BDS B.Sc Nursing) -2025 Round 5 Counselling - 2026010176307210.pdf` |

### 1.2 Explicitly ignored files for this implementation
- `CLEAR VACANCY ROUND 5 (BDS B.Sc Nursing) – UG COUNSELLING 2025 - 20251209696683132.pdf`
- `Schedule for NEET-UG Round 5 & 6 Schedule 2025 for BDS ⁄ B.sc Nursing - 202512091840430664.pdf`
- `SCHEDULE OF ROUND 5 & ROUND 6 OF UG COUNSELLING 2025 FOR BDS⁄B.SC (NURSING)- 202512081633163473.pdf`
- `Notice for weeding out of candidates dated 15.11.2025 - 202511151570160169.pdf`

### 1.3 Required user-facing limitation note
`ERROR: Cannot read "ADMITTED JOINED CANDIDATES LIST UPTO ROUND 3 UG COUNSELLING 2025 - 202511031508909973.pdf" (this model does not support pdf input).`

---

## 2) Extraction Strategy (Tabula-First, Table-Only)

## 2.1 Primary extraction
Use Tabula (Java CLI) and only accept structured table output.

Example command:

```bash
java -jar tabula.jar \
  --pages all \
  --lattice \
  --format JSON \
  --outfile /tmp/output.json \
  "/path/to/input.pdf"
```

When lattice fails for a document, retry with stream mode:

```bash
java -jar tabula.jar \
  --pages all \
  --stream \
  --format JSON \
  --outfile /tmp/output.json \
  "/path/to/input.pdf"
```

Use `--area` / `--columns` when headers/footers or merged cells break alignment.

## 2.2 Integrity gates (mandatory)
Reject extraction output if any fails:

1. **Column count gate:** data rows must match expected header count.
2. **Rank gate (result PDFs):** `Rank` must parse as integer on valid rows.
3. **Seat gate (seat matrix PDFs):** `TotalSeats` must parse as non-negative integer.
4. **Required headers gate:**
   - Seat matrix: `StateName`, `Institute`, `Quota`, `Branch`, `Category`, `TotalSeats`
   - Result: `Rank`, `Allotted Quota`, `Allotted Institute`, `Course`, `Alloted Category`, `Candidate Category`, `Remarks`

No non-tabular fallback path should write production facts.

---

## 3) Minimal Robust Schema (`neetcounselling2025`)

## 3.1 Control table

### `source_document`
- `document_id bigserial primary key`
- `file_name text not null`
- `absolute_path text not null unique`
- `sha256 text not null unique`
- `doc_type text not null` (`final_seat_matrix`, `final_allotment_result`)
- `round_key text not null` (`R1`,`R2`,`R3`,`STRAY`,`SPECIAL_STRAY`,`R5_BDS_BSCN`)
- `published_on date null`
- `is_active boolean not null default true`
- `notes text null`
- `created_at timestamptz not null default now()`

## 3.2 Dimensions

### `counselling_round`
- `round_id bigserial primary key`
- `round_key text unique not null`
- `stage_order int not null`
- `round_type text not null` (`REGULAR`,`STRAY`,`SPECIAL_STRAY`)
- `is_after_stray boolean not null default false`

### `institution`
- `institution_id bigserial primary key`
- `mcc_institute_code int null unique`
- `institution_name text not null`
- `institution_name_normalized text not null`
- `state_name text not null`

### `institution_alias`
- `institution_alias_id bigserial primary key`
- `institution_id bigint not null references institution(institution_id)`
- `alias_raw text not null`
- `alias_normalized text not null`
- `source_document_id bigint null references source_document(document_id)`

### `program`
- `program_id smallserial primary key`
- `program_code text unique not null` (`MBBS`,`BDS`,`BSCN`)
- `program_label text not null`

### `quota`
- `quota_id bigserial primary key`
- `quota_label text unique not null`
- `quota_code text null`

### `seat_category`
- `seat_category_id bigserial primary key`
- `raw_label text unique not null` (e.g. `BC NO`, `OP PH`)
- `normalized_code text not null`
- `is_pwd boolean not null default false`

### `result_category`
- `result_category_id bigserial primary key`
- `raw_label text unique not null` (e.g. `Open`, `OBC`, `EWS`, `SC`, `ST`)
- `normalized_code text not null`
- `is_pwd boolean not null default false`

## 3.3 Facts

### `final_seat_matrix_row`
- `final_seat_matrix_row_id bigserial primary key`
- `source_document_id bigint not null references source_document(document_id)`
- `round_id bigint not null references counselling_round(round_id)`
- `institution_id bigint not null references institution(institution_id)`
- `program_id smallint not null references program(program_id)`
- `quota_id bigint not null references quota(quota_id)`
- `seat_category_id bigint not null references seat_category(seat_category_id)`
- `total_seats int not null`

### `allotment_result_effective`
- `allotment_result_effective_id bigserial primary key`
- `source_document_id bigint not null references source_document(document_id)`
- `round_id bigint not null references counselling_round(round_id)`
- `candidate_rank int not null`
- `institution_id bigint not null references institution(institution_id)`
- `program_id smallint not null references program(program_id)`
- `quota_id bigint not null references quota(quota_id)`
- `allotted_result_category_id bigint not null references result_category(result_category_id)`
- `candidate_result_category_id bigint not null references result_category(result_category_id)`
- `remarks text null`

### `round_cutoff`
- `round_cutoff_id bigserial primary key`
- `round_id bigint not null references counselling_round(round_id)`
- `institution_id bigint not null references institution(institution_id)`
- `program_id smallint not null references program(program_id)`
- `quota_id bigint not null references quota(quota_id)`
- `allotted_result_category_id bigint not null references result_category(result_category_id)`
- `candidate_result_category_id bigint not null references result_category(result_category_id)`
- `opening_rank int not null`
- `closing_rank int not null`
- `allotment_count int not null`

---

## 4) Functions for App Query

### `fn_normalize_candidate_category(p_input text)`
Normalizes app input category text to canonical category code.

### `sp_refresh_round_cutoffs()`
Rebuilds `round_cutoff` from `allotment_result_effective`.

### `fn_available_options_by_rank(
  p_rank int,
  p_candidate_category text,
  p_program_codes text[] default null,
  p_round_keys text[] default null,
  p_include_after_stray boolean default true
)`

Returns round-wise options where `closing_rank >= p_rank`, including:
- round/stage
- institution
- program
- quota
- allotted category
- candidate category
- opening/closing rank

---

## 5) Parsing Rules by Round Family

1. **Round 1 / Stray / Special Stray / Round 5 BDS-BScN**
   - Use standard final-result table parser.

2. **Round 2 / Round 3**
   - If result format includes transition/upgrade columns, parser must emit only **effective allotment rows for that round**.
   - Do not duplicate prior-round carry-forward rows as fresh allotments in the current round.

---

## 6) Implementation Tasks

### Task A: Source registry + Tabula extraction
- [ ] Build `source_document` migration.
- [ ] Build Tabula extraction runner (lattice first, stream retry).
- [ ] Persist parsed table rows only if integrity gates pass.

### Task B: Dimensions and round seeds
- [ ] Create dimensions listed in section 3.2.
- [ ] Seed rounds: `R1`,`R2`,`R3`,`STRAY`,`SPECIAL_STRAY`,`R5_BDS_BSCN`.

### Task C: Load final seat matrix facts
- [ ] Parse and load only final seat matrix PDFs in scope.

### Task D: Load final allotment facts
- [ ] Parse and load only final allotment PDFs in scope.
- [ ] Apply Round-2/3 effective-allotment parser rule.

### Task E: Build cutoffs + functions
- [ ] Build `round_cutoff`.
- [ ] Implement `fn_normalize_candidate_category`, `sp_refresh_round_cutoffs`, `fn_available_options_by_rank`.

---

## 7) Verification Checklist

- [ ] MBBS appears in seat + allotment facts.
- [ ] BDS appears in seat + allotment facts.
- [ ] B.Sc Nursing appears in seat + allotment facts.
- [ ] `STRAY`, `SPECIAL_STRAY`, and `R5_BDS_BSCN` have populated cutoff rows.
- [ ] `fn_available_options_by_rank` returns expected rows for at least one sample rank in each program family.

---

## 8) Reviewer Notes

- This V2 intentionally does **not** reconstruct dynamic seat availability from vacancy/newly-added files.
- Output semantics are: **final realized allotment history by rank/category**, plus final seat-matrix context where present.
