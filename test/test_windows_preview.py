"""Protect preview promotion, source identity and the publication boundary."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import hashlib
import importlib.util
import json
import shutil
import subprocess
import unittest
from unittest import mock
import zipfile

import test_windows_sources as fixture_module

SPEC = importlib.util.spec_from_file_location('preview', fixture_module.REPO / 'utils/emacsvox-windows-preview.py')
PREVIEW = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREVIEW)


class WindowsPreviewTests(unittest.TestCase):
    def setUp(self):
        fixture = fixture_module.WindowsSourcesTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.fixture = fixture
        self.root = fixture.root
        fixture.prepare()
        self.downloads = fixture.destination
        evidence = self.downloads / 'evidence'
        (evidence / 'setup').mkdir(parents=True)
        (evidence / 'lifecycle').mkdir()
        shutil.copyfile(fixture.stage / 'setup-manifest.json', evidence / 'setup/setup-manifest.json')
        PREVIEW.write_json(evidence / 'lifecycle/result.json', {
            'Schema': 1, 'Passed': True, 'RollbackRequested': True,
            'AudioCheck': False, 'UpgradeRequested': False})
        self.pair = PREVIEW.read_json(self.downloads / 'installer/downloads.json')
        self.ci = {'id': 1, 'run_attempt': 2, 'status': 'completed', 'conclusion': 'success',
                   'repository': {'full_name': 'example/project'},
                   'head_repository': {'full_name': 'example/project'},
                   'head_sha': self.pair['SourceCommit'], 'head_branch': 'master', 'event': 'push',
                   'path': '.github/workflows/ci.yml', 'html_url': self.pair['RunURL']}
        self.destination = self.downloads.parent / 'preview'
        self.tag = 'windows-preview-2026-09-20'
        original_run = PREVIEW.run

        def command(*args, **kwargs):
            if args[:3] == ('gh', 'repo', 'view'):
                return 'example/project'
            if args[:3] == ('gh', 'run', 'download'):
                kind = next(k for k, v in PREVIEW.ARTIFACTS.items() if v == args[args.index('--name') + 1])
                shutil.copytree(self.downloads / kind, args[args.index('--dir') + 1])
                return ''
            return original_run(*args, **kwargs)

        self.addCleanup(mock.patch.stopall)
        mock.patch.object(PREVIEW, 'run', side_effect=command).start()
        mock.patch.object(PREVIEW, 'api', return_value=self.ci).start()
        git = self.fixture.fixture.fixture.git
        git('config', 'user.name', 'Preview fixture')
        git('config', 'user.email', 'preview@example.invalid')
        git('remote', 'add', 'origin', 'https://github.com/example/project.git')

    def prepare(self):
        return PREVIEW.prepare(self.root, 'origin', 1, self.tag, self.destination)

    def test_preparation_preserves_ci_bytes_and_does_not_publish(self):
        receipt = self.prepare()
        assets = self.destination / 'assets'
        self.assertEqual(receipt['SourceCommit'], self.ci['head_sha'])
        self.assertEqual(PREVIEW.sha256(assets / self.pair['Installer']), self.pair['InstallerSHA256'])
        self.assertEqual(PREVIEW.sha256(assets / self.pair['SourceArchive']), self.pair['SourceArchiveSHA256'])
        notes = (assets / 'README-preview.md').read_text()
        self.assertIn(f'/releases/download/{self.tag}/{self.pair["SourceArchive"]}', notes)
        self.assertIn('Start > Emacsvox Windows', notes)
        self.assertIn('Emacs 31.1, Omnivox 1.12.0', notes)
        self.assertIn('not a new stable Emacsvox release', notes)
        self.assertNotIn('download the emacsvox-windows-sources artifact', notes)
        self.assertEqual(subprocess.check_output(['git', 'tag', '--list'], cwd=self.root), b'')
        self.assertEqual(subprocess.check_output(['git', 'status', '--porcelain'], cwd=self.root), b'')
        for call in PREVIEW.run.call_args_list:
            self.assertNotEqual(call.args[:2], ('gh', 'release'))

    def test_requires_the_whole_trusted_ci_run_to_pass(self):
        for change in [{'conclusion': 'failure'}, {'status': 'in_progress'},
                       {'event': 'pull_request'}, {'head_branch': 'feature'},
                       {'head_repository': {'full_name': 'someone/fork'}},
                       {'path': '.github/workflows/spelling.yml'}]:
            with self.subTest(change=change), mock.patch.object(PREVIEW, 'api', return_value=self.ci | change):
                with self.assertRaises(ValueError):
                    self.prepare()
                self.assertFalse(self.destination.exists())

    def test_mismatched_source_commit_is_rejected(self):
        self.ci['head_sha'] = '0' * 40
        with self.assertRaisesRegex(ValueError, 'successful CI run'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_incomplete_native_checks_are_rejected(self):
        path = self.downloads / 'evidence/lifecycle/result.json'
        lifecycle = PREVIEW.read_json(path)
        lifecycle['RollbackRequested'] = False
        PREVIEW.write_json(path, lifecycle)
        with self.assertRaisesRegex(ValueError, 'lifecycle checks'):
            self.prepare()

    def test_dirty_checkout_and_existing_output_are_preserved(self):
        marker = self.root / 'personal-note'
        marker.write_text('preserve')
        with self.assertRaisesRegex(ValueError, 'clean committed'):
            self.prepare()
        self.assertEqual(marker.read_text(), 'preserve')
        self.destination.mkdir()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()
        self.assertTrue(self.destination.exists())

    def test_corrupt_installer_is_rejected(self):
        (self.downloads / 'installer' / self.pair['Installer']).write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'Installer checksum'):
            self.prepare()

    def test_self_consistent_source_tampering_is_rejected_against_git(self):
        path = self.downloads / 'sources' / self.pair['SourceArchive']
        with zipfile.ZipFile(path) as archive:
            entries = [(info, archive.read(info.filename)) for info in archive.infolist()]
        changed = 'emacsvox/lisp/emacsvox-setup.el'
        inventory = json.loads(next(data for info, data in entries if info.filename == 'source-manifest.json'))
        for item in inventory['Files']:
            if item['Path'] == changed:
                item['SHA256'] = hashlib.sha256(b'changed').hexdigest()
        with zipfile.ZipFile(path, 'w') as archive:
            for info, data in entries:
                if info.filename == changed:
                    data = b'changed'
                elif info.filename == 'source-manifest.json':
                    data = json.dumps(inventory).encode()
                archive.writestr(info, data)
        self.pair['SourceArchiveSHA256'] = PREVIEW.sha256(path)
        path.with_suffix('.zip.sha256').write_text(f'{PREVIEW.sha256(path)}  {path.name}\n')
        for kind in ['installer', 'sources']:
            PREVIEW.write_json(self.downloads / kind / 'downloads.json', self.pair)
        with self.assertRaisesRegex(ValueError, 'differs from Git'):
            self.prepare()

    def test_changed_prepared_asset_is_rejected(self):
        self.prepare()
        (self.destination / 'assets/README-preview.md').write_text('edited')
        with self.assertRaisesRegex(ValueError, 'Prepared preview changed'):
            PREVIEW.check(self.root, 'origin', self.destination)

    def test_stable_tag_cannot_use_preview_path(self):
        self.tag = '2026.9.6'
        with self.assertRaisesRegex(ValueError, 'separate windows-preview'):
            self.prepare()

    def test_tag_is_annotated_unsigned_and_uses_installer_source(self):
        # Publication tooling may be newer than the immutable installer source.
        (self.root / 'publication-tool').write_text('later tool')
        self.fixture.commit()
        receipt = self.prepare()
        with mock.patch.object(PREVIEW, 'remote_tag', return_value=None), \
                mock.patch.object(PREVIEW, 'existing_release', return_value=None):
            PREVIEW.create_tag(self.root, 'origin', receipt)
            with self.assertRaisesRegex(ValueError, 'already exists'):
                PREVIEW.create_tag(self.root, 'origin', receipt)
        ref = 'refs/tags/' + self.tag
        self.assertEqual(PREVIEW.run('git', 'cat-file', '-t', ref, root=self.root), 'tag')
        self.assertEqual(PREVIEW.run('git', 'rev-parse', ref + '^{commit}', root=self.root), self.ci['head_sha'])
        self.assertNotIn('BEGIN PGP SIGNATURE', PREVIEW.run('git', 'cat-file', '-p', ref, root=self.root))

    def test_draft_upload_failure_cannot_publish_and_can_resume(self):
        receipt = self.prepare()
        with mock.patch.object(PREVIEW, 'remote_tag', return_value=None), \
                mock.patch.object(PREVIEW, 'existing_release', return_value=None):
            PREVIEW.create_tag(self.root, 'origin', receipt)
        release = {'draft': True, 'prerelease': True, 'tag_name': self.tag,
                   'target_commitish': self.ci['head_sha'], 'assets': [],
                   'body': (self.destination / 'assets/README-preview.md').read_text(),
                   'html_url': 'https://github.com/example/project/releases/tag/' + self.tag}
        commands = []
        original_run = PREVIEW.run

        def command(*args, **kwargs):
            commands.append(args)
            if args[:2] == ('git', 'push'):
                return ''
            if args[:3] == ('gh', 'release', 'upload'):
                raise RuntimeError('upload interrupted')
            return original_run(*args, **kwargs)

        tag_object = PREVIEW.run('git', 'rev-parse', 'refs/tags/' + self.tag, root=self.root)
        with mock.patch.object(PREVIEW, 'run', side_effect=command), \
                mock.patch.object(PREVIEW, 'remote_tag', return_value=tag_object), \
                mock.patch.object(PREVIEW, 'existing_release', return_value=release):
            with self.assertRaisesRegex(RuntimeError, 'upload interrupted'):
                PREVIEW.publish(self.root, 'origin', self.destination, receipt)
            self.assertFalse(any(args[:3] == ('gh', 'release', 'edit') for args in commands))
            release['assets'] = [{'name': name, 'state': 'uploaded', 'digest': 'sha256:' + digest}
                                 for name, digest in receipt['Files'].items()]

            def resume(*args, **kwargs):
                commands.append(args)
                if args[:2] == ('git', 'push'):
                    return ''
                if args[:3] == ('gh', 'release', 'edit'):
                    self.assertIn('--prerelease', args)
                    self.assertIn('--latest=false', args)
                    self.assertIn('--repo', args)
                    self.assertIn('example/project', args)
                    release['draft'] = False
                    return ''
                return original_run(*args, **kwargs)

            with mock.patch.object(PREVIEW, 'run', side_effect=resume):
                self.assertEqual(PREVIEW.publish(self.root, 'origin', self.destination, receipt), release['html_url'])
            with self.assertRaisesRegex(ValueError, 'matching unpublished preview'):
                PREVIEW.publish(self.root, 'origin', self.destination, receipt)

    def test_foreign_or_corrupt_draft_is_not_overwritten(self):
        receipt = self.prepare()
        release = {'draft': True, 'prerelease': True, 'tag_name': self.tag,
                   'target_commitish': self.ci['head_sha'], 'body': 'reviewed notes', 'assets': []}
        for change in [{'draft': False}, {'prerelease': False}, {'body': 'foreign notes'},
                       {'assets': [{'name': self.pair['Installer'], 'state': 'uploaded', 'digest': 'sha256:wrong'}]}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                PREVIEW.checked_draft(release | change, receipt, 'reviewed notes')

    def test_new_draft_uploads_sources_before_binary_and_publishes_last(self):
        receipt = self.prepare()
        with mock.patch.object(PREVIEW, 'remote_tag', return_value=None), \
                mock.patch.object(PREVIEW, 'existing_release', return_value=None):
            PREVIEW.create_tag(self.root, 'origin', receipt)
        tag_object = PREVIEW.run('git', 'rev-parse', 'refs/tags/' + self.tag, root=self.root)
        release = None
        mutations = []
        original_run = PREVIEW.run

        def command(*args, **kwargs):
            nonlocal release
            if args[:2] == ('git', 'push'):
                mutations.append('push')
                return ''
            if args[:2] == ('gh', 'release'):
                mutations.append(args[2])
                self.assertIn('example/project', args)
                if args[2] == 'create':
                    self.assertIn('--verify-tag', args)
                    self.assertIn('--draft', args)
                    self.assertIn('--prerelease', args)
                    self.assertIn('--latest=false', args)
                    release = {'draft': True, 'prerelease': True, 'tag_name': self.tag,
                               'target_commitish': 'master', 'assets': [],
                               'body': (self.destination / 'assets/README-preview.md').read_text(),
                               'html_url': 'https://github.com/example/project/releases/tag/' + self.tag}
                elif args[2] == 'upload':
                    for name in args[6:]:
                        filename = PREVIEW.Path(name).name
                        if filename.endswith('.exe'):
                            self.assertIn(self.pair['SourceArchive'], [a['name'] for a in release['assets']])
                        release['assets'].append({'name': filename, 'state': 'uploaded',
                                                  'digest': 'sha256:' + receipt['Files'][filename]})
                elif args[2] == 'edit':
                    self.assertEqual(len(release['assets']), len(receipt['Files']))
                    self.assertIn('--draft=false', args)
                    self.assertIn('--prerelease', args)
                    self.assertIn('--latest=false', args)
                    release['draft'] = False
                return ''
            return original_run(*args, **kwargs)

        with mock.patch.object(PREVIEW, 'run', side_effect=command), \
                mock.patch.object(PREVIEW, 'remote_tag', return_value=tag_object), \
                mock.patch.object(PREVIEW, 'existing_release', side_effect=lambda *args: release):
            PREVIEW.publish(self.root, 'origin', self.destination, receipt)
        self.assertEqual(mutations, ['push', 'create', 'upload', 'upload', 'edit'])


if __name__ == '__main__':
    unittest.main()
