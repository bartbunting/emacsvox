"""Offline bundle integrity and source-only packaging regression tests."""

# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


REPO = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('bundle', REPO / 'utils/emacsvox-windows-bundle.py')
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)


class WindowsBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = self.directory / 'source with spaces'
        self.root.mkdir()
        self.cache = self.directory / 'cache'
        self.cache.mkdir()
        self.destination = self.directory / 'output'
        for name in BUNDLE.REQUIRED:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture\n')
        (self.root / 'VERSION').write_text('2026.9.5\n')
        (self.root / 'utils/emacsvox-windows-bundle-install.ps1').write_text('# wrapper fixture\n')
        emacs = self.cache / 'emacs.zip'
        omnivox = self.cache / 'omnivox.zip'
        emacs.write_bytes(b'Emacs archive fixture')
        omnivox.write_bytes(b'Omnivox archive fixture')
        (self.root / 'etc/windows-install.conf').write_text(
            'EMACSVOX_WINDOWS_INSTALL_SCHEMA=1\n'
            'EMACSVOX_WINDOWS_EMACS_ARCHIVE=emacs.zip\n'
            'EMACSVOX_WINDOWS_EMACS_URL=https://example.invalid/emacs.zip\n'
            f'EMACSVOX_WINDOWS_EMACS_SHA256={BUNDLE.sha256(emacs)}\n')
        (self.root / 'etc/wsl-install.conf').write_text(
            'EMACSVOX_WSL_INSTALL_SCHEMA=1\n'
            'EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE=omnivox.zip\n'
            'EMACSVOX_WSL_OMNIVOX_RELEASE_URL=https://example.invalid\n'
            f'EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256={BUNDLE.sha256(omnivox)}\n')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')

    def git(self, *arguments):
        subprocess.run(['git', *arguments], cwd=self.root, check=True, capture_output=True)

    def prepare(self):
        return BUNDLE.prepare(self.root, self.cache, self.destination, offline=True)

    def test_source_only_payload_preserves_dirty_source_and_excludes_personal_state(self):
        source = self.root / 'lisp/emacsvox-setup.el'
        source.write_text('uncommitted change\n')
        (self.root / 'lisp/emacsvox-setup.elc').write_bytes(b'private bytecode')
        (self.root / 'native-install.json').write_text('private settings')
        (self.root / 'local.mk').write_text('EMACS=private')
        archive = self.prepare()
        with zipfile.ZipFile(archive) as payload:
            names = payload.namelist()
            self.assertIn('Archives/emacs.zip', names)
            self.assertIn('Archives/omnivox.zip', names)
            self.assertIn('Install.ps1', names)
            self.assertIn('Install.cmd', names)
            self.assertFalse(any(n.endswith(('.elc', 'local.mk', 'native-install.json')) for n in names))
            self.assertEqual(payload.read('Source/lisp/emacsvox-setup.el'), b'uncommitted change\n')
            manifest = json.loads(payload.read('bundle.json'))
            self.assertIn('-dev-', manifest['Build'])
            for entry in manifest['Files']:
                self.assertEqual(BUNDLE.hashlib.sha256(payload.read(entry['Path'])).hexdigest(), entry['SHA256'])
        self.assertEqual(source.read_text(), 'uncommitted change\n')
        self.assertEqual(archive.with_suffix('.zip.sha256').read_text().split()[0], BUNDLE.sha256(archive))

    def test_missing_or_corrupt_archive_creates_no_bundle(self):
        archive = self.cache / 'omnivox.zip'
        archive.write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
            self.prepare()
        self.assertFalse(self.destination.exists())
        archive.unlink()
        with self.assertRaisesRegex(ValueError, 'Offline archive missing'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_missing_source_is_not_silently_omitted(self):
        (self.root / 'lisp/emacsvox-setup.el').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing regular payload'):
            self.prepare()
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_symlink_cannot_import_outside_payload(self):
        source = self.root / 'lisp/emacsvox-setup.el'
        source.unlink()
        source.symlink_to(self.cache / 'emacs.zip')
        with self.assertRaisesRegex(ValueError, 'Missing regular payload'):
            self.prepare()

    def test_reproducible_and_payload_change_gets_new_identity(self):
        first = self.prepare()
        other = self.directory / 'other'
        second = BUNDLE.prepare(self.root, self.cache, other, offline=True)
        self.assertEqual(first.name, second.name)
        self.assertEqual(BUNDLE.sha256(first), BUNDLE.sha256(second))
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()
        (self.root / 'lisp/emacsvox-setup.el').write_text('changed\n')
        self.assertNotEqual(first.name, self.prepare().name)


if __name__ == '__main__':
    unittest.main()
