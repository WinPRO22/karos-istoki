"""Shared explicit paths for the standalone, offline client patch tools.

Common options are consumed before the individual patcher's argument parser.
The defaults deliberately refer only to this exported project. Importing a
generator never opens, creates or patches a client file.
"""
import argparse
import os
from pathlib import Path
import sys


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


class ClientPaths:
    def __init__(self):
        project = Path(__file__).resolve().parents[1]
        parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
        parser.add_argument('--source', type=Path,
                            default=os.environ.get('BERNEO_SOURCE_CLIENT', project / 'client-source'))
        parser.add_argument('--client', type=Path, default=project / 'runtime/b1008')
        parser.add_argument('--backups', type=Path)
        parser.add_argument('--shops', type=Path, default=project / 'data/b1008/shops-v1.json')
        args, remaining = parser.parse_known_args()
        sys.argv[1:] = remaining
        self.source = plain_path(args.source)
        self.client = plain_path(args.client)
        self.backups = plain_path(args.backups or self.client.parent / 'patch-backups')
        self.shops = plain_path(args.shops)
        if (self.client == self.source or self.source in self.client.parents
                or self.client in self.source.parents):
            raise ValueError('Source and client directories must be disjoint')
        if (self.backups == self.source or self.source in self.backups.parents
                or self.backups == self.client or self.client in self.backups.parents):
            raise ValueError('Backups must be outside source and client directories')


paths = ClientPaths()
