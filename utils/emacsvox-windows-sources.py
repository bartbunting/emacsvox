#!/usr/bin/env python3
"""Pair a tested Windows development installer with its matching source download."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('bundle', ROOT / 'utils/emacsvox-windows-bundle.py')
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)
LOCK = 'etc/windows-sources.json'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def safe_path(name):
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or '..' in path.parts or
            any(c in name for c in '\\:*?"<>|\r\n') or
            any(part.endswith((' ', '.')) for part in path.parts)):
        raise ValueError(f'Unsafe source path: {name}')
    return path


def source_lock(root):
    lock = read_json(root / LOCK)
    common = BUNDLE.pins(root / 'etc/wsl-install.conf')
    windows = BUNDLE.pins(root / 'etc/windows-install.conf')
    expected = {'Emacs': windows['EMACSVOX_WINDOWS_EMACS_SHA256'],
                'Omnivox': common['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256']}
    if lock['Schema'] != 1 or lock['RuntimeSHA256'] != expected:
        raise ValueError('Runtime pins changed: review matching sources and notices first')
    names = set()
    for item in lock['Archives']:
        safe_path(item['Path'])
        name = item['Path'].casefold()
        if name in names or not re.fullmatch('[0-9a-f]{64}', item['SHA256']):
            raise ValueError('Duplicate source archive or invalid checksum')
        if not item['URL'].startswith('https://'):
            raise ValueError('Source downloads require HTTPS')
        names.add(name)
    if not names:
        raise ValueError('No matching source archives')
    for item in lock['Notices']:
        safe_path(item['Path'])
        if BUNDLE.sha256(root / item['Path']) != item['SHA256']:
            raise ValueError(f'Source review notice changed: {item["Path"]}')
    return lock


def checked_checkout(root, manifest):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)
    commit = git('rev-parse', 'HEAD').decode().strip()
    if git('status', '--porcelain', '--untracked-files=all'):
        raise ValueError('Source publication requires a clean committed checkout; work was preserved')
    if commit != manifest['BundleSourceCommit']:
        raise ValueError('Installer was staged from a different source commit')
    names = {}
    for entry in git('ls-files', '--stage', '-z').decode().rstrip('\0').split('\0'):
        metadata, name = entry.split('\t', 1)
        mode, _, stage = metadata.split()
        if mode not in {'100644', '100755', '120000'} or stage != '0':
            raise ValueError(f'Unsupported source entry: {name}')
        names[name] = int(mode, 8)
        safe_path(name)
        path = root / name
        if not path.is_symlink() and not path.is_file():
            raise ValueError(f'Nonregular source file: {name}')
    for name, digest in manifest['SetupInputs'].items():
        if name not in names or BUNDLE.sha256(root / name) != digest:
            raise ValueError(f'Installer build input differs from source: {name}')
    prefix = f'Applications/{manifest["Build"]}/'
    app = {item['Path'][len(prefix):]: item['SHA256'] for item in manifest['Files']
           if item['Path'].startswith(prefix)}
    expected = {name: BUNDLE.sha256(root / name) for name in names if BUNDLE.include(name)}
    if app != expected:
        raise ValueError('Installer application payload differs from committed source')
    return commit, names


def checked_installer(stage):
    manifest_path = stage / 'setup-manifest.json'
    manifest = read_json(manifest_path)
    if manifest['Schema'] != 1 or not re.fullmatch(r'\d{4}\.\d{1,2}\.\d+-dev-[a-f0-9]{16}', manifest['Build']):
        raise ValueError('Unsupported installer manifest')
    installers = list((stage / 'output').glob('*.exe'))
    if len(installers) != 1:
        raise ValueError('Expected exactly one compiled installer')
    installer = installers[0]
    provenance = read_json(installer.with_suffix('.exe.provenance.json'))
    digest = BUNDLE.sha256(installer)
    if (provenance['InstallerSHA256'] != digest or
            provenance['ManifestSHA256'] != BUNDLE.sha256(manifest_path)):
        raise ValueError('Installer provenance does not match the staged payload')
    if installer.with_suffix('.exe.sha256').read_text().split() != [digest, installer.name]:
        raise ValueError('Installer checksum sidecar does not match')
    for item in manifest['Files']:
        safe_path(item['Path'])
        if BUNDLE.sha256(stage / 'payload' / item['Path']) != item['SHA256']:
            raise ValueError(f'Staged payload changed: {item["Path"]}')
    return manifest, installer, digest


def source_hash(path):
    # Archive the link itself, never a file outside the checkout. Windows Git
    # may check symlinks out as ordinary files containing the same link text.
    return (hashlib.sha256(os.readlink(path).encode()).hexdigest()
            if path.is_symlink() else BUNDLE.sha256(path))


def add_file(archive, name, path, mode=0o100644):
    entry = zipfile.ZipInfo(name)
    entry.compress_type = zipfile.ZIP_STORED if name.startswith('archives/') else zipfile.ZIP_DEFLATED
    entry.create_system = 3
    entry.external_attr = mode << 16
    if path.is_symlink():
        archive.writestr(entry, os.readlink(path).encode())
        return
    with path.open('rb') as source, archive.open(entry, 'w', force_zip64=True) as target:
        shutil.copyfileobj(source, target)


def source_index(lock):
    """Put exact upstream source locations beside the downloadable binary."""
    lines = [
        '# Windows installer source downloads', '',
        'Third-party sources are hosted by their upstream projects. They are optional',
        'and are not needed to install or run Emacsvox. Download the components you need.',
        'The separate Emacsvox source ZIP includes our exact source checkout and this index.', '',
        'The filenames, versions and SHA256 values below identify the matching sources.',
        'Build instructions are in README.txt in the source ZIP and',
        'emacsvox/etc/windows-sources.txt. No third-party source archives are mirrored here.', '',
        '## Main source packages', '',
    ]
    for heading, prefix in [(None, ''), ('Rust dependencies', 'crates/'),
                            ('Optional Wasmtime test sources', 'wasmtime-tests/')]:
        if heading:
            lines += ['## ' + heading, '']
        for item in lock['Archives']:
            if (not prefix and '/' in item['Path']) or (prefix and not item['Path'].startswith(prefix)):
                continue
            lines += [f'- [{item["Path"]}]({item["URL"]})', f'  SHA256: `{item["SHA256"]}`', '']
    return '\n'.join(lines)


def prepare(root, stage, cache, destination, run_url, offline=False):
    """Publish our source with upstream links; verify external archives privately."""
    if destination.exists():
        raise ValueError(f'Download directory already exists: {destination}')
    if not re.fullmatch(r'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/\d+', run_url):
        raise ValueError('Expected a GitHub Actions run URL for the paired downloads')
    lock = source_lock(root)
    manifest, installer, installer_hash = checked_installer(stage)
    commit, names = checked_checkout(root, manifest)
    def acquire(item):
        return BUNDLE.acquire(item['URL'], cache / item['Path'], item['SHA256'], offline)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(acquire, lock['Archives']))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.windows-sources-', dir=destination.parent) as temporary:
        work = Path(temporary)
        sources = work / 'sources'
        binary = work / 'installer'
        sources.mkdir()
        binary.mkdir()
        source_name = f'emacsvox-{manifest["Build"]}-windows-x64-sources.zip'
        source_archive = sources / source_name
        files = [(f'emacsvox/{name}', root / name, mode) for name, mode in names.items()]
        inventory = {'Schema': 1, 'Build': manifest['Build'], 'SourceCommit': commit,
                     'RunURL': run_url, 'Installer': installer.name, 'InstallerSHA256': installer_hash,
                     'SetupManifestSHA256': BUNDLE.sha256(stage / 'setup-manifest.json'),
                     'SourceLockSHA256': BUNDLE.sha256(root / LOCK),
                     'RuntimeSHA256': lock['RuntimeSHA256'],
                     'UpstreamSources': lock['Archives'],
                     'Files': [{'Path': name, 'SHA256': source_hash(path), 'Mode': oct(mode)}
                               for name, path, mode in files]}
        write_json(work / 'source-manifest.json', inventory)
        (work / 'SOURCE-DOWNLOADS.md').write_text(source_index(lock), encoding='utf-8')
        with zipfile.ZipFile(source_archive, 'w') as archive:
            for name, path, mode in files:
                add_file(archive, name, path, mode)
            add_file(archive, 'source-manifest.json', work / 'source-manifest.json')
            add_file(archive, 'README.txt', root / 'etc/windows-sources.txt')
            add_file(archive, 'SOURCE-DOWNLOADS.md', work / 'SOURCE-DOWNLOADS.md')
        archive_hash = BUNDLE.sha256(source_archive)
        (sources / (source_name + '.sha256')).write_text(f'{archive_hash}  {source_name}\n', encoding='utf-8')
        for suffix in ['', '.sha256', '.provenance.json']:
            shutil.copyfile(Path(str(installer) + suffix), binary / (installer.name + suffix))
        if BUNDLE.sha256(binary / installer.name) != installer_hash:
            raise ValueError('Installer changed during source preparation')
        pairing = {'Schema': 1, 'Build': manifest['Build'], 'SourceCommit': commit,
                   'Installer': installer.name, 'InstallerSHA256': installer_hash,
                   'SourceArchive': source_name, 'SourceArchiveSHA256': archive_hash,
                   'SourcesArtifact': 'emacsvox-windows-sources', 'RunURL': run_url}
        for directory in [binary, sources]:
            write_json(directory / 'downloads.json', pairing)
            shutil.copyfile(work / 'SOURCE-DOWNLOADS.md', directory / 'SOURCE-DOWNLOADS.md')
        (binary / 'README.txt').write_text(
            'Emacsvox Windows development installer\n\n'
            f'Run {installer.name} to install Emacsvox, Emacs and Omnivox for your account.\n'
            'No administrator privileges are needed. Start it later from Start > Emacsvox Windows.\n\n'
            'Sources are optional; they are not needed to install or run.\n'
            'For Emacs, its libraries and Omnivox, open SOURCE-DOWNLOADS.md for exact upstream links\n'
            'and checksums. Those source archives are hosted by their upstream projects.\n'
            f'Open {run_url} and download the emacsvox-windows-sources artifact from this same run.\n'
            f'It contains our Emacsvox sources and the source index in {source_name}.\n'
            f'Its SHA256 is {archive_hash}.\n'
            'Keep matching sources and their locations available if you redistribute this installer.\n'
            'The installed application contains the applicable licence notices.\n\n'
            'CI checks installation, repair, rollback and uninstall. Interactive speech and screen-reader\n'
            'acceptance are separate checks. This development download is not a tagged release.\n', encoding='utf-8')
        # Recheck the checkout and source inventory before making either download visible.
        checked_checkout(root, manifest)
        for item, (_, path, _) in zip(inventory['Files'], files):
            if source_hash(path) != item['SHA256']:
                raise ValueError(f'Source changed during packaging: {item["Path"]}')
        work.rename(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staging-directory', type=Path, required=True)
    parser.add_argument('--cache-directory', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--run-url', required=True)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    print(prepare(ROOT, args.staging_directory.resolve(), args.cache_directory.resolve(),
                  args.output_directory.resolve(), args.run_url, args.offline))


if __name__ == '__main__':
    main()
