#!/usr/bin/env python3
"""Restore offline Cargo sources from a Windows installer source download."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import tempfile


def restore(archives, lock_path, destination):
    if destination.exists():
        raise ValueError(f'Destination already exists: {destination}')
    lock = json.loads(lock_path.read_text(encoding='utf-8'))
    crates = [item for item in lock['Archives'] if item['Path'].startswith('crates/')]
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.cargo-sources-', dir=destination.parent) as temporary:
        work = Path(temporary)
        for item in crates:
            name = PurePosixPath(item['Path'])
            if len(name.parts) != 2 or name.suffix != '.crate' or '\\' in str(name):
                raise ValueError('Invalid crate source path')
            archive = archives / name.name
            with archive.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != item['SHA256']:
                    raise ValueError(f'Crate checksum mismatch: {name.name}')
            package = name.stem
            hashes = {}
            with tarfile.open(archive) as source:
                for member in source:
                    relative = PurePosixPath(member.name)
                    if (relative.is_absolute() or '..' in relative.parts or
                            relative.parts[0] != package or '\\' in member.name):
                        raise ValueError(f'Unsafe crate member: {member.name}')
                    if member.isdir():
                        continue
                    if not member.isfile():
                        raise ValueError(f'Nonregular crate member: {member.name}')
                    key = relative.relative_to(package).as_posix()
                    if key in hashes:
                        raise ValueError(f'Duplicate crate member: {member.name}')
                    content = source.extractfile(member).read()
                    path = work / 'vendor' / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(content)
                    hashes[key] = hashlib.sha256(content).hexdigest()
            path = work / 'vendor' / package / '.cargo-checksum.json'
            path.write_text(json.dumps({'files': hashes, 'package': item['SHA256']}) + '\n', encoding='utf-8')
        vendor = (destination / 'vendor').resolve().as_posix()
        (work / 'config.toml').write_text(
            '[source.crates-io]\nreplace-with = "provided-sources"\n\n'
            '[source.provided-sources]\ndirectory = ' + json.dumps(vendor) + '\n', encoding='utf-8')
        work.rename(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archives', type=Path, required=True, help='extracted archives/crates directory')
    parser.add_argument('--lock', type=Path, required=True, help='extracted emacsvox/etc/windows-sources.json')
    parser.add_argument('--destination', type=Path, required=True, help='new directory for Cargo home and vendor sources')
    args = parser.parse_args()
    print(restore(args.archives, args.lock, args.destination.resolve()))


if __name__ == '__main__':
    main()
