import re
import subprocess
from datetime import datetime
from collections import Counter

def parse_dob(text):
    for fmt in ['%d-%m-%Y', '%d/%m/%Y', '%d-%m-%y']:
        try:
            return datetime.strptime(text, fmt)
        except:
            pass
    return None

def get_age_on_date(dob, cutoff_date):
    age = cutoff_date.year - dob.year
    if (cutoff_date.month, cutoff_date.day) < (dob.month, dob.day):
        age -= 1
    return age

def categorize(age):
    if age <= 17:
        return 'Fresher (17 or younger)'
    elif age == 18:
        return 'Fresher or Dropper (18)'
    elif age == 19:
        return 'Dropper (1 year)'
    elif age == 20:
        return 'Dropper (2 years)'
    elif age == 21:
        return 'Dropper (3 years)'
    else:
        return 'Dropper (3+ years)'

def extract_dobs(pdf_path, pattern):
    result = subprocess.run(['pdftotext', '-layout', pdf_path, '-'],
                           capture_output=True, text=True)
    text = result.stdout
    matches = re.findall(pattern, text)
    
    valid_dobs = []
    for m in matches:
        dob = parse_dob(m)
        if dob:
            valid_dobs.append(dob)
    return valid_dobs

# Cutoff date: 31st Dec 2025
cutoff = datetime(2025, 12, 31)

# Process each state
states = [
    ('Jharkhand', 'Jharkhand_NEET_2025_Merit_list_1756.pdf', r'\b\d{2}/\d{2}/\d{4}\b'),
    ('Tripura', 'Tripura NEET-UG 2025 Qualified Candidate List.pdf', r'\b\d{2}-\d{2}-\d{4}\b')
]

insert_statements = []
for state, pdf, pattern in states:
    dobs = extract_dobs(pdf, pattern)
    
    # Calculate ages
    ages = [get_age_on_date(dob, cutoff) for dob in dobs]
    age_counts = Counter(ages)
    total = len(ages)
    
    if total == 0:
        continue
    
    print(f'\n=== {state.upper()} NEET 2025 AGE ANALYSIS ===')
    print(f'Total students with DOB data: {total}')
    print(f'Age Distribution on 31/12/2025:')
    
    cat_counts = Counter()
    for age, count in sorted(age_counts.items()):
        pct = 100.0 * count / total
        cat = categorize(age)
        cat_counts[cat] += count
        print(f'  Age {age}: {count} students ({pct:.1f}%)')
        
        # Build SQL INSERT
        insert_statements.append(
            f"INSERT INTO neetstatecouncelling.age_distribution (state, year, age, student_count, percentage, category) "
            f"SELECT '{state}', 2025, {age}, {count}, {pct:.2f}, '{cat}' "
            f"ON CONFLICT (state, year, age) DO UPDATE SET "
            f"student_count = EXCLUDED.student_count, percentage = EXCLUDED.percentage, category = EXCLUDED.category;"
        )
    
    # Print summary
    fresher = cat_counts.get('Fresher (17 or younger)', 0)
    fresher_or_dropper = cat_counts.get('Fresher or Dropper (18)', 0)
    droppers = sum(cat_counts[c] for c in cat_counts if c.startswith('Dropper'))
    
    print(f'\nSummary:')
    print(f'  Total Freshers (age ≤18): {fresher + fresher_or_dropper} ({100.0*(fresher+fresher_or_dropper)/total:.1f}%)')
    print(f'  Total Droppers (age 19+): {droppers} ({100.0*droppers/total:.1f}%)')

# Write SQL to file
with open('insert_age_data.sql', 'w') as f:
    f.write('\n'.join(insert_statements))

print(f'\n\nGenerated {len(insert_statements)} SQL INSERT statements in insert_age_data.sql')
