"""Repair the b1008 HAM spear recovery ID typo in the local Body.pak only."""
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path
from B1008PortablePaths import paths as portable_paths

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = Path('resource/Character/Body.pak')
SOURCE = portable_paths.source / RELATIVE
RUNTIME = portable_paths.client
SOURCE_HASH = '9d727263f6789820d8b27152cf40cd9a417c53889056afaac5710c56c09c601a'
PATCH_HASH = '98c994666a027c13cae13715ef562e4ff81f4a2441bc1fe7e07c12ed6a9ef496'
ENTRY_OFFSET, ENTRY_SIZE = 6165642, 26212
RECORD_OFFSET = 0x5E726E
OLD = bytes.fromhex('8f0200000c000000414e303635355f28424c4b2921000000')
NEW = bytes.fromhex('900200000c000000414e303635365f28424c4b2921000000')

spec = importlib.util.spec_from_file_location('skill_patch_paths',
    Path(__file__).with_name('Patch-B1008ProfessionLevels.py'))
paths = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paths)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def generate(source):
    require(len(source) == 42305547 and digest(source) == SOURCE_HASH, 'Unknown archived Body.pak')
    header = source[ENTRY_OFFSET - 145:ENTRY_OFFSET]
    require(header[0] == 0 and header[1:129].split(b'\0')[0] == b'HAM._OB'
            and struct.unpack_from('<I', header, 129)[0] == ENTRY_SIZE, 'Unexpected HAM entry')
    require(source[RECORD_OFFSET:RECORD_OFFSET + len(OLD)] == OLD, 'Unexpected recovery record')
    result = bytearray(source)
    result[RECORD_OFFSET:RECORD_OFFSET + len(NEW)] = NEW
    result = bytes(result)
    require(digest(result) == PATCH_HASH, 'Unexpected generated recovery hash')
    return result


def apply(*, runtime=RUNTIME, source_path=SOURCE, backup_root=None, verify=False, restore=False):
    runtime = paths.plain_path(runtime)
    source_path = paths.plain_path(source_path)
    target = paths.plain_path(runtime / RELATIVE)
    manifest_path = paths.plain_path(runtime / 'LOCAL-CLIENT-MANIFEST.json')
    require(target.resolve() != source_path.resolve() and not target.samefile(source_path), 'Archive cannot be target')
    source = source_path.read_bytes()
    patched = generate(source)
    current = target.read_bytes()
    require(current in (source, patched), 'Unknown local Body.pak changes; left untouched')
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode('utf-8-sig'))
    entries = [r for r in manifest['Files'] if r['Path'].replace('\\', '/') == RELATIVE.as_posix()]
    require(len(entries) == 1 and entries[0]['SHA256'].lower() == digest(current), 'Body manifest mismatch')
    if verify:
        require(current == patched, 'Spear recovery patch is not applied')
        return digest(current)
    desired = source if restore else patched
    if desired == current:
        return digest(current)
    backup_root = paths.plain_path(backup_root or portable_paths.backups)
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='spear-recovery-', dir=backup_root))
    shutil.copy2(target, backup / target.name)
    shutil.copy2(manifest_path, backup / manifest_path.name)
    entries[0]['SHA256'] = digest(desired)
    key = str(RELATIVE).replace('/', '\\')
    if restore:
        manifest['Changed'] = [p for p in manifest['Changed'] if p != key]
    elif key not in manifest['Changed']:
        manifest['Changed'].append(key)
    try:
        target.write_bytes(desired)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        require(target.read_bytes() == desired, 'Write verification failed')
        require(source_path.read_bytes() == source, 'Archive changed unexpectedly')
    except BaseException:
        target.write_bytes(current)
        manifest_path.write_bytes(manifest_bytes)
        raise
    print('Backup:', backup)
    return digest(desired)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    require(not (args.verify and args.restore), 'Choose verify or restore')
    if os.name == 'nt':
        processes = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], check=True,
                                   stdout=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW).stdout.lower()
        require(b'"amo.exe"' not in processes, 'Close the game before patching')
    print('PASS: spear recovery', apply(verify=args.verify, restore=args.restore))
