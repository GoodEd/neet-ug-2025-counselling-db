import re, subprocess

def read_pdf_lines(pdf_name):
    result = subprocess.run(
        ['pdftotext', '-layout', pdf_name, '-'],
        capture_output=True, text=True,
    )
    return result.stdout.split('\n')

def analyze_tripura_2024_dob_lines():
    lines = read_pdf_lines('Tripura_NEET_6b6353a89a0ba63a02668482e7eef6d5.pdf')
    dob_pattern = re.compile(r'(\d{2}-\d{2}-\d{4})\s+(.*?)\s+(Yes|No)\s*$')
    count = 0
    for i, line in enumerate(lines):
        match = dob_pattern.search(line)
        if match:
            count += 1
            dob, cat_raw, ph = match.group(1), match.group(2).strip(), match.group(3)
            if count <= 5:
                print(f"Line {i}: DOB={dob} Cat='{cat_raw}' PH={ph}")
    print(f"Total DOB matches: {count}")

if __name__ == '__main__':
    analyze_tripura_2024_dob_lines()
