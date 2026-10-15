"""Check the APK actually contains the offline self-care assets and cloud URL."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

apk = Path(sys.argv[1])
prefix = 'assets/flutter_assets/'
with zipfile.ZipFile(apk) as archive:
    names = set(archive.namelist())
    references = {'assets/music.mp3', 'assets/models/movenet_lightning.tflite'}
    for symptom in ('stress', 'anxiety', 'insomnia'):
        guides = json.loads(archive.read(prefix + f'assets/jsons/{symptom}.json'))
        for guide in guides:
            for step in guide['steps']:
                references.add(step['image'])
    for asset in references:
        assert prefix + asset in names, f'Missing guide asset: {asset}'
        assert archive.getinfo(prefix + asset).file_size > 0, asset
    fonts = [name for name in names if name.startswith(prefix + 'assets/fonts/') and name.endswith('.ttf')]
    assert len(fonts) == 11, f'Expected 11 offline fonts, found {len(fonts)}'
    assert not any(name.endswith('/.env') for name in names), 'Environment secrets must not ship'
    kernel = archive.read(prefix + 'kernel_blob.bin')
    assert b'https://femwise.onrender.com' in kernel, 'Deployed backend URL missing'
    assert b'http://10.60.73.214' not in kernel, 'Obsolete laptop URL found'
    if 'scanner' in apk.name.lower():
        assert b'/extract_ingredients' in kernel, 'Scanner route missing'
        assert b'Scan Ingredients' in kernel, 'Scanner entry missing'
        assert b'demo_tracking_data_v1' in kernel, 'Separate demo dataset missing'
print(f'Verified {len(references)} self-care assets, {len(fonts)} fonts and deployed HTTPS URL.')
print(f'APK: {apk.resolve()}')
print(f'Size: {apk.stat().st_size / (1024 * 1024):.1f} MiB')
print(f'SHA-256: {hashlib.file_digest(apk.open("rb"), "sha256").hexdigest()}')
