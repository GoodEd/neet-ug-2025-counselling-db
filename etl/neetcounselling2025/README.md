# Tabula Extraction + Ingestion

This module provides **table-only** extraction using Tabula and ingestion into PostgreSQL staging.

## Prerequisites

- Java installed (`java -version` works)
- Python virtualenv created at `.venv`

Install dependencies:

```bash
python -m venv .venv
.venv/bin/pip install tabula-py pandas sqlalchemy psycopg2-binary
```

## 1) Sample extraction for admitted-joined PDF

```bash
.venv/bin/python etl/neetcounselling2025/run_admitted_joined_tabula.py --sample
```

Output:
- `.sisyphus/extracts/tabula_sample_admitted_joined.json`

## 2) Full extraction + ingest

Set database URL (example):

```bash
export DATABASE_URL='postgresql+psycopg2://learner:YOUR_PASSWORD@neetprep-staging.cvvtorjqg7t7.ap-south-1.rds.amazonaws.com/learner_development'
```

Run:

```bash
.venv/bin/python etl/neetcounselling2025/run_admitted_joined_tabula.py --ingest
```

### Chunked full-file ingest (recommended for large PDFs)

```bash
export DATABASE_URL='postgresql+psycopg2://learner:YOUR_PASSWORD@neetprep-staging.cvvtorjqg7t7.ap-south-1.rds.amazonaws.com/learner_development'
.venv/bin/python etl/neetcounselling2025/run_admitted_joined_tabula.py --ingest --chunked --chunk-size 10
```

This runs page windows sequentially (e.g., `1-10`, `11-20`, …) to avoid long single-run timeouts.

Completed windows are recorded in:
- `neetcounselling2025.tabula_ingestion_windows`

If a chunked run is interrupted, rerunning the same command will skip already completed windows and continue with the remaining windows.

### Restarting older interrupted runs

Older partial runs created before `tabula_ingestion_windows` existed should be cleaned up and restarted for the affected PDF, because those rows do not have resumable window checkpoints.

Rows are inserted into:
- `neetcounselling2025.tabula_extracted_rows`

## Direct generic runner

```bash
.venv/bin/python etl/neetcounselling2025/tabula_extract_ingest.py \
  --pdf "/absolute/path/to/file.pdf" \
  --mode lattice \
  --pages all \
  --sample --sample-out .sisyphus/extracts/tabula_sample.json
```

For ingestion:

```bash
.venv/bin/python etl/neetcounselling2025/tabula_extract_ingest.py \
  --pdf "/absolute/path/to/file.pdf" \
  --mode lattice \
  --pages all \
  --ingest \
  --db-url "$DATABASE_URL" \
  --schema neetcounselling2025
```

## Notes

- Extraction is blocked if Tabula returns no valid table rows.
- This enforces the table-only requirement.
- Try `--mode stream` if `lattice` returns sparse/invalid tables.
