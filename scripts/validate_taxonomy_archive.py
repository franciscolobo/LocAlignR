#!/usr/bin/env python3
"""Verify the curated archive without extracting any files."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).resolve().parents[1] / 'inst/extdata/db_manifest-taxonomy.json')
    args = parser.parse_args()
    db = json.loads(args.manifest.read_text())['databases'][0]
    spec = db['files'][0]
    expected = set(db['post_download']['extract']['outputs'])
    h = hashlib.sha256()
    with args.archive.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    if h.hexdigest() != spec['sha256']:
        raise SystemExit('SHA256 mismatch')
    print('SHA256: OK')
    files = {}
    with tarfile.open(args.archive, 'r:gz') as archive:
        for entry in archive:
            p = PurePosixPath(entry.name)
            if p.is_absolute() or '..' in p.parts:
                raise SystemExit(f'Unsafe archive path: {entry.name}')
            if entry.isdir():
                continue
            if not entry.isfile() or entry.size <= 0:
                raise SystemExit(f'Unexpected nonregular or empty member: {entry.name}')
            if p.name not in expected or p.name in files:
                raise SystemExit(f'Unexpected or duplicate archive member: {entry.name}')
            files[p.name] = p
    if set(files) != expected:
        raise SystemExit(f'Missing members: {sorted(expected - set(files))}')
    parents = {p.parent for p in files.values()}
    named_directory = PurePosixPath(spec['filename'].removesuffix('.tar.gz'))
    if parents not in ({PurePosixPath('.')}, {named_directory}):
        raise SystemExit(f'Unexpected archive layout: {parents}')
    for p in sorted(files.values()):
        print(p)
    print('Archive layout: OK')


if __name__ == '__main__':
    main()
