#!/usr/bin/env python3
"""Prepare a verified offline development bundle for native Windows x64."""

# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parent.parent
RUNTIME_FILES = {
    'VERSION', 'README.org', 'AUTHORS', 'COPYING', 'THIRD_PARTY_NOTICES',
    'lisp/Makefile', 'bin/emacsvox-install.ps1', 'bin/emacsvox.ps1',
    'utils/emacsvox-windows-common.ps1', 'utils/emacsvox-native-bytecode.el',
    'utils/emacsvox-windows-startup.el', 'utils/emacsvox-windows-build.sh',
}
RUNTIME_TREES = {'etc', 'sounds', 'xsl', 'js', 'LICENSES'}
REQUIRED = RUNTIME_FILES | {
    'etc/windows-install.conf', 'etc/wsl-install.conf',
    'lisp/emacsvox-setup.el', 'info/emacsvox.info',
    'sounds/packs/chimes/open-object.ogg',
}


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def pins(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        match = re.fullmatch(r'([A-Z][A-Z0-9_]*)=([A-Za-z0-9_./:+-]+)', line)
        if not match or match[1] in result:
            raise ValueError(f'Invalid or duplicate installation pin in {path}')
        result[match[1]] = match[2]
    return result


def include(name):
    path = Path(name)
    if any(part.startswith('.') for part in path.parts):
        return False
    if path.suffix in {'.elc', '.pyc', '.exe', '.dll', '.o'}:
        return False
    return (name in RUNTIME_FILES or path.parts[0] in RUNTIME_TREES
            or path.parts[:2] == ('media', 'radio')
            or (path.parent == Path('lisp') and path.suffix == '.el')
            or (path.parent == Path('info') and '.info' in path.name))


def acquire(url, path, expected, offline=False):
    if not url.startswith('https://') or not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('Invalid archive pin')
    if path.exists():
        if sha256(path) != expected:
            raise ValueError(f'Checksum mismatch in cached archive: {path}')
        return path
    if offline:
        raise ValueError(f'Offline archive missing: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.download-', dir=path.parent) as temporary:
        download = Path(temporary) / 'archive'
        with urllib.request.urlopen(url, timeout=120) as response, download.open('wb') as output:
            shutil.copyfileobj(response, output)
        if sha256(download) != expected:
            raise ValueError(f'Checksum mismatch: {url}')
        download.replace(path)
    return path


def prepare(root, cache, destination, offline=False):
    common = pins(root / 'etc/wsl-install.conf')
    windows = pins(root / 'etc/windows-install.conf')
    if common['EMACSVOX_WSL_INSTALL_SCHEMA'] != '1' or windows['EMACSVOX_WINDOWS_INSTALL_SCHEMA'] != '1':
        raise ValueError('Unsupported installation manifest schema')
    archive_pins = [
        (windows['EMACSVOX_WINDOWS_EMACS_ARCHIVE'], windows['EMACSVOX_WINDOWS_EMACS_URL'],
         windows['EMACSVOX_WINDOWS_EMACS_SHA256']),
        (common['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE'],
         common['EMACSVOX_WSL_OMNIVOX_RELEASE_URL'] + '/' + common['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE'],
         common['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256']),
    ]
    for name, url, expected in archive_pins:
        if Path(name).name != name or not name.endswith('.zip'):
            raise ValueError(f'Invalid archive name: {name}')
        acquire(url, cache / name, expected, offline)
    names = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root
    ).decode().split('\0')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    version = (root / 'VERSION').read_text().strip()
    if not re.fullmatch(r'\d{4}\.\d{1,2}\.\d+', version):
        raise ValueError('Invalid Emacsvox VERSION')
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.windows-bundle-', dir=destination) as temporary:
        stage = Path(temporary)
        for name in sorted(set(names) - {''}):
            if not include(name):
                continue
            source = root / name
            if source.is_symlink() or not source.is_file():
                raise ValueError(f'Missing regular payload file: {source}')
            target = stage / 'Source' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        for name in REQUIRED:
            if not (stage / 'Source' / name).is_file():
                raise ValueError(f'Required payload file missing: {name}')
        (stage / 'Archives').mkdir()
        for name, _, expected in archive_pins:
            target = stage / 'Archives' / name
            shutil.copyfile(cache / name, target)
            if sha256(target) != expected:
                raise ValueError(f'Archive changed during packaging: {name}')
        shutil.copyfile(root / 'utils/emacsvox-windows-bundle-install.ps1', stage / 'Install.ps1')
        (stage / 'Install.cmd').write_bytes(
            b'@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*\r\n'
            b'if errorlevel 1 (\r\n  pause\r\n  exit /b 1\r\n)\r\npause\r\nexit /b 0\r\n')
        (stage / 'README.txt').write_text(
            'Emacsvox native Windows x64 development bundle\n\n'
            'Extract this ZIP on a local Windows drive, then run Install.cmd.\n'
            'No administrator privileges, Git, WSL or build tools are required.\n'
            'The installation is offline and uses verified bundled archives.\n'
            'An audio check opens a temporary Emacs window and speaks twice.\n'
            'Start Emacsvox using the command printed after installation.\n\n'
            'PowerShell: .\\Install.ps1 -InstallRoot "C:\\path with spaces\\Emacsvox"\n'
            'Add -Check for a read-only preflight; -NoAudioCheck for unattended setup.\n'
            'Profile and logs live under InstallRoot; sources and runtimes are versioned.\n'
            'This first development slice has no wizard, shortcuts or uninstaller yet.\n'
            'It is not a release artifact. Redistribution/source publication is not yet prepared.\n',
            encoding='utf-8')
        files = [{'Path': str(p.relative_to(stage)).replace('\\', '/'), 'SHA256': sha256(p)}
                 for p in sorted(stage.rglob('*')) if p.is_file()]
        identity = hashlib.sha256(json.dumps({'Files': files, 'SourceCommit': commit}, sort_keys=True).encode()).hexdigest()
        build = f'{version}-dev-{identity[:16]}'
        manifest = {'Schema': 1, 'Build': build, 'SourceCommit': commit,
                    'PayloadSHA256': identity, 'Files': files}
        (stage / 'bundle.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        archive = destination / f'emacsvox-{build}-windows-x64.zip'
        if archive.exists():
            raise ValueError(f'Bundle already exists: {archive}')
        partial = stage / 'bundle.zip'
        # Stable metadata makes identical payloads reproducible, independent of
        # checkout timestamps. Archives are already compressed.
        with zipfile.ZipFile(partial, 'w') as output:
            for path in sorted(stage.rglob('*')):
                if not path.is_file() or path == partial:
                    continue
                entry = zipfile.ZipInfo(str(path.relative_to(stage)).replace('\\', '/'))
                entry.compress_type = zipfile.ZIP_STORED if path.suffix == '.zip' else zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                output.writestr(entry, path.read_bytes())
        partial.replace(archive)
        archive.with_suffix('.zip.sha256').write_text(f'{sha256(archive)}  {archive.name}\n')
        return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-directory', type=Path, default=Path.home() / '.cache/emacsvox/downloads')
    parser.add_argument('--output-directory', type=Path, default=ROOT / 'dist')
    parser.add_argument('--offline', action='store_true', help='require previously cached archives')
    arguments = parser.parse_args()
    print(prepare(ROOT, arguments.cache_directory.resolve(), arguments.output_directory.resolve(), arguments.offline))


if __name__ == '__main__':
    main()
