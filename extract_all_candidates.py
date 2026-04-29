"""
Extract candidate data from NEET UG state counselling PDFs for Jharkhand and Tripura.

Processes 4 PDFs:
- Jharkhand 2024: JCECEB merit list (state ranks, not AI ranks)
- Tripura 2024: Merit list with AI ranks
- Jharkhand 2025: Merit list with AI ranks
- Tripura 2025: Qualified candidate list with AI ranks

Output: Generates insert_candidates_raw.sql with 13,105 INSERT statements.
"""
import re
import subprocess
from datetime import datetime

def parse_dob(text):
    for fmt in ['%d-%m-%Y', '%d/%m/%Y', '%d-%m-%y', '%d/%m/%y']:
        try:
            return datetime.strptime(text.strip(), fmt)
        except:
            pass
    return None

def get_age_on_date(dob, cutoff_date):
    age = cutoff_date.year - dob.year
    if (cutoff_date.month, cutoff_date.day) < (dob.month, dob.day):
        age -= 1
    return max(0, age)

def categorize(age):
    if age <= 17:
        return 'Fresher'
    elif age == 18:
        return 'Fresher_or_Dropper'
    elif age == 19:
        return 'Dropper_1y'
    elif age == 20:
        return 'Dropper_2y'
    elif age == 21:
        return 'Dropper_3y'
    else:
        return 'Dropper_3y+'

def read_pdf_lines(pdf_name):
    result = subprocess.run(
        ['pdftotext', '-layout', pdf_name, '-'],
        capture_output=True, text=True,
    )
    return result.stdout.split('\n')

def extract_2024_jharkhand():
    lines = read_pdf_lines('Jharkhand_NEET_6960bee4e1acda925837cf2bf1acef5a.pdf')
    candidates = []
    in_data = False

    for line in lines:
        if 'D.O.B.' in line and 'Gender' in line:
            in_data = True
            continue
        if not in_data:
            continue

        m = re.search(
            r'(\d{2}/\d{2}/\d{4})\s+(MALE|FEMALE)\s+(\d{3,4})\s+([\d.]+)\s+(\d+)\s+([A-Z\-/]+)',
            line,
        )
        if not m:
            continue

        dob_str = m.group(1)
        gender = m.group(2)
        marks = m.group(3)
        percentile = m.group(4)
        ai_rank = m.group(5)
        category = m.group(6).strip()

        parsed_dob = parse_dob(dob_str)
        if not parsed_dob:
            continue

        age = get_age_on_date(parsed_dob, datetime(2024, 12, 31))
        attempt_cat = categorize(age)

        candidates.append(
            {
                'state': 'Jharkhand',
                'year': 2024,
                'roll_no': '',
                'neet_app_no': '',
                'candidate_name': '',
                'gender': gender,
                'total_marks': marks,
                'percentile': percentile,
                'ai_rank': ai_rank,
                'category': category,
                'raw_dob': dob_str,
                'parsed_dob': parsed_dob,
                'age_at_cutoff': age,
                'attempt_category': attempt_cat,
            }
        )

    return candidates

def extract_2024_tripura():
    lines = read_pdf_lines(
        'Tripura_NEET_6b6353a89a0ba63a02668482e7eef6d5.pdf'
    )
    candidates = []

    for line in lines:
        match = re.search(
            r'(\d{2,4})\s+(\d+)\s+(\d{2}-\d{2}-\d{4})\s+(.*?)\s+(Yes|No)\s*$',
            line,
        )
        if not match:
            continue

        score = match.group(1)
        rank = match.group(2)
        dob_str = match.group(3)
        category_raw = match.group(4).strip()
        ph = match.group(5)

        parsed_dob = parse_dob(dob_str)
        if not parsed_dob:
            continue

        age = get_age_on_date(parsed_dob, datetime(2024, 12, 31))
        attempt_cat = categorize(age)

        # Normalize category
        if 'General' in category_raw or 'Gen-EWS' in category_raw:
            category = 'GENERAL'
        elif 'OBC' in category_raw:
            category = 'OBC'
        elif 'SC' in category_raw:
            category = 'SC'
        elif 'ST' in category_raw:
            category = 'ST'
        else:
            category = ''

        candidates.append(
            {
                'state': 'Tripura',
                'year': 2024,
                'roll_no': '',
                'neet_app_no': '',
                'candidate_name': '',
                'gender': '',
                'total_marks': score,
                'percentile': '0',
                'ai_rank': rank,
                'category': category,
                'raw_dob': dob_str,
                'parsed_dob': parsed_dob,
                'age_at_cutoff': age,
                'attempt_category': attempt_cat,
            }
        )

    return candidates

