"""Guarded local itemAttr patch: Returning Stone cooldown is ten minutes."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from B1008PortablePaths import paths

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = Path('resource/Interface/IE_Lod/itemAttr.lod_eng')
SOURCE = paths.source / RELATIVE
TARGET = paths.client / RELATIVE
MANIFEST = paths.client / 'LOCAL-CLIENT-MANIFEST.json'
SOURCE_HASH = '7a54da8182bd5bf87538d99feaefcae6bb22f91a3f51f4de2c75e35ccaffd4e5'


def generate(source):
    assert hashlib.sha256(source).hexdigest() == SOURCE_HASH
    assert len(source) == 4 + struct.unpack_from('<I', source)[0] * 443
    offsets = [o for o in range(4, len(source), 443)
               if struct.unpack_from('<I', source, o)[0] == 57104]
    assert len(offsets) == 1
    offset = offsets[0] + 96
    assert struct.unpack_from('<d', source, offset)[0] == 3600
    result = bytearray(source)
    struct.pack_into('<d', result, offset, 600)
    assert result[:offset] == source[:offset] and result[offset+8:] == source[offset+8:]
    return bytes(result)


def main():
    processes = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], check=True,
                               stdout=subprocess.PIPE).stdout.lower()
    assert b'"amo.exe"' not in processes, 'Close the test client before patching'
    for path in (SOURCE, TARGET, MANIFEST):
        assert path.resolve() == path.absolute() and path.stat().st_nlink == 1
    source = SOURCE.read_bytes()
    patched = generate(source)
    current = TARGET.read_bytes()
    assert current in (source, patched), 'Unknown local itemAttr; preserved'
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    entries = [r for r in manifest['Files'] if r['Path'].replace('\\', '/') == RELATIVE.as_posix()]
    assert len(entries) == 1 and entries[0]['SHA256'].lower() == hashlib.sha256(current).hexdigest()
    if current != patched:
        paths.backups.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='return-cooldown-', dir=paths.backups))
        shutil.copy2(TARGET, backup / TARGET.name)
        shutil.copy2(MANIFEST, backup / MANIFEST.name)
        TARGET.write_bytes(patched)
        entries[0]['SHA256'] = hashlib.sha256(patched).hexdigest()
        key = str(RELATIVE).replace('/', '\\')
        if key not in manifest['Changed']:
            manifest['Changed'].append(key)
        manifest['ReturnCooldown'] = dict(item=57104, seconds=600)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print('Backup:', backup)
    assert TARGET.read_bytes() == patched and SOURCE.read_bytes() == source
    print('PASS: Returning Stone 600 seconds; all other fields preserved')


if __name__ == '__main__':
    main()
