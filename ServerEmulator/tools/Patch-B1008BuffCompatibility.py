"""Remove zero placeholders from the LOCAL client's blocked-skill categories.

b1008 5089AB parses skillData+82C into the restriction multimap +50.
It converts literal "0" to category 0 instead of an empty list. 5001FC ->
50703E then blocks uncategorized skills (including all combined Fletta)
while any such modifier is active. Only standalone zero placeholders are
normalized; genuine nonzero restriction lists and numeric effects stay intact.
The native 4EB9D4 buff collection already adds/refreshes by skill ID.
"""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import tempfile
from B1008PortablePaths import paths

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = Path('resource/Interface/IE_Lod/skillData.lod_eng')
SOURCE = paths.source / RELATIVE
TARGET = paths.client / RELATIVE
MANIFEST = paths.client / 'LOCAL-CLIENT-MANIFEST.json'
SOURCE_HASH = 'f3de6ca77564039bc04511040810789a873315770d74afcda6a5863fe7b09fc1'


def generate(source):
    assert hashlib.sha256(source).hexdigest() == SOURCE_HASH
    assert len(source) == 4 + struct.unpack_from('<I', source)[0] * 3116
    result = bytearray(source)
    changed = []
    for offset in range(4, len(source), 3116):
        text = source[offset + 0x82C:offset + 0xC2C].split(b'\0')[0]
        if text == b'0':
            result[offset + 0x82C] = 0
            changed.append(struct.unpack_from('<I', source, offset)[0])
    assert changed
    return bytes(result), changed


def main():
    import subprocess
    processes = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], check=True,
                               stdout=subprocess.PIPE).stdout.lower()
    assert b'"amo.exe"' not in processes, 'Close the test client before patching'
    source = SOURCE.read_bytes()
    patched, changed = generate(source)
    current = TARGET.read_bytes()
    assert current in (source, patched), 'Unrecognized local table; left untouched'
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    entries = [row for row in manifest['Files'] if row['Path'].replace('\\', '/') == RELATIVE.as_posix()]
    assert len(entries) == 1
    assert entries[0]['SHA256'].lower() == hashlib.sha256(current).hexdigest()
    if current != patched:
        paths.backups.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='buff-compatibility-', dir=paths.backups))
        shutil.copy2(TARGET, backup / TARGET.name)
        shutil.copy2(MANIFEST, backup / MANIFEST.name)
        TARGET.write_bytes(patched)
        entries[0]['SHA256'] = hashlib.sha256(patched).hexdigest()
        key = str(RELATIVE).replace('/', '\\')
        if key not in manifest['Changed']:
            manifest['Changed'].append(key)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print('Backup:', backup)
    assert TARGET.read_bytes() == patched and SOURCE.read_bytes() == source
    print('PASS: normalized', len(changed), 'empty restriction lists; numerical effects and genuine restrictions unchanged')


if __name__ == '__main__':
    main()
