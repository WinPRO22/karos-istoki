"""Package only verified client payloads and explicitly selected emulator files.

No game/server launch, save copying, Git operation or network access.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import zipfile

DATA = (
    'balance-v2.ini', 'rates-v1.ini', 'drop-v1.ini', 'potions-v1.ini',
    'berneo-v1.json', 'npcs-v1.json', 'quests-v1.json', 'shops-v1.json',
    'drop-catalog.json', 'quest-items-v1.json', 'shop-items-v1.json',
    'crafting-items-v1.json', 'crafting-v1.json', 'item-enhancement-v1.json',
    'blader-profession-skills-v1.json',
)
DOCS = ('README.md', 'README.en.md', 'README.es.md', 'LICENSE',
        'THIRD_PARTY_NOTICES.md', 'docs/BERNEO_MECHANICS.md')
SCRIPTS = ('Start-Berneo.ps1', 'Stop-Berneo.ps1', 'Verify-BerneoClient.ps1')


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def contained(root, relative):
    parts = PurePosixPath(relative.replace('\\', '/'))
    if parts.is_absolute() or any(p in ('..', '.') for p in parts.parts) or ':' in relative:
        raise ValueError('Unsafe payload path')
    candidate = root.joinpath(*parts.parts)
    resolved = candidate.resolve(strict=True)
    if not resolved.is_relative_to(root) or not resolved.is_file():
        raise ValueError('Payload escapes root or is not a regular file')
    return resolved


def package(path, files, extra=None):
    temporary = path.with_suffix(path.suffix + '.partial')
    if path.exists() or temporary.exists():
        raise FileExistsError(f'Refusing to replace an existing artifact: {path.name}')
    with zipfile.ZipFile(temporary, 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for number, (source, target) in enumerate(files, 1):
            archive.write(source, target)
            if number % 100 == 0:
                print(f'{path.name}: {number}/{len(files)} files', flush=True)
        if extra:
            for name, content in extra.items():
                archive.writestr(name, content)
    temporary.rename(path)
    with zipfile.ZipFile(path) as archive:
        failed = archive.testzip()
        if failed:
            raise ValueError(f'ZIP CRC failed: {failed}')
    print(f'PASS ZIP: {path.name}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, required=True)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', default='v0.1.0-berneo')
    args = parser.parse_args()
    if not args.version or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-' for c in args.version):
        raise ValueError('Invalid version')
    repo, client = args.repository.resolve(strict=True), args.client.resolve(strict=True)
    output = args.output.resolve()
    if output.is_relative_to(repo) or output.is_relative_to(client):
        raise ValueError('Release output must be outside source and client trees')
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                    str(repo / 'scripts/Verify-BerneoClient.ps1'), '-ClientDirectory',
                    str(client)], check=True)
    manifest = json.loads((client / 'BERNEO-CLIENT-MANIFEST.json').read_text(encoding='utf-8-sig'))
    client_files = [(contained(client, item['Path']), 'client/' + item['Path'].replace('\\', '/'))
                    for item in manifest['Files']]
    client_files.append((client / 'BERNEO-CLIENT-MANIFEST.json', 'client/BERNEO-CLIENT-MANIFEST.json'))
    emulator_paths = list(DOCS) + ['scripts/' + name for name in SCRIPTS]
    emulator_paths += ['ServerEmulator/KarosOldEmulator.dpr']
    emulator_paths += ['ServerEmulator/data/b1008/' + name for name in DATA]
    emulator_paths += ['ServerEmulator/Win64/Release/KarosOldEmulator.exe',
                      'ServerEmulator/Win64/Release/sqlite3.dll',
                      'ServerEmulator/Win64/Tools/B1008TestHost.exe',
                      'ServerEmulator/Win64/Tools/sqlite3.dll']
    emulator_files = [(contained(repo, name), name) for name in emulator_paths]
    release_manifest = {'schema': 1, 'version': args.version,
                        'files': [{'path': name, 'bytes': source.stat().st_size, 'sha256': sha(source)}
                                  for source, name in emulator_files]}
    archives = [output / f'Karos-Istoki-{args.version}-client-b1008.zip',
                output / f'Karos-Istoki-{args.version}-emulator-win64.zip']
    if any(p.exists() or p.with_suffix(p.suffix + '.partial').exists() for p in archives):
        raise FileExistsError('Version artifacts already exist; use a new output directory')
    package(archives[0], client_files)
    package(archives[1], emulator_files, {'RELEASE-MANIFEST.json': json.dumps(release_manifest, indent=2) + '\n'})
    checksum = output / 'SHA256SUMS.txt'
    with checksum.open('x', encoding='utf-8', newline='\n') as stream:
        for path in archives:
            stream.write(f'{sha(path)}  {path.name}\n')
            print(f'READY {path.name} bytes={path.stat().st_size}', flush=True)


if __name__ == '__main__':
    main()
