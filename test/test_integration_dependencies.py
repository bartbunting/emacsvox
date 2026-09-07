"""Offline failure and isolation checks for the pinned integration preparer."""

# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "prepare_dependencies", Path(__file__).with_name("prepare-dependencies.py"))
PREP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREP)


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="emacsvox-deps-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.destination = self.root / "prepared with spaces"
        self.emacs = os.environ["EMACS"]
        self.version = PREP.emacs_version(self.emacs)
        self.package = {
            "name": "fixture", "commit": "a" * 40,
            "url": "https://example.invalid/fixture.tar",
            "archive_root": "fixture-source", "subdirectory": "."}
        self.lisp = (b";;; fixture.el -*- lexical-binding: t; -*-\n"
                     b";;;###autoload\n(defun fixture-answer () 42)\n"
                     b"(provide 'fixture)\n")
        self.set_archive([("fixture-source/fixture.el", self.lisp)])

    def set_archive(self, entries):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w") as archive:
            for name, body in entries:
                member = tarfile.TarInfo(name)
                if body is None:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "../../outside"
                    archive.addfile(member)
                else:
                    member.size = len(body)
                    archive.addfile(member, io.BytesIO(body))
        self.data = data.getvalue()
        self.package["sha256"] = PREP.digest(self.data)
        self.cached = self.cache / (self.package["sha256"] + ".tar")
        self.cached.write_bytes(self.data)
        self.lock_path = self.root / "lock.json"
        self.lock_path.write_text(json.dumps({"schema": 1, "packages": [self.package]}))
        self.lock, self.lock_hash = PREP.read_lock(self.lock_path)

    def prepare(self):
        with mock.patch.object(PREP.urllib.request, "urlopen", side_effect=AssertionError("network")):
            PREP.prepare(self.lock, self.lock_hash, self.destination, self.cache,
                         self.emacs, self.version)

    def test_prepares_relocatable_autoloads_and_reuses_unchanged_tree(self):
        self.prepare()
        manifest = (self.destination / "manifest.json").read_bytes()
        timestamps = {p: p.stat().st_mtime_ns for p in self.destination.rglob("*")}
        self.prepare()
        self.assertEqual(manifest, (self.destination / "manifest.json").read_bytes())
        self.assertEqual(timestamps, {p: p.stat().st_mtime_ns for p in timestamps})
        package = self.destination / "fixture"
        result = subprocess.run(
            [self.emacs, "-Q", "--batch", "-L", str(package),
             "-l", str(package / "fixture-autoloads.el"), "--eval",
             "(progn (unless (autoloadp (symbol-function 'fixture-answer)) "
             "(error \"Missing autoload\")) (princ (fixture-answer)))"],
            check=True, capture_output=True, text=True)
        self.assertEqual(result.stdout, "42")
        self.assertFalse(list(self.destination.rglob("*.elc")))

    def test_changed_files_lock_toolchain_and_recipe_are_rejected(self):
        self.prepare()
        with self.assertRaisesRegex(PREP.DependencyError, "lock changed"):
            PREP.check(self.destination, "changed", self.version)
        with self.assertRaisesRegex(PREP.DependencyError, "another Emacs"):
            PREP.check(self.destination, self.lock_hash, "0.0")
        with mock.patch.object(PREP, "preparer_hash", return_value="changed"):
            with self.assertRaisesRegex(PREP.DependencyError, "preparer changed"):
                PREP.check(self.destination, self.lock_hash, self.version)
        source = self.destination / "fixture/fixture.el"
        source.write_text("user work")
        with self.assertRaisesRegex(PREP.DependencyError, "files changed.*fixture.el"):
            self.prepare()
        self.assertEqual(source.read_text(), "user work")

    def test_added_file_executable_bit_and_symlink_are_rejected(self):
        self.prepare()
        extra = self.destination / "extra.el"
        extra.write_text("extra")
        with self.assertRaisesRegex(PREP.DependencyError, "files changed.*extra.el"):
            self.prepare()
        extra.unlink()
        source = self.destination / "fixture/fixture.el"
        source.chmod(0o755)
        with self.assertRaisesRegex(PREP.DependencyError, "files changed.*fixture.el"):
            self.prepare()
        source.chmod(0o644)
        extra.symlink_to(source)
        with self.assertRaisesRegex(PREP.DependencyError, "Unexpected symlink"):
            self.prepare()

    def test_existing_unprepared_directory_and_symlink_are_preserved(self):
        self.destination.mkdir()
        note = self.destination / "note"
        note.write_text("user work")
        with self.assertRaisesRegex(PREP.DependencyError, "Unprepared"):
            self.prepare()
        self.assertEqual(note.read_text(), "user work")
        self.destination = self.root / "linked"
        self.destination.symlink_to(note.parent, target_is_directory=True)
        with self.assertRaisesRegex(PREP.DependencyError, "Unprepared"):
            self.prepare()
        self.assertTrue(self.destination.is_symlink())

    def test_corrupt_cache_fails_without_replacing_it(self):
        self.cached.write_bytes(b"corrupt")
        with self.assertRaisesRegex(PREP.DependencyError, "Cached dependency checksum mismatch"):
            self.prepare()
        self.assertEqual(self.cached.read_bytes(), b"corrupt")
        self.assertFalse(self.destination.exists())
        self.assertFalse(list(self.root.glob(".emacsvox-test-deps-*")))

    def test_download_verifies_bytes_before_caching(self):
        self.cached.unlink()
        for payload, url, error in (
                (b"corrupt", self.package["url"], "checksum mismatch"),
                (self.data, "http://example.invalid/archive", "away from HTTPS")):
            with self.subTest(error=error):
                response = io.BytesIO(payload)
                response.geturl = lambda: url
                with mock.patch.object(PREP.urllib.request, "urlopen", return_value=response):
                    with self.assertRaisesRegex(PREP.DependencyError, error):
                        PREP.archive(self.package, self.cache)
                self.assertFalse(self.cached.exists())
        response = io.BytesIO(self.data)
        response.geturl = lambda: self.package["url"]
        with mock.patch.object(PREP.urllib.request, "urlopen", return_value=response):
            self.assertEqual(PREP.archive(self.package, self.cache).read_bytes(), self.data)

    def test_unsafe_archives_leave_no_partial_destination(self):
        for entry, body in (("fixture-source/../../outside", b"escaped"),
                            ("/absolute", b"escaped"),
                            ("fixture-source/link", None),
                            ("fixture-source/fixture.elc", b"byte-code"),
                            ("fixture-source/fixture.el", b"duplicate")):
            with self.subTest(entry=entry):
                self.set_archive([("fixture-source/fixture.el", self.lisp), (entry, body)])
                with self.assertRaises(PREP.DependencyError):
                    self.prepare()
                self.assertFalse(self.destination.exists())
                self.assertFalse((self.root / "outside").exists())
                self.assertFalse(list(self.root.glob(".emacsvox-test-deps-*")))

    def test_subdirectory_and_explicit_nonruntime_exclusions(self):
        self.package.update(subdirectory="lisp", excluded_paths=["CLAUDE.md"])
        self.set_archive([("fixture-source/lisp/fixture.el", self.lisp),
                          ("fixture-source/lisp/CLAUDE.md", None),
                          ("fixture-source/docs/link", None)])
        self.prepare()
        self.assertTrue((self.destination / "fixture/fixture.el").is_file())
        self.assertFalse((self.destination / "fixture/CLAUDE.md").exists())

    def test_emacs_failure_removes_only_owned_staging_directory(self):
        keep = self.root / ".emacsvox-test-deps-user-work"
        keep.mkdir()
        with mock.patch.object(PREP.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "emacs")):
            with self.assertRaises(subprocess.CalledProcessError):
                self.prepare()
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.root.glob(".emacsvox-test-deps-*")), [keep])


if __name__ == "__main__":
    unittest.main()
