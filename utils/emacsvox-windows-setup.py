#!/usr/bin/env python3
"""Stage an Inno Setup development installer from a verified offline bundle."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('bundle', ROOT / 'utils/emacsvox-windows-bundle.py')
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)
PRODUCT = 'Emacsvox.Native.Development.1'
INPUTS = ('utils/emacsvox-windows-setup.iss', 'utils/emacsvox-windows-setup-helper.ps1',
          'utils/emacsvox-windows-setup-launch.ps1', 'utils/emacsvox-windows-common.ps1',
          'utils/emacsvox-windows-setup.py', 'utils/emacsvox-windows-setup-build.ps1',
          'etc/windows-setup.conf')


def safe_name(name):
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or '..' in path.parts or
            any(c in name for c in '\\:*?"<>|\r\n') or
            any(part.endswith((' ', '.')) for part in path.parts)):
        raise ValueError(f'Unsafe setup archive path: {name}')
    return path


def extract(archive, destination):
    """Extract only ordinary ZIP files/directories, checking Windows collisions."""
    seen = set()
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            path = safe_name(entry.filename)
            key = str(path).casefold()
            if key in seen or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f'Duplicate or linked setup archive entry: {entry.filename}')
            seen.add(key)
        source.extractall(destination)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def prepare(bundle, destination, root=ROOT):
    if destination.exists():
        raise ValueError(f'Staging directory already exists: {destination}')
    inputs = {name: BUNDLE.sha256(root / name) for name in INPUTS}
    bundle_hash = BUNDLE.sha256(bundle)
    with zipfile.ZipFile(bundle) as source:
        manifest = json.loads(source.read('bundle.json'))
        if manifest['Schema'] != 1 or not re.fullmatch(r'\d{4}\.\d{1,2}\.\d+-dev-[a-f0-9]{16}', manifest['Build']):
            raise ValueError('Unsupported development bundle')
        seen = set()
        for file in manifest['Files']:
            name = file['Path']
            safe_name(name)
            if name.startswith('Source/') and (name.endswith('.elc') or
                    any(part in {'local.mk', 'native-install.json', '.git'} for part in PurePosixPath(name).parts)):
                raise ValueError(f'Private configuration or byte-code in source payload: {name}')
            if name.casefold() in seen or hashlib.sha256(source.read(name)).hexdigest() != file['SHA256']:
                raise ValueError(f'Bundle checksum mismatch or duplicate: {name}')
            seen.add(name.casefold())
        # Reject unlisted input, including private config and stale byte-code.
        if set(source.namelist()) != {f['Path'] for f in manifest['Files']} | {'bundle.json'}:
            raise ValueError('Bundle contains unlisted payload')
        version = source.read('Source/VERSION').decode().strip()
        if not re.fullmatch(r'\d{4}\.\d{1,2}\.\d+', version):
            raise ValueError('Invalid Emacsvox version')
        identity = hashlib.sha256(json.dumps({'Bundle': bundle_hash, 'SetupInputs': inputs}, sort_keys=True).encode()).hexdigest()
        build = f'{version}-dev-{identity[:16]}'
        destination.mkdir(parents=True)
        try:
            application = destination / 'payload' / 'Applications' / build
            for file in manifest['Files']:
                name = file['Path']
                if name.startswith('Source/'):
                    target = application / name.removeprefix('Source/')
                elif name.startswith('Archives/'):
                    target = destination / name
                else:
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read(name))
            common = BUNDLE.pins(application / 'etc/wsl-install.conf')
            windows = BUNDLE.pins(application / 'etc/windows-install.conf')
            emacs_dir = f"Emacs/{common['EMACSVOX_WSL_EMACS_VERSION']}-windows-x64-{windows['EMACSVOX_WINDOWS_EMACS_SHA256'][:12]}"
            omnivox_dir = f"Omnivox/{common['EMACSVOX_WSL_OMNIVOX_VERSION']}-windows-x64"
            for name, expected, directory in [
                (windows['EMACSVOX_WINDOWS_EMACS_ARCHIVE'], windows['EMACSVOX_WINDOWS_EMACS_SHA256'], emacs_dir),
                (common['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE'], common['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256'], omnivox_dir),
            ]:
                archive = destination / 'Archives' / name
                if BUNDLE.sha256(archive) != expected:
                    raise ValueError(f'Runtime archive pin mismatch: {name}')
                extract(archive, destination / 'payload' / directory)
            for required in [emacs_dir + '/bin/emacs.exe', emacs_dir + '/bin/runemacs.exe',
                             emacs_dir + '/share/emacs/' + common['EMACSVOX_WSL_EMACS_VERSION'] + '/etc/COPYING',
                             omnivox_dir + '/omnivox.exe', omnivox_dir + '/espeak-ng-data/phontab',
                             omnivox_dir + '/third-party-licenses/THIRD-PARTY-NOTICES.md']:
                if not (destination / 'payload' / required).is_file():
                    raise ValueError(f'Required runtime file missing: {required}')
            write_json(destination / 'payload' / emacs_dir / 'emacsvox-build.json', {
                'Schema': 1, 'Kind': 'verified-prebuilt', 'Emacs': common['EMACSVOX_WSL_EMACS_VERSION'],
                'ArchiveSHA256': windows['EMACSVOX_WINDOWS_EMACS_SHA256'],
            })
            for original, relative in [
                ('utils/emacsvox-windows-setup-helper.ps1', 'Setup/emacsvox-windows-setup-helper.ps1'),
                ('utils/emacsvox-windows-common.ps1', 'Setup/emacsvox-windows-common.ps1'),
                ('utils/emacsvox-windows-setup-launch.ps1', 'Launcher/Start.ps1'),
            ]:
                target = destination / 'payload' / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / original, target)
            files = [{'Path': p.relative_to(destination / 'payload').as_posix(), 'SHA256': BUNDLE.sha256(p)}
                     for p in sorted((destination / 'payload').rglob('*')) if p.is_file()]
            setup_manifest = {'Schema': 1, 'Product': PRODUCT, 'Build': build, 'BundleBuild': manifest['Build'],
                              'BundleSHA256': bundle_hash, 'BundleSourceCommit': manifest['SourceCommit'],
                              'SetupInputs': inputs, 'Files': files}
            write_json(destination / 'setup-manifest.json', setup_manifest)
            write_json(destination / 'setup-owner.json', {'Schema': 1, 'Product': PRODUCT})
            shutil.copyfile(root / 'utils/emacsvox-windows-setup.iss', destination / 'setup.iss')
            (destination / 'setup-inputs.iss').write_text(
                f'#define AppVersion "{version}"\n#define Build "{build}"\n'
                f'#define EmacsDirectory "{emacs_dir.replace("/", chr(92))}"\n', encoding='utf-8')
            # Only generated application files are explicitly deleted. No root,
            # profile, voice, runtime or application-directory wildcard removal.
            generated = ['native-install.json', 'lisp/emacsvox-loaddefs.el']
            generated += [p.relative_to(application).as_posix() + 'c' for p in (application / 'lisp').glob('*.el')]
            uninstall = '[UninstallDelete]\n'
            for name in generated:
                relative = f'Applications/{build}/{name}'.replace('/', '\\')
                uninstall += f'Type: files; Name: "{{app}}\\{relative}"\n'
            uninstall += 'Type: files; Name: "{app}\\current.json"\n'
            # Generated byte-code can keep directories nonempty during Inno's
            # regular file removal. Remove only empty directories afterward.
            directories = [p for p in (destination / 'payload').rglob('*') if p.is_dir()]
            for directory in sorted(directories, key=lambda p: len(p.parts), reverse=True):
                relative = directory.relative_to(destination / 'payload').as_posix().replace('/', '\\')
                uninstall += f'Type: dirifempty; Name: "{{app}}\\{relative}"\n'
            uninstall += 'Type: dirifempty; Name: "{app}\\Cache"\n'
            (destination / 'setup-generated-uninstall.iss').write_text(uninstall, encoding='utf-8')
            (destination / 'setup-readme.txt').write_text(
                'Emacsvox Windows Development for Windows x64\n\n'
                'Setup installs Emacs, Emacsvox and Omnivox for your Windows account.\n'
                'No administrator privileges or internet connection are needed.\n\n'
                'After installation you can test speech and start Emacsvox.\n'
                'Use Start menu > Emacsvox Windows Development to start it later.\n\n'
                'Run Setup again to repair missing application files or install a newer build.\n'
                'Close this installation of Emacsvox first. Setup preserves your profile.\n'
                'Uninstall removes application files and shortcuts; your profile, logs\n'
                'and downloaded voices are kept.\n\n'
                'This is a local development build for testing.\n', encoding='utf-8')
            shutil.rmtree(destination / 'Archives')
            return destination / 'setup.iss'
        except Exception:
            shutil.rmtree(destination)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--staging-directory', type=Path, required=True)
    arguments = parser.parse_args()
    print(prepare(arguments.bundle.resolve(), arguments.staging_directory.resolve()))


if __name__ == '__main__':
    main()
