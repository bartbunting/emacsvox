"""Verify setup payload integrity and the boundary between program and user files."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import importlib.util
import json
from pathlib import Path
import shutil
import unittest
import zipfile

import test_windows_bundle as fixture_module

BUNDLE, REPO = fixture_module.BUNDLE, fixture_module.REPO

SPEC = importlib.util.spec_from_file_location('setup', REPO / 'utils/emacsvox-windows-setup.py')
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)


class WindowsSetupTests(unittest.TestCase):
    def setUp(self):
        fixture = fixture_module.WindowsBundleTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.fixture = fixture
        self.root = fixture.root
        self.stage = fixture.directory / 'staged setup'
        for name in SETUP.INPUTS:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, target)
        for archive, entries in [
            ('emacs.zip', ['bin/emacs.exe', 'bin/runemacs.exe', 'share/emacs/31.1/etc/COPYING']),
            ('omnivox.zip', ['omnivox.exe', 'espeak-ng-data/phontab', 'third-party-licenses/THIRD-PARTY-NOTICES.md']),
        ]:
            path = fixture.cache / archive
            old_hash = BUNDLE.sha256(path)
            with zipfile.ZipFile(path, 'w') as output:
                for name in entries:
                    output.writestr(name, 'fixture\n')
            for name in ['etc/windows-install.conf', 'etc/wsl-install.conf']:
                pins = self.root / name
                pins.write_text(pins.read_text().replace(old_hash, BUNDLE.sha256(path)))
        pins = self.root / 'etc/wsl-install.conf'
        pins.write_text(pins.read_text() + 'EMACSVOX_WSL_EMACS_VERSION=31.1\nEMACSVOX_WSL_OMNIVOX_VERSION=1.12.0\n')
        self.bundle = fixture.prepare()

    def prepare(self):
        return SETUP.prepare(self.bundle, self.stage, root=self.root)

    def test_payload_and_uninstall_keep_user_data_outside_ownership(self):
        self.prepare()
        manifest = json.loads((self.stage / 'setup-manifest.json').read_text())
        application = self.stage / 'payload/Applications' / manifest['Build']
        self.assertTrue((application / 'lisp/emacsvox-setup.el').exists())
        self.assertEqual(list(application.rglob('*.elc')), [])
        self.assertEqual(list(application.rglob('native-install.json')), [])
        for file in manifest['Files']:
            self.assertEqual(BUNDLE.sha256(self.stage / 'payload' / file['Path']), file['SHA256'])
            self.assertNotIn(file['Path'].split('/')[0], ['profile', 'voices', 'logs'])
        deleted = (self.stage / 'setup-generated-uninstall.iss').read_text().splitlines()[1:]
        for entry in deleted:
            self.assertTrue(entry.startswith(('Type: files; Name: "{app}\\Applications\\',
                                              'Type: dirifempty; Name: "{app}\\')) or
                            entry == 'Type: files; Name: "{app}\\current.json"')
            self.assertNotIn('*', entry)
            self.assertNotIn('\\profile', entry)
            self.assertNotIn('\\voices', entry)
        self.assertFalse((self.stage / 'Archives').exists())

    def test_wrapper_changes_get_a_distinct_build(self):
        self.prepare()
        first = json.loads((self.stage / 'setup-manifest.json').read_text())['Build']
        script = self.root / 'utils/emacsvox-windows-setup.iss'
        script.write_text(script.read_text() + '\n; new setup revision\n')
        self.stage = self.fixture.directory / 'second stage'
        self.prepare()
        self.assertNotEqual(first, json.loads((self.stage / 'setup-manifest.json').read_text())['Build'])

    def test_bad_bundle_is_rejected_before_staging(self):
        with zipfile.ZipFile(self.bundle, 'a') as archive:
            archive.writestr('Source/local.mk', 'private')
        with self.assertRaisesRegex(ValueError, 'unlisted'):
            self.prepare()
        self.assertFalse(self.stage.exists())

    def test_existing_staging_is_preserved(self):
        self.stage.mkdir()
        marker = self.stage / 'user-file'
        marker.write_text('preserve')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()
        self.assertEqual(marker.read_text(), 'preserve')

    def test_even_listed_emacsvox_bytecode_is_rejected(self):
        with zipfile.ZipFile(self.bundle) as source:
            entries = {name: source.read(name) for name in source.namelist()}
        manifest = json.loads(entries['bundle.json'])
        name = 'Source/lisp/emacsvox-setup.elc'
        entries[name] = b'stale byte-code'
        manifest['Files'].append({'Path': name, 'SHA256': BUNDLE.hashlib.sha256(entries[name]).hexdigest()})
        entries['bundle.json'] = json.dumps(manifest).encode()
        with zipfile.ZipFile(self.bundle, 'w') as output:
            for name, data in entries.items(): output.writestr(name, data)
        with self.assertRaisesRegex(ValueError, 'byte-code in source payload'):
            self.prepare()
        self.assertFalse(self.stage.exists())

    def test_runtime_zip_cannot_escape_or_overwrite_case_aliases(self):
        archive = self.fixture.directory / 'unsafe.zip'
        for names in [['../escape'], ['A.txt', 'a.txt'], ['C:/escape'], ['file.']]:
            with zipfile.ZipFile(archive, 'w') as output:
                for name in names:
                    output.writestr(name, 'unsafe')
            with self.assertRaises(ValueError):
                SETUP.extract(archive, self.stage)
            self.assertFalse(self.stage.exists())


if __name__ == '__main__':
    unittest.main()
