#!/usr/bin/env python3
import json, re, subprocess
from pathlib import Path
from difflib import SequenceMatcher
from collections import defaultdict

import psycopg2

ROOT = Path(__file__).resolve().parents[2]
DB_URI = "postgresql://learner:***@neetprep-staging.cvvtorjqg7t7.ap-south-1.rds.amazonaws.com:5432/learner_development"
SCHEMA = "neetcounselling2025"

def get_mcc_map():
    venv = ROOT / '.venv/bin/python'
    script = ROOT / 'etl/neetcounselling2025/tabula_extract_ingest.py'
    out = ROOT / '.sisyphus/extracts/tabula_newly_added_full.json'
    pdf = ROOT / 'Newly Added Seats Round 2 (MBBS BDS) — UG Counselling 2025 - 20250905348194385.pdf'
    
    result = subprocess.run(
        [str(venv), str(script), '--pdf', str(pdf), '--mode', 'lattice', '--pages', 'all', '--sample', '--sample-out', str(out)],
        capture_output=True, text=True, cwd=ROOT
    )
    if result.returncode != 0:
        raise RuntimeError(f"Tabula extraction failed: {result.stderr[:2000]}")
    if not out.exists():
        raise FileNotFoundError(f"Expected output file missing: {out}")
    with open(out) as f:
        data = json.load(f)
    mcc_map = {}
    for table in data:
        for row in table['rows']:
            inst = row.get('Unnamed: 0', '')
            m = re.search(r'\((\d{6})\)', inst)
            if m and inst not in ('Institute', ''):
                code = m.group(1)
                clean = re.sub(r'\(\d{6}\)', '', inst).strip().rstrip(',')
                mcc_map[clean] = code
    return mcc_map

def main():
    mcc_map = get_mcc_map()
    print(f"Institutions found in PDF: {len(mcc_map)}")

    with psycopg2.connect(DB_URI) as conn:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT DISTINCT i.institution_id, i.institution_name
                FROM {SCHEMA}.allotment_result_effective ae
                JOIN {SCHEMA}.institution i ON ae.institution_id = i.institution_id
                WHERE 'MISSING_MCC_CODE' = ANY(ae.data_quality_flags)
            """)
            missing = {row[0]: row[1] for row in cur.fetchall()}
        print(f"Currently missing MCC: {len(missing)} institutions")

        updates = []
        for bad_id, bad_name in missing.items():
            best_match = None
            best_score = 0
            bad_norm = bad_name.lower().replace(' ', '').replace(',', '')
            for clean_name, code in mcc_map.items():
                clean_norm = clean_name.lower().replace(' ', '').replace(',', '')
                if bad_norm in clean_norm or clean_norm in bad_norm:
                    score = SequenceMatcher(None, bad_name, clean_name).ratio()
                    if clean_norm == bad_norm:
                        score = 1.0
                    if score > best_score:
                        best_score = score
                        best_match = (bad_id, bad_name, code, clean_name)
            if best_match and best_score >= 0.6:
                updates.append(best_match)

        if not updates:
            print("No matches found.")
            return

        print(f"Matching institutions: {len(updates)}")
        with conn.cursor() as cur:
            for bad_id, bad_name, code, clean in updates:
                if not code.isdigit():
                    print(f"Skipping non-numeric MCC code for {bad_name}: {code}")
                    continue
                cur.execute(f"""
                    UPDATE {SCHEMA}.institution
                    SET mcc_institute_code = %s
                    WHERE institution_id = %s AND mcc_institute_code IS NULL
                """, (int(code), bad_id))
            conn.commit()
        print(f"Updated {len(updates)} institutions with MCC codes.")

if __name__ == '__main__':
    main()
