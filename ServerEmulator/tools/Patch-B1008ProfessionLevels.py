"""Compose approved local skill levels and the existing Wind Barrier tooltip.

Original archive bytes are read-only. Native 47DA8C checks skillLevel+0C
before K sends learn/upgrade. No executable or live memory is accessed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import tempfile
from B1008PortablePaths import paths

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = Path('resource/Interface/IE_Lod/skillLevel.lod_eng')
SOURCE = paths.source / RELATIVE
RUNTIME = paths.client
SOURCE_HASH = '74884ce42ac05be8370bb520f8011dbf8c4f56b9e76b940c3e845a0c8532afa6'
STRIDE = 1698
PROVOCATION_RANGES = (35, 51, 68, 84, 100)
# skill, rank, original level, approved level, absolute byte offset
LEVELS = ((1104, 1, 36, 26, 76426), (1106, 5, 1, 45, 100198),
          (1906, 5, 1, 45, 159628))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def generate(source, *, tooltip=False, levels=False, provocation=False):
    require(digest(source) == SOURCE_HASH, 'Unknown original skill table')
    require(len(source) == 4 + struct.unpack_from('<I', source)[0] * STRIDE,
            'Invalid skill table layout')
    result = bytearray(source)
    for skill, rank, old, new, field in LEVELS:
        require(struct.unpack_from('<II', source, field - 12) == (skill, rank),
                'Unexpected skill row identity')
        require(struct.unpack_from('<I', source, field)[0] == old,
                'Unexpected original required level')
        if levels:
            struct.pack_into('<I', result, field, new)
    matches = 0
    taunt_ranks = set()
    for offset in range(4, len(source), STRIDE):
        skill, rank = struct.unpack_from('<II', source, offset)
        if skill == 1005:
            require(rank in range(1, 6) and rank not in taunt_ranks,
                    'Invalid or duplicate Provocation rank')
            require(struct.unpack_from('<I', source, offset + 0x6c)[0] == 1 and
                    struct.unpack_from('<d', source, offset + 0x70)[0] == 35,
                    'Unexpected original Provocation geometry')
            taunt_ranks.add(rank)
            if provocation:
                struct.pack_into('<d', result, offset + 0x70, PROVOCATION_RANGES[rank - 1])
        if struct.unpack_from('<II', source, offset) != (50211, 1):
            continue
        start = offset + 1186
        text = source[start:start + 512].split(b'\0')[0]
        require(text.count(b'Defense Rating by 3.') == 1,
                'Unexpected Wind Barrier tooltip')
        if tooltip:
            text = text.replace(b'Defense Rating by 3.', b'Defense Rating by 4.')
            result[start:start + len(text)] = text
        matches += 1
    require(matches == 1, 'Missing or duplicate Wind Barrier row')
    require(taunt_ranks == set(range(1, 6)), 'Missing Provocation ranks')
    return bytes(result)


def detect(source, current):
    for tooltip in (False, True):
        for levels in (False, True):
            for provocation in (False, True):
                if current == generate(source, tooltip=tooltip, levels=levels, provocation=provocation):
                    return tooltip, levels, provocation
    raise ValueError('Unknown local skill table changes; left untouched')


def plain_path(path):
    path = Path(path).absolute()
    for part in (path, *path.parents):
        if part.exists():
            attributes = getattr(part.lstat(), 'st_file_attributes', 0)
            require(not part.is_symlink() and not attributes & 0x400,
                    'Redirected path is not allowed')
    return path


def apply(feature, *, runtime=RUNTIME, source_path=SOURCE, backup_root=None, verify=False):
    require(feature in ('tooltip', 'levels', 'provocation'), 'Unknown patch feature')
    runtime = plain_path(runtime)
    source_path = plain_path(source_path)
    target = plain_path(runtime / RELATIVE)
    manifest_path = plain_path(runtime / 'LOCAL-CLIENT-MANIFEST.json')
    require(target.resolve() != source_path.resolve(), 'Archive cannot be target')
    require(not target.samefile(source_path), 'Archive hard link cannot be target')
    source = source_path.read_bytes()
    current = target.read_bytes()
    tooltip, levels, provocation = detect(source, current)
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode('utf-8-sig'))
    entries = [row for row in manifest['Files']
               if row['Path'].replace('\\', '/') == RELATIVE.as_posix()]
    require(len(entries) == 1, 'Missing or duplicate manifest entry')
    require(entries[0]['SHA256'].lower() == digest(current), 'Local manifest hash mismatch')
    if verify:
        require(dict(tooltip=tooltip, levels=levels, provocation=provocation)[feature], 'Requested patch is not applied')
        return digest(current)
    patched = generate(source, tooltip=tooltip or feature == 'tooltip',
                       levels=levels or feature == 'levels',
                       provocation=provocation or feature == 'provocation')
    if patched == current:
        return digest(current)
    if backup_root is None:
        backup_root = paths.backups
    backup_root = plain_path(backup_root)
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='skill-levels-', dir=backup_root))
    shutil.copy2(target, backup / target.name)
    shutil.copy2(manifest_path, backup / manifest_path.name)
    entries[0]['SHA256'] = digest(patched)
    key = str(RELATIVE).replace('/', '\\')
    if key not in manifest['Changed']:
        manifest['Changed'].append(key)
    try:
        target.write_bytes(patched)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        require(target.read_bytes() == patched, 'Local write verification failed')
        require(source_path.read_bytes() == source, 'Archive changed unexpectedly')
    except BaseException:
        target.write_bytes(current)
        manifest_path.write_bytes(manifest_bytes)
        raise
    print('Backup:', backup)
    return digest(patched)


def main(feature='levels'):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    print('PASS:', feature, apply(feature, verify=args.verify))


if __name__ == '__main__':
    main()