def extract_2025_jharkhand():
    lines = read_pdf_lines('Jharkhand_NEET_2025_Merit_list_1756.pdf')
    candidates = []

    for line in lines:
        m = re.search(
            r'(MALE|FEMALE)\s+(\d{2}/\d{2}/\d{4})\s+(\d{3,4})\s+([\d.]+)\s+(\d+)\s+([A-Z\-/]+)',
            line,
        )
        if not m:
            continue

        gender = m.group(1)
        dob_str = m.group(2)
        marks = m.group(3)
        percentile = m.group(4)
        ai_rank = m.group(5)
        category = m.group(6).strip()

        parsed_dob = parse_dob(dob_str)
        if not parsed_dob:
            continue

        age = get_age_on_date(parsed_dob, datetime(2025, 12, 31))
        attempt_cat = categorize(age)

        candidates.append(
            {
                'state': 'Jharkhand',
                'year': 2025,
                'roll_no': '',
                'neet_app_no': '',
                'candidate_name': '',
                'gender': gender,
                'total_marks': marks,
                'percentile': percentile,
                'ai_rank': ai_rank,
                'category': category,
                'raw_dob': dob_str,
                'parsed_dob': parsed_dob,
                'age_at_cutoff': age,
                'attempt_category': attempt_cat,
            }
        )

    return candidates

def extract_2025_tripura():
    lines = read_pdf_lines(
        'Tripura NEET-UG 2025 Qualified Candidate List.pdf'
    )
    candidates = []

    for line in lines:
        m = re.search(
            r'(\d{2}-\d{2}-\d{4})\s+(Male|Female)\s+([^0-9]+?)\s+(Yes|No|yes|no)\s+(\d{3,4})\s+([\d.]+)\s+(\d+)',
            line,
            re.IGNORECASE,
        )
        if not m:
            continue

        dob_str = m.group(1)
        gender = m.group(2).upper()
        category_raw = m.group(3).strip()
        marks = m.group(5)
        percentile = m.group(6)
        ai_rank = m.group(7)

        parsed_dob = parse_dob(dob_str)
        if not parsed_dob:
            continue

        age = get_age_on_date(parsed_dob, datetime(2025, 12, 31))
        attempt_cat = categorize(age)

        cat = category_raw
        if 'General' in category_raw or 'Gen' in category_raw:
            cat = 'GENERAL'
        elif 'OBC' in category_raw:
            cat = 'OBC'
        elif 'SC' in category_raw:
            cat = 'SC'
        elif 'ST' in category_raw:
            cat = 'ST'

        candidates.append(
            {
                'state': 'Tripura',
                'year': 2025,
                'roll_no': '',
                'neet_app_no': '',
                'candidate_name': '',
                'gender': gender,
                'total_marks': marks,
                'percentile': percentile,
                'ai_rank': ai_rank,
                'category': cat,
                'raw_dob': dob_str,
                'parsed_dob': parsed_dob,
                'age_at_cutoff': age,
                'attempt_category': attempt_cat,
            }
        )

    return candidates

def generate_sql(all_candidates):
    if not all_candidates:
        print('No candidates to insert')
        return

    with open('insert_candidates_raw.sql', 'w') as f:
        f.write('BEGIN;\n')
        for cand in all_candidates:
            parsed_date = (
                cand['parsed_dob'].strftime('%Y-%m-%d')
                if cand['parsed_dob'] else None
            )
            f.write(
                f"INSERT INTO neetstatecouncelling.candidate_raw "
                f"(state, year, roll_no, neet_app_no, candidate_name, gender, total_marks, percentile, ai_rank, category, raw_dob, parsed_dob, age_at_cutoff, attempt_category) "
                f"VALUES ('{cand['state']}', {cand['year']}, NULL, NULL, NULL, "
                f"'{cand['gender']}', {cand['total_marks']}, {cand['percentile']}, "
                f"{cand['ai_rank']}, '{cand['category']}', '{cand['raw_dob']}', "
                f"'{parsed_date}', {cand['age_at_cutoff']}, '{cand['attempt_category']}') "
                f"ON CONFLICT (state, year, roll_no, neet_app_no) DO UPDATE SET "
                f"gender = EXCLUDED.gender, total_marks = EXCLUDED.total_marks, percentile = EXCLUDED.percentile, "
                f"ai_rank = EXCLUDED.ai_rank, category = EXCLUDED.category, raw_dob = EXCLUDED.raw_dob, "
                f"parsed_dob = EXCLUDED.parsed_dob, age_at_cutoff = EXCLUDED.age_at_cutoff, attempt_category = EXCLUDED.attempt_category;\n"
            )
        f.write('COMMIT;\n')
    print(
        f'SQL written to insert_candidates_raw.sql ({len(all_candidates)} inserts)'
    )


if __name__ == '__main__':
    results = {
        'jh24': extract_2024_jharkhand(),
        'tr24': extract_2024_tripura(),
        'jh25': extract_2025_jharkhand(),
        'tr25': extract_2025_tripura(),
    }
    for key, val in results.items():
        print(f'{key}: {len(val)} candidates')

    all_candidates = []
    for val in results.values():
        all_candidates.extend(val)
    print(f'\nTotal candidates extracted: {len(all_candidates)}')
    generate_sql(all_candidates)
