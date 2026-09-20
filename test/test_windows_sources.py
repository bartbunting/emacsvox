"""Protect the pairing of downloadable installers and their committed sources."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile

import test_windows_setup as fixture_module

BUNDLE, REPO = fixture_module.BUNDLE, fixture_module.REPO
SPEC = importlib.util.spec_from_file_location('sources', REPO / 'utils/emacsvox-windows-sources.py')
SOURCES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SOURCES)
VENDOR_SPEC = importlib.util.spec_from_file_location('vendor', REPO / 'utils/emacsvox-restore-cargo-vendor.py')
VENDOR = importlib.util.module_from_spec(VENDOR_SPEC)
VENDOR_SPEC.loader.exec_module(VENDOR)


class WindowsSourcesTests(unittest.TestCase):
    def setUp(self):
        fixture = fixture_module.WindowsSetupTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.fixture = fixture
        self.root = fixture.root
        self.cache = fixture.fixture.cache
        self.stage = fixture.stage
        self.destination = fixture.fixture.directory / 'downloads'
        self.source = self.cache / 'matching-sources.tar.gz'
        self.source.write_bytes(b'exact third-party sources')
        notice = self.root / 'etc/windows-notices.txt'
        notice.write_text('original notices\n')
        (self.root / 'etc/windows-sources.txt').write_text('Build instructions\n')
        if os.name != 'nt':
            (self.root / 'source-link').symlink_to('../not-a-build-input')
        self.lock = {'Schema': 1, 'RuntimeSHA256': {
            'Emacs': BUNDLE.pins(self.root / 'etc/windows-install.conf')['EMACSVOX_WINDOWS_EMACS_SHA256'],
            'Omnivox': BUNDLE.pins(self.root / 'etc/wsl-install.conf')['EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256']},
            'Archives': [{'Path': self.source.name, 'URL': 'https://example.invalid/source',
                          'SHA256': BUNDLE.sha256(self.source)}],
            'Notices': [{'Path': 'etc/windows-notices.txt', 'SHA256': BUNDLE.sha256(notice)}]}
        SOURCES.write_json(self.root / SOURCES.LOCK, self.lock)
        self.commit()
        fixture.fixture.destination = fixture.fixture.directory / 'committed-bundle'
        fixture.bundle = fixture.fixture.prepare()
        fixture.prepare()
        output = self.stage / 'output'
        output.mkdir()
        self.installer = output / 'fixture-setup.exe'
        self.installer.write_bytes(b'compiled setup fixture')
        self.provenance()

    def commit(self):
        self.fixture.fixture.git('add', '.')
        self.fixture.fixture.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'source fixture')

    def provenance(self):
        digest = BUNDLE.sha256(self.installer)
        self.installer.with_suffix('.exe.sha256').write_text(f'{digest}  {self.installer.name}\n')
        SOURCES.write_json(self.installer.with_suffix('.exe.provenance.json'), {
            'InstallerSHA256': digest, 'ManifestSHA256': BUNDLE.sha256(self.stage / 'setup-manifest.json')})

    def prepare(self):
        return SOURCES.prepare(self.root, self.stage, self.cache, self.destination,
                               'https://github.com/example/project/actions/runs/1', offline=True)

    def test_sources_separate_and_exactly_paired_with_installer(self):
        self.prepare()
        sources = self.destination / 'sources'
        binary = self.destination / 'installer'
        pairing = SOURCES.read_json(binary / 'downloads.json')
        self.assertEqual(pairing, SOURCES.read_json(sources / 'downloads.json'))
        self.assertEqual(pairing['InstallerSHA256'], BUNDLE.sha256(binary / self.installer.name))
        archive = sources / pairing['SourceArchive']
        self.assertEqual(pairing['SourceArchiveSHA256'], BUNDLE.sha256(archive))
        self.assertEqual(list(binary.glob('*sources.zip')), [])
        self.assertEqual(list(sources.glob('*.exe')), [])
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(z.read('archives/' + self.source.name), self.source.read_bytes())
            manifest = json.loads(z.read('source-manifest.json'))
            for item in manifest['Files']:
                self.assertEqual(BUNDLE.hashlib.sha256(z.read(item['Path'])).hexdigest(), item['SHA256'])
            self.assertEqual(z.read('emacsvox/utils/emacsvox-windows-setup.py'),
                             (self.root / 'utils/emacsvox-windows-setup.py').read_bytes())
            if os.name != 'nt':
                self.assertEqual(z.read('emacsvox/source-link'), b'../not-a-build-input')
                self.assertEqual(z.getinfo('emacsvox/source-link').external_attr >> 16, 0o120000)

    def test_changed_runtime_requires_source_review(self):
        self.lock['RuntimeSHA256']['Emacs'] = '0' * 64
        SOURCES.write_json(self.root / SOURCES.LOCK, self.lock)
        with self.assertRaisesRegex(ValueError, 'Runtime pins changed'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_dirty_work_preserved_and_not_published(self):
        path = self.root / 'lisp/emacsvox-setup.el'
        path.write_text('unsaved release work\n')
        with self.assertRaisesRegex(ValueError, 'clean committed'):
            self.prepare()
        self.assertEqual(path.read_text(), 'unsaved release work\n')
        self.assertFalse(self.destination.exists())

    def test_other_source_commit_rejected(self):
        (self.root / 'new-source.txt').write_text('new commit\n')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'different source commit'):
            self.prepare()

    def test_staged_application_must_match_source_even_if_manifest_is_changed(self):
        manifest_path = self.stage / 'setup-manifest.json'
        manifest = SOURCES.read_json(manifest_path)
        item = next(item for item in manifest['Files'] if item['Path'].endswith('/lisp/emacsvox-setup.el'))
        file = self.stage / 'payload' / item['Path']
        file.write_text('uncommitted build input')
        item['SHA256'] = BUNDLE.sha256(file)
        SOURCES.write_json(manifest_path, manifest)
        self.provenance()
        with self.assertRaisesRegex(ValueError, 'application payload differs'):
            self.prepare()

    def test_modified_installer_cannot_reuse_provenance(self):
        self.installer.write_bytes(b'different executable')
        with self.assertRaisesRegex(ValueError, 'provenance'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_installer_changed_during_download_is_not_published(self):
        acquire = SOURCES.BUNDLE.acquire

        def changed(*args):
            self.installer.write_bytes(b'changed while fetching sources')
            return acquire(*args)

        with mock.patch.object(SOURCES.BUNDLE, 'acquire', side_effect=changed):
            with self.assertRaisesRegex(ValueError, 'Installer changed during'):
                self.prepare()
        self.assertFalse(self.destination.exists())

    def test_missing_or_corrupt_source_prevents_both_downloads(self):
        self.source.write_bytes(b'corrupt source')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
            self.prepare()
        self.assertFalse(self.destination.exists())
        self.source.unlink()
        with self.assertRaisesRegex(ValueError, 'Offline archive missing'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_existing_downloads_are_preserved(self):
        self.destination.mkdir()
        sentinel = self.destination / 'keep'
        sentinel.write_text('keep')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()
        self.assertEqual(sentinel.read_text(), 'keep')

    def test_unsafe_or_duplicate_source_paths_rejected_before_download(self):
        for name in ['../escape', '/outside', 'C:/outside', 'bad\\path', 'trailing.']:
            self.lock['Archives'][0]['Path'] = name
            SOURCES.write_json(self.root / SOURCES.LOCK, self.lock)
            with self.assertRaisesRegex(ValueError, 'Unsafe source path'):
                self.prepare()
        self.lock['Archives'][0]['Path'] = self.source.name
        self.lock['Archives'].append(dict(self.lock['Archives'][0]))
        SOURCES.write_json(self.root / SOURCES.LOCK, self.lock)
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.prepare()


class CargoSourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.destination = self.root / 'restored'
        self.archive = self.root / 'example-1.0.crate'
        self.lock = self.root / 'lock.json'

    def crate(self, member='example-1.0/src/lib.rs'):
        with tarfile.open(self.archive, 'w:gz') as t:
            entry = tarfile.TarInfo(member)
            data = b'// source and original notice\n'
            entry.size = len(data)
            t.addfile(entry, io.BytesIO(data))
        SOURCES.write_json(self.lock, {'Archives': [{'Path': 'crates/' + self.archive.name,
                                                   'SHA256': BUNDLE.sha256(self.archive)}]})

    def test_restore_keeps_sources_and_cargo_package_checksums(self):
        self.crate()
        VENDOR.restore(self.root, self.lock, self.destination)
        package = self.destination / 'vendor/example-1.0'
        sums = SOURCES.read_json(package / '.cargo-checksum.json')
        self.assertEqual(sums['package'], BUNDLE.sha256(self.archive))
        self.assertEqual(sums['files']['src/lib.rs'], BUNDLE.sha256(package / 'src/lib.rs'))
        self.assertIn('replace-with = "provided-sources"', (self.destination / 'config.toml').read_text())

    def test_escaping_source_and_corrupt_archive_leave_no_destination(self):
        self.crate('../escape')
        with self.assertRaisesRegex(ValueError, 'Unsafe crate member'):
            VENDOR.restore(self.root, self.lock, self.destination)
        self.assertFalse(self.destination.exists())
        self.crate()
        self.archive.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            VENDOR.restore(self.root, self.lock, self.destination)
        self.assertFalse(self.destination.exists())


if __name__ == '__main__':
    unittest.main()
