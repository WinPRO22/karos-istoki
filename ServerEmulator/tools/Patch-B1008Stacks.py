"""Reversible local itemBase stack policy: equipment 1, other items 100.

Carat uses the largest count supported by the native signed-integer UI;
there is no separate 100-million gameplay cap. No running process is read.
"""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from B1008PortablePaths import paths

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = Path('resource/Interface/IE_Lod/itemBase.lod_eng')
SOURCE = paths.source / RELATIVE
TARGET = paths.client / RELATIVE
MANIFEST = paths.client / 'LOCAL-CLIENT-MANIFEST.json'
SOURCE_HASH = 'a2f1bb75019c11db2b92d1d20952ca22f6607ecc7d815407a9ceb67e8ad18a41'


def generate(source):
    assert hashlib.sha256(source).hexdigest() == SOURCE_HASH
    assert len(source) == 4 + struct.unpack_from('<I', source)[0] * 2184
    result = bytearray(source)
    changed = []
    for o in range(4, len(source), 2184):
        item = struct.unpack_from('<I', source, o)[0]
        family = struct.unpack_from('<I', source, o + 12)[0]
        limit = 0x7FFFFFFF if item == 999999 else (1 if family == 1 else 100)
        if struct.unpack_from('<I', source, o + 52)[0] != limit:
            struct.pack_into('<I', result, o + 52, limit)
            changed.append(item)
    assert changed
    return bytes(result), changed


def main():
    processes = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], check=True,
                               stdout=subprocess.PIPE).stdout.lower()
    assert b'"amo.exe"' not in processes, 'Close the test client before patching'
    source = SOURCE.read_bytes()
    patched, changed = generate(source)
    current = TARGET.read_bytes()
    assert current in (source, patched), 'Unknown item table; preserved'
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    entries = [r for r in manifest['Files'] if r['Path'].replace('\\', '/') == RELATIVE.as_posix()]
    assert len(entries) == 1 and entries[0]['SHA256'].lower() == hashlib.sha256(current).hexdigest()
    if current != patched:
        paths.backups.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='stack-policy-', dir=paths.backups))
        shutil.copy2(TARGET, backup / TARGET.name)
        shutil.copy2(MANIFEST, backup / MANIFEST.name)
        TARGET.write_bytes(patched)
        entries[0]['SHA256'] = hashlib.sha256(patched).hexdigest()
        key = str(RELATIVE).replace('/', '\\')
        if key not in manifest['Changed']:
            manifest['Changed'].append(key)
        manifest['Stacks'] = dict(version=1, equipment=1, other=100, currencyNativeMaximum=0x7FFFFFFF)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print('Backup:', backup)
    assert TARGET.read_bytes() == patched and SOURCE.read_bytes() == source
    print('PASS:', len(changed), 'local stack fields changed; original client preserved')


if __name__ == '__main__':
    main()
