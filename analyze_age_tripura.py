import re
import subprocess
from datetime import datetime
from collections import Counter

def parse_dob(text):
    for fmt in ['%d-%m-%Y', '%d/%m/%Y']:
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

# Extract text from PDF
result = subprocess.run(['pdftotext', '-layout', 'Tripura_NEET_6b6353a89a0ba63a02668482e7eef6d5.pdf', '-'],
                       capture_output=True, text=True)
text = result.stdout

# Extract DOBs: match both DD-MM-YYYY and DD/MM/YYYY
dob_pattern = r'\b\d{2}[-/]\d{2}[-/]\d{4}\b'
matches = re.findall(dob_pattern, text)

# Parse dates
seen = set()
unique_dobs = []
for m in matches:
    dob = parse_dob(m)
    if dob:
        dob_key = dob.strftime('%d/%m/%Y')
        if dob_key not in seen:
            seen.add(dob_key)
            unique_dobs.append(dob)

# Cutoff date: 31st Dec 2024
cutoff = datetime(2024, 12, 31)

# Calculate ages and categories
ages = [get_age_on_date(dob, cutoff) for dob in unique_dobs]
categories = [categorize(age) for age in ages]

# Statistics
total = len(ages)
if total == 0:
    print("No valid DOB data found")
    exit()

age_counts = Counter(ages)
cat_counts = Counter(categories)

print(f'=== TRIPURA NEET 2024 AGE ANALYSIS ===')
print(f'Total students with DOB data: {total}')
print(f'')
print(f'Age Distribution on 31/12/2024:')
for age in sorted(age_counts.keys()):
    count = age_counts[age]
    pct = 100.0 * count / total
    print(f'  Age {age}: {count} students ({pct:.1f}%)')

print(f'')
print(f'Category Distribution:')
for cat in ['Fresher (17 or younger)', 'Fresher or Dropper (18)', 'Dropper (1 year)', 
            'Dropper (2 years)', 'Dropper (3 years)', 'Dropper (3+ years)']:
    count = cat_counts.get(cat, 0)
    pct = 100.0 * count / total
    print(f'  {cat}: {count} students ({pct:.1f}%)')

print(f'')
fresher = cat_counts['Fresher (17 or younger)']
fresher_or_dropper = cat_counts['Fresher or Dropper (18)']
droppers = cat_counts['Dropper (1 year)'] + cat_counts['Dropper (2 years)'] + cat_counts['Dropper (3 years)'] + cat_counts['Dropper (3+ years)']

print(f'Summary:')
print(f'  Fresher only (age ≤17): {fresher} ({100.0*fresher/total:.1f}%)')
print(f'  Fresher or Dropper (age 18): {fresher_or_dropper} ({100.0*fresher_or_dropper/total:.1f}%)')
print(f'  Dropper only (age 19+): {droppers} ({100.0*droppers/total:.1f}%)')
print(f'')
print(f'  Total Freshers (age ≤18): {fresher + fresher_or_dropper} ({100.0*(fresher+fresher_or_dropper)/total:.1f}%)')
print(f'  Total Droppers (age 19+): {droppers} ({100.0*droppers/total:.1f}%)')
