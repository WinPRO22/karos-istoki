"""Enable normal-price sell-only Store bindings in the local test client."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from B1008PortablePaths import paths

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = Path('resource/Interface/IE_Lod/npcShop.lod_eng')
SOURCE = paths.source / RELATIVE
TARGET = paths.client / RELATIVE
MANIFEST = paths.client / 'LOCAL-CLIENT-MANIFEST.json'
SOURCE_HASH = 'd8f1506a9dabe3e35002cc1673a52700142e0ec981a8e020cb7ef42bcffe101b'

def generate(source, merchants):
    assert hashlib.sha256(source).hexdigest() == SOURCE_HASH
    count, = struct.unpack_from('<I', source)
    assert len(source) == 4 + count * 138
    offsets = {struct.unpack_from('<II', source, o): o for o in range(4, len(source), 138)}
    result = bytearray(source)
    allowed = set(range(4))
    # Jason is the native empty Store template. Painstrome has a Store button
    # but no binding, so give it the same empty stock and normal sale prices.
    template = source[offsets[9300231, 19003]:offsets[9300231, 19003]+138]
    for merchant in merchants:
        key = merchant['npcId'], merchant['mapId']
        offset = offsets.get(key)
        if offset is None:
            assert key == (9320021, 19003) and merchant['shopId'] == 0
            offset = len(result)
            result.extend(template)
            struct.pack_into('<II', result, offset, *key)
            count += 1
        assert struct.unpack_from('<I', result, offset+8)[0] == merchant['shopId']
        if merchant['shopId'] == 0:
            struct.pack_into('<dd', result, offset+12, 100, 100)
            allowed.update(range(offset+12, offset+28))
    struct.pack_into('<I', result, 0, count)
    assert all(a == b or i in allowed for i, (a, b) in enumerate(zip(source, result)))
    assert len(result) == 4 + count * 138
    parsed = {struct.unpack_from('<II', result, o): struct.unpack_from('<Idd', result, o+8)
              for o in range(4, len(result), 138)}
    for merchant in merchants:
        assert parsed[merchant['npcId'], merchant['mapId']] == (merchant['shopId'], 100, 100)
    return bytes(result)

def main():
    processes = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], check=True, stdout=subprocess.PIPE).stdout.lower()
    assert b'"amo.exe"' not in processes, 'Close the test client before patching'
    for path in (SOURCE, TARGET, MANIFEST):
        assert path.resolve() == path.absolute() and path.stat().st_nlink == 1
    merchants = json.loads(paths.shops.read_text(encoding='utf-8-sig'))['merchants']
    source = SOURCE.read_bytes()
    patched = generate(source, merchants)
    current = TARGET.read_bytes()
    assert current in (source, patched), 'Unknown local npcShop; preserved'
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    entries = [r for r in manifest['Files'] if r['Path'].replace('\\', '/') == RELATIVE.as_posix()]
    assert len(entries) == 1 and entries[0]['SHA256'].lower() == hashlib.sha256(current).hexdigest()
    if current != patched:
        paths.backups.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='stores-', dir=paths.backups))
        shutil.copy2(TARGET, backup / TARGET.name)
        shutil.copy2(MANIFEST, backup / MANIFEST.name)
        TARGET.write_bytes(patched)
        entries[0]['SHA256'] = hashlib.sha256(patched).hexdigest()
        key = str(RELATIVE).replace('/', '\\')
        if key not in manifest['Changed']:
            manifest['Changed'].append(key)
        manifest['StoreServices'] = dict(count=len(merchants), sellOnlyPrices='Original itemBase prices')
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print('Backup:', backup)
    assert TARGET.read_bytes() == patched and SOURCE.read_bytes() == source
    print('PASS: all 16 local Store bindings/prices; stock and unrelated fields unchanged; original client preserved')

if __name__ == '__main__':
    main()
