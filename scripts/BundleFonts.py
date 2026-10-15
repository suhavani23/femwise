"""Bundle the exact, checksum-verified fonts used by our locked google_fonts SDK."""
import concurrent.futures
import hashlib
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SDK = next((ROOT / '.tools/pub-cache/hosted/pub.dev').glob('google_fonts-6.3.2'))
DEST = ROOT / 'assets/fonts'
DEST.mkdir(parents=True, exist_ok=True)
families = {
    'poppins': ('Poppins', 'part_p.g.dart'),
    'montserrat': ('Montserrat', 'part_m.g.dart'),
    'playfairDisplay': ('PlayfairDisplay', 'part_p.g.dart'),
    'pacifico': ('Pacifico', 'part_p.g.dart'),
}
weights = {'400': 'Regular', '500': 'Medium', '600': 'SemiBold', '700': 'Bold'}
jobs = []
for method, (family, source) in families.items():
    content = (SDK / 'lib/src/google_fonts_parts' / source).read_text(encoding='utf-8')
    body = content.split(f'static TextStyle {method}(', 1)[1].split('return googleFontsTextStyle', 1)[0]
    variants = re.findall(r'fontWeight: FontWeight.w(\d+),\s*fontStyle: FontStyle.(\w+),\s*\): GoogleFontsFile\(\s*\x27([a-f0-9]+)\x27,\s*(\d+)', body)
    assert variants, family
    for weight, style, checksum, length in variants:
        wanted = (family in ('Poppins', 'Montserrat') and weight in weights and style == 'normal') or (family == 'Montserrat' and weight == '400' and style == 'italic') or (family == 'PlayfairDisplay' and weight == '700' and style == 'normal') or family == 'Pacifico'
        if wanted:
            variant = 'Italic' if style == 'italic' else weights[weight]
            jobs.append((DEST / f'{family}-{variant}.ttf', f'https://fonts.gstatic.com/s/a/{checksum}.ttf', checksum, int(length)))

def fetch(job):
    path, url, checksum, length = job
    data = path.read_bytes() if path.exists() else urllib.request.urlopen(url, timeout=45).read()
    assert len(data) == length and hashlib.sha256(data).hexdigest() == checksum, path
    path.write_bytes(data)
    return path.name

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for name in pool.map(fetch, jobs):
        print(name)
for family in ('poppins', 'montserrat', 'playfairdisplay', 'pacifico'):
    url = f'https://raw.githubusercontent.com/google/fonts/main/ofl/{family}/OFL.txt'
    license_text = urllib.request.urlopen(url, timeout=45).read()
    assert b'SIL OPEN FONT LICENSE' in license_text
    (DEST / f'{family}-OFL.txt').write_bytes(
        b'\n'.join(line.rstrip() for line in license_text.splitlines()) + b'\n')
print('Fonts verified; licenses included.')
