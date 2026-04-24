# NEETCounselling2025 Normalized Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the normalized `neetcounselling2025` schema and ETL needed to serve rank/category queries from final allotment data first, then extend it with final seat-matrix data.

**Architecture:** Keep the existing Tabula staging tables as the raw ingestion layer, then add a normalized relational layer with dimensions (`source_document`, `counselling_round`, `institution`, `institution_alias`, `program`, `quota`, `result_category`) plus fact tables (`allotment_result_effective`, `final_seat_matrix_row`) and a derived aggregate table (`round_cutoff`). Implement allotment normalization first because it unlocks the core application query, then load seat-matrix facts as the second slice.

**Tech Stack:** PostgreSQL, Python 3, SQLAlchemy, Tabula staging tables, pytest.

---

## Chunk 1: Normalized schema foundation

### Task 1: Add normalized schema migration

**Files:**
- Create: `sql/neetcounselling2025/001_normalized_foundation.sql`
- Modify: `sql/neetcounselling2025/000_tabula_staging.sql`
- Test: live DB schema inspection

- [ ] **Step 1: Write the failing schema expectation**

Document the required new tables and keys:
- `source_document`
- `counselling_round`
- `institution`
- `institution_alias`
- `program`
- `quota`
- `result_category`
- `allotment_result_effective`
- `round_cutoff`

- [ ] **Step 2: Verify the tables do not exist yet**

Run:

```bash
.venv/bin/python -c "from sqlalchemy import create_engine,text; engine=create_engine('$DATABASE_URL'); conn=engine.connect(); rows=conn.execute(text(\"select table_name from information_schema.tables where table_schema='neetcounselling2025' order by table_name\")).fetchall(); print([r[0] for r in rows]); conn.close()"
```

Expected: only staging/checkpoint tables exist.

- [ ] **Step 3: Write the migration**

Create normalized tables with:
- primary keys
- foreign keys
- uniqueness on natural dimensions where safe
- indexes for rank/category/round lookups

- [ ] **Step 4: Apply migration and verify it passes**

Run:

```bash
.venv/bin/python -c "from sqlalchemy import create_engine,text; engine=create_engine('$DATABASE_URL'); sql=open('sql/neetcounselling2025/001_normalized_foundation.sql').read(); conn=engine.connect(); trans=conn.begin(); conn.execute(text(sql)); trans.commit(); conn.close()"
```

Expected: success with no SQL errors.

- [ ] **Step 5: Verify table and FK creation**

Run metadata checks and confirm all normalized tables exist.

---

## Chunk 2: Round/program seeds and source document registry

### Task 2: Seed dimensions that do not depend on staged row parsing

**Files:**
- Modify: `sql/neetcounselling2025/001_normalized_foundation.sql`
- Create: `etl/neetcounselling2025/normalized_loader.py`
- Test: live DB row checks

- [ ] **Step 1: Write the failing seed expectation**

Expected seeded rows:
- rounds: `R1`, `R2`, `R3`, `STRAY`, `SPECIAL_STRAY`, `R5_BDS_BSCN`
- programs: `MBBS`, `BDS`, `BSCN`

- [ ] **Step 2: Verify seeds are currently absent**

Run a select against `counselling_round` and `program`.

- [ ] **Step 3: Implement seeding logic**

Add idempotent inserts for rounds and programs.

- [ ] **Step 4: Build source-document registration helper**

In `normalized_loader.py`, add functions to:
- map in-scope PDFs to `doc_type` + `round_key`
- compute sha256
- upsert `source_document`

- [ ] **Step 5: Verify seeds and source documents**

Check that rounds/programs exist and in-scope PDFs are registered.

---

## Chunk 3: Allotment normalization (first query-serving slice)

### Task 3: Load institutions, quotas, categories, and normalized allotment facts from staged rows

**Files:**
- Modify: `etl/neetcounselling2025/tabula_extract_ingest.py`
- Create: `etl/neetcounselling2025/normalized_loader.py`
- Create: `tests/neetcounselling2025/test_normalized_loader.py`
- Test: `tests/neetcounselling2025/test_normalized_loader.py`

