import re, subprocess

def test_jh24_regex():
    result = subprocess.run(
        ['pdftotext', '-layout', 'Jharkhand_NEET_6960bee4e1acda925837cf2bf1acef5a.pdf', '-'],
        capture_output=True, text=True,
    )
    lines = result.stdout.split('\n')
    regex = re.compile(r'(\d{2}/\d{2}/\d{4})\s+(MALE|FEMALE)\s+(\d{3,4})\s+([\d.]+)\s+(\d+)\s+([A-Z\-/]+)')
    count = 0
    for line in lines[:20]:
        m = regex.search(line)
        if m:
            count += 1
            print(f'{count}: DOB={m.group(1)} G={m.group(2)} M={m.group(3)} P={m.group(4)} R={m.group(5)} C={m.group(6)}')
    print(f'Matched {count} lines')

if __name__ == '__main__':
    test_jh24_regex()
