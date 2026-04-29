# NEET State Counselling Analysis

Analysis of NEET UG state counselling merit lists for Jharkhand and Tripura (2024 and 2025) to understand age demographics, dropper vs fresher ratios, and top-ranker performance patterns.

## Data Sources

| State | Year | PDF | Records | Notes |
|-------|------|-----|---------|-------|
| Jharkhand | 2024 | `Jharkhand_NEET_6960bee4e1acda925837cf2bf1acef5a.pdf` | 2,662 | JCECEB state ranks (not AI ranks) |
| Tripura | 2024 | `Tripura_NEET_6b6353a89a0ba63a02668482e7eef6d5.pdf` | 5,016 | AI ranks available |
| Jharkhand | 2025 | `Jharkhand_NEET_2025_Merit_list_1756.pdf` | 3,171 | AI ranks available |
| Tripura | 2025 | `Tripura NEET-UG 2025 Qualified Candidate List.pdf` | 2,256 | AI ranks available |

**Total**: 13,105 candidates in `neetstatecouncelling.candidate_raw`

## Age Classification

Age computed at 31st December of the counselling year:
- **Fresher** (<= 17): First attempt, typically current year student
- **Fresher_or_Dropper** (18): Ambiguous - could be either
- **Dropper_1y** (19): 1 year drop
- **Dropper_2y** (20): 2 year drop
- **Dropper_3y** (21): 3 year drop
- **Dropper_3y+** (>= 22): 3+ year drop

For analysis, grouped as:
- **<= 19**: Freshers + up to 1 year drop (younger cohort)
- **> 19**: 2+ year droppers (older cohort)

## Key Findings

### Overall Age Distribution (All Candidates)

| State | Year | <= 19 | > 19 | Total |
|-------|------|-------|------|-------|
| Jharkhand | 2025 | 37.97% | 62.03% | 3,171 |
| Jharkhand | 2024 | 36.21% | 63.79% | 2,662 |
| Tripura | 2025 | 58.73% | 41.27% | 2,256 |
| Tripura | 2024 | 71.17% | 28.83% | 5,016 |

### Top 100k AI Ranks Age Distribution

| State | Year | <= 19 in Top 100k | > 19 in Top 100k | Total in Top 100k |
|-------|------|-------------------|-------------------|-------------------|
| Jharkhand | 2025 | 41.13% | 58.87% | 1,026 |
| Jharkhand | 2024 | 37.28% | 62.72% | 1,148 |
| Tripura | 2025 | 65.56% | 34.44% | 90 |
| Tripura | 2024 | 58.82% | 41.18% | 102 |

### Observations

1. **Tripura has significantly younger candidates**: 59-71% are <= 19 vs Jharkhand's 36-38%
2. **Jharkhand has more droppers**: 62-64% are > 19 (repeaters/droppers)
3. **Top 100k representation slightly favors younger candidates**: In both states, the <= 19 group is slightly over-represented in top ranks compared to their overall share
4. **Tripura's pool aged from 2024 to 2025**: % of <= 19 dropped from 71% to 59%, while Jharkhand remained stable at ~37%
5. **Jharkhand 2024 uses state ranks**: JCECEB ranks start at 200005 and cannot be directly compared with AI ranks

## Files

### SQL Queries

| File | Purpose |
|------|---------|
| `age_dist_top50k.sql` | Age distribution for top 50k AI ranks (2025 only) |
| `age_dist_top100k.sql` | Age distribution for top 100k AI ranks with percentage of total merit list (all years) |
| `age_dist_top100k_all_years.sql` | Age distribution for top 100k AI ranks (all years) |
| `age_dist_all_years.sql` | Age distribution for all ranks (all years) |
| `age_dist_by_age_group_total.sql` | Age group distribution for total students by state and year |
| `final_age_table.sql` | Combined analysis: total students + top 100k breakdown by age group |

### Python Scripts

| File | Purpose |
|------|---------|
| `extract_all_candidates.py` | Extracts candidate data from all 4 PDFs using pdftotext + regex patterns. Generates `insert_candidates_raw.sql` |
| `insert_candidates_raw.sql` | Generated SQL with 13,105 INSERT statements for candidate_raw table |
| `test_jh24_regex.py` | Regex validation helper for Jharkhand 2024 PDF extraction |

### Database

| File | Purpose |
|------|---------|
| `dumps/neetstatecouncelling.dump` | PostgreSQL custom-format dump of neetstatecouncelling schema (214KB) |

## Running the Analysis

```bash
# Restore the schema
pg_restore -h <host> -U <user> -d <database> -n neetstatecouncelling dumps/neetstatecouncelling.dump

# Run analysis queries
psql -h <host> -U <user> -d <database> -f age_dist_by_age_group_total.sql
psql -h <host> -U <user> -d <database> -f final_age_table.sql
```

## Schema

```sql
CREATE TABLE neetstatecouncelling.candidate_raw (
    id SERIAL PRIMARY KEY,
    state VARCHAR(50),
    year INTEGER,
    roll_no VARCHAR(50),
    neet_app_no VARCHAR(50),
    candidate_name VARCHAR(255),
    gender VARCHAR(10),
    total_marks INTEGER,
    percentile NUMERIC(10,7),
    ai_rank BIGINT,
    category VARCHAR(50),
    raw_dob VARCHAR(20),
    parsed_dob DATE,
    age_at_cutoff INTEGER,
    attempt_category VARCHAR(50),
    UNIQUE(state, year, roll_no, neet_app_no)
);
```