- [ ] **Step 1: Write failing parser/normalizer tests**

Add tests for:
- raw institute text → canonical institution name + alias
- raw course text → `MBBS` / `BDS` / `BSCN`
- raw quota text → normalized quota dimension row
- raw category text → normalized `result_category`

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
.venv/bin/python -m pytest tests/neetcounselling2025/test_normalized_loader.py -v
```

Expected: failure due to missing loader functions.

- [ ] **Step 3: Implement minimal normalization helpers**

Build helpers for:
- institution normalization
- program detection
- quota normalization
- result-category normalization
- document-to-round mapping

- [ ] **Step 4: Implement allotment fact loading**

Read staged rows from `tabula_extracted_rows` for final result PDFs and populate:
- `institution`
- `institution_alias`
- `quota`
- `result_category`
- `allotment_result_effective`

- [ ] **Step 5: Re-run tests and verify pass**

Run the targeted test file and confirm green.

- [ ] **Step 6: Verify live DB population**

Run row-count checks for:
- `source_document`
- `institution`
- `institution_alias`
- `quota`
- `result_category`
- `allotment_result_effective`

---

## Chunk 4: Cutoff aggregation and app query function

### Task 4: Build `round_cutoff` and rank/category query function

**Files:**
- Modify: `sql/neetcounselling2025/001_normalized_foundation.sql`
- Modify: `etl/neetcounselling2025/normalized_loader.py`
- Create: `tests/neetcounselling2025/test_cutoff_queries.py`
- Test: `tests/neetcounselling2025/test_cutoff_queries.py`

- [ ] **Step 1: Write failing tests / query expectations**

Cover:
- cutoff opening/closing aggregation
- rank/category query returning rows for a known sample

- [ ] **Step 2: Verify the tests fail**

Run:

```bash
.venv/bin/python -m pytest tests/neetcounselling2025/test_cutoff_queries.py -v
```

- [ ] **Step 3: Implement cutoff refresh SQL**

Create SQL/functionality to rebuild `round_cutoff` from `allotment_result_effective`.

- [ ] **Step 4: Implement rank/category query function**

Add `fn_available_options_by_rank(...)` that filters by:
- candidate rank
- candidate category
- optional program/round filters

- [ ] **Step 5: Verify against live DB**

Run sample queries and confirm rows return.

---

## Chunk 5: Seat matrix normalization (second slice)

### Task 5: Add seat categories and final seat-matrix fact loading

**Files:**
- Modify: `sql/neetcounselling2025/001_normalized_foundation.sql`
- Modify: `etl/neetcounselling2025/normalized_loader.py`
- Create: `tests/neetcounselling2025/test_seat_matrix_loader.py`
- Test: `tests/neetcounselling2025/test_seat_matrix_loader.py`

- [ ] **Step 1: Write failing seat-matrix normalization tests**

Cover:
- seat category parsing
- row grain `(document, round, institution, program, quota, seat_category)`

- [ ] **Step 2: Verify tests fail**

Run:

```bash
.venv/bin/python -m pytest tests/neetcounselling2025/test_seat_matrix_loader.py -v
```

- [ ] **Step 3: Implement `seat_category` and `final_seat_matrix_row` loading**

Populate final seat-matrix facts from staged rows for in-scope seat PDFs.

- [ ] **Step 4: Verify live DB counts**

Confirm `seat_category` and `final_seat_matrix_row` are populated.

---

## Chunk 6: Final verification

### Task 6: Verify the end-to-end normalized layer

**Files:**
- Modify: `etl/neetcounselling2025/README.md`
- Test: schema checks, test suite, sample SQL queries

- [ ] **Step 1: Run all targeted tests**

Run:

```bash
.venv/bin/python -m pytest tests/neetcounselling2025 -v
```

- [ ] **Step 2: Verify populated tables**

Confirm row counts for all normalized tables.

- [ ] **Step 3: Verify sample app query**

Run the rank/category query for at least one sample rank in each program family.

- [ ] **Step 4: Update README**

Document:
- schema layers
- loader commands
- refresh/query workflow
