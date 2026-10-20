"""Prepare an original-resource client in a NEW directory; launch nothing.

Requires Python 3.10+, Node.js, and the exact unpacked b1008 source listed in
b1008-source-files.json. Original client assets are not covered by the code
license. This tool never reads a personal runtime client or character save.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys

TOOLS = Path(__file__).resolve().parent
SOURCE_EXE = '9d0a4ff1cf224e1637be3c0c99ab60eea962928747e0f1f1baad3fca0e082966'
RELEASE_EXE = '312d1e3465e4a0e4b42fdebd30d000998bd3647307da90d1dd1164b6f29ab927'
ENDPOINT = bytes.fromhex('73a5dc0a3a6898c6f7040e3f6f9fcf000d17')
PATCHES = ('TradeUI-v16', 'CompactLabels-v3', 'Stacks', 'ReturnCooldown-600',
           'Stores', 'BuffCompatibility', 'ProfessionLevels', 'FlettaText',
           'ProvocationRange', 'SpearRecovery')


def plain_path(value):
    value = Path(value).absolute()
    for entry in (value, *value.parents):
        if entry.exists():
            info = entry.lstat()
            if entry.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
                raise ValueError('Redirected path is not allowed: ' + str(entry))
            if entry.is_file() and info.st_nlink != 1:
                raise ValueError('Hard-linked file is not allowed: ' + str(entry))
    return value


def child(root, relative):
    relative = relative.replace('\\', '/')
    parts = PurePosixPath(relative)
    if (not relative or parts.is_absolute() or ':' in relative
            or any(p in ('', '.', '..') for p in relative.split('/'))):
        raise ValueError('Unsafe inventory path: ' + relative)
    result = plain_path(root.joinpath(*parts.parts))
    if root not in result.parents:
        raise ValueError('Inventory path escapes its root')
    return result


def digest(file):
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else stream_digest(stream)


def stream_digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(block)
    return value.hexdigest()


def write_json(file, value):
    file.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def run(command):
    subprocess.run(command, check=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path, help='read-only original unpacked b1008 directory')
    parser.add_argument('--target', required=True, type=Path, help='new directory outside the source repository')
    parser.add_argument('--backups', type=Path, help='separate patch backup directory; defaults beside target')
    parser.add_argument('--node', default='node', help='Node.js executable for exact label generation')
    args = parser.parse_args()
    source, target = plain_path(args.source), plain_path(args.target)
    backups = plain_path(args.backups or target.parent / 'client-patch-backups')
    repository = TOOLS.parents[1]
    if not source.is_dir() or target.exists():
        raise ValueError('Source must exist; target must be a NEW directory')
    if (source == target or source in target.parents or target in source.parents
            or repository == target or repository in target.parents):
        raise ValueError('Target must be outside the source and exported code repository')
    if (backups in (source, target) or source in backups.parents or target in backups.parents
            or repository == backups or repository in backups.parents):
        raise ValueError('Backups must be outside source, client and code repository')
    if not shutil.which(args.node):
        raise ValueError('Node.js executable was not found')
    shops = plain_path(TOOLS.parent / 'data/b1008/shops-v1.json')
    if not shops.is_file():
        raise ValueError('Exported Berneo shops-v1.json is missing')
    inventory = json.loads((TOOLS / 'b1008-source-files.json').read_text(encoding='utf-8-sig'))
    seen = set()
    for row in inventory:
        name = row['path'].replace('\\', '/')
        if name.casefold() in seen:
            raise ValueError('Duplicate source inventory path')
        seen.add(name.casefold())
        file = child(source, name)
        if not file.is_file() or file.stat().st_size != row['size'] or digest(file) != row['sha256']:
            raise ValueError('Original source identity mismatch: ' + name)
        if name.lower().endswith('.exe') and name != 'AMo.exe':
            raise ValueError('Unreviewed executable: ' + name)
    if digest(child(source, 'AMo.exe')) != SOURCE_EXE:
        raise ValueError('Wrong original executable')
    # The explicit inventory is the only copy input. Extra source files are
    # ignored; no source tree, private runtime or research tree is copied.
    target.mkdir(parents=True)
    backups.mkdir(parents=True, exist_ok=True)
    for row in inventory:
        destination = child(target, row['path'])
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(child(source, row['path']), destination)
    (target / 'ServerList.ten').write_bytes(ENDPOINT)
    files = [{'Path': row['path'].replace('\\', '/'),
              'SHA256': digest(child(target, row['path']))} for row in inventory]
    local_manifest = target / 'LOCAL-CLIENT-MANIFEST.json'
    write_json(local_manifest, dict(Schema=1, SourceExeSHA256=SOURCE_EXE,
                                   Endpoint='127.0.0.1:10001', Changed=['ServerList.ten'], Files=files))
    common = ['--source', str(source), '--client', str(target), '--backups', str(backups)]
    run([sys.executable, str(TOOLS / 'Patch-B1008TradeUI.py'), 'apply', *common])
    run([args.node, str(TOOLS / 'Compact-B1008Labels.cjs'), '--apply', *common])
    for patch in ('Stacks', 'ReturnCooldown', 'Stores', 'BuffCompatibility',
                  'ProfessionLevels', 'FlettaText', 'ProvocationRange', 'SpearRecovery'):
        run([sys.executable, str(TOOLS / ('Patch-B1008' + patch + '.py')), *common])
    if digest(target / 'AMo.exe') != RELEASE_EXE or (target / 'ServerList.ten').read_bytes() != ENDPOINT:
        raise ValueError('Final executable or endpoint mismatch')
    current = json.loads(local_manifest.read_text(encoding='utf-8-sig'))
    # Public manifests retain identities and exact hashes, never machine paths,
    # backup locations, personal settings or historical test notes.
    clean = dict(Schema=1, SourceExeSHA256=SOURCE_EXE, Endpoint='127.0.0.1:10001',
                 Changed=current['Changed'], Files=current['Files'])
    for key in ('TradeUI', 'CompactLabels', 'Stacks', 'ReturnCooldown', 'StoreServices'):
        if key in current:
            clean[key] = current[key]
    clean['Files'].sort(key=lambda row: row['Path'])
    for row in clean['Files']:
        if digest(child(target, row['Path'])) != row['SHA256']:
            raise ValueError('Patch manifest mismatch: ' + row['Path'])
    write_json(local_manifest, clean)
    release_files = []
    for name in sorted([row['Path'] for row in clean['Files']] + [local_manifest.name]):
        file = child(target, name)
        release_files.append(dict(Path=name, Size=file.stat().st_size, SHA256=digest(file)))
    expected_names = {row['Path'].casefold() for row in release_files}
    for file in target.rglob('*'):
        plain_path(file)
        if file.is_file() and file.relative_to(target).as_posix().casefold() not in expected_names:
            raise ValueError('Unexpected client file: ' + file.name)
    manifest = dict(Schema=1, Product='Karos Istoki / Berneo b1008',
                    Endpoint='127.0.0.1:10001', SourceExeSHA256=SOURCE_EXE,
                    ExeSHA256=RELEASE_EXE, Patches=list(PATCHES),
                    AssetLicense='Original client and third-party assets are excluded from the source-code license.',
                    Files=release_files)
    write_json(target / 'BERNEO-CLIENT-MANIFEST.json', manifest)
    print('PASS: prepared', len(release_files), 'payload files; endpoint 127.0.0.1:10001; client not launched')
    print('AMo.exe SHA256:', RELEASE_EXE)


if __name__ == '__main__':
    main()
