"""Exercise publication checks with synthetic paths, tokens, and Git blobs."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import gzip
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "utils/emacsvox-privacy-check.py"
SPEC = importlib.util.spec_from_file_location("privacy_check", SCRIPT)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)
PERSON = b"fixture-person"
LINUX_HOME = b"/home/" + PERSON
TOKEN = b"eyJabc." + b"eyJdef." + b"x" * 16


class PrivacyCheckTests(unittest.TestCase):
    def test_home_directories_across_platforms(self):
        for prefix in (b"/home/", b"/Users/", b"/mnt/d/Users/", b"C:/Users/",
                       b"D:\\Users\\", b"C:\\\\Users\\\\", b"file:///Users/"):
            with self.subTest(prefix=prefix):
                content = b"ok\n" + prefix + PERSON + b"/project"
                self.assertEqual(list(CHECK.inspect_blob("fixture", content)),
                                 [(":2", "personal home directory")])
        utf16 = LINUX_HOME.decode().encode("utf-16")
        self.assertEqual(list(CHECK.inspect_blob("windows.log", utf16)),
                         [(":1", "personal home directory")])

    def test_public_urls_placeholders_and_key_are_allowed(self):
        content = (b"https://example.org/users/contributors\n"
                   b"ftp://example.org/home/contributors\n"
                   b"/home/${USER}\n/mnt/c/Users/example/bin\n"
                   b"-----BEGIN PGP PUBLIC KEY BLOCK-----")
        self.assertEqual(list(CHECK.inspect_blob("guide", content)), [])

    def test_tokens_and_keys(self):
        cases = ((TOKEN, "signed token"),
                 (b"https://example.org/?partnertok=" + PERSON, "listener token"),
                 (b"-----BEGIN OPENSSH " + b"PRIVATE KEY-----", "private key"),
                 (b"fixture." + b"ts.net", "private VPN hostname"))
        for data, label in cases:
            self.assertEqual(list(CHECK.inspect_blob("fixture", data)), [(":1", label)])

    def test_nested_archives_report_position_without_member_text(self):
        tar = io.BytesIO()
        with tarfile.open(fileobj=tar, mode="w:gz") as archive:
            content = b"ok\n" + LINUX_HOME
            member = tarfile.TarInfo("private-transcript.txt")
            member.size = len(content)
            archive.addfile(member, io.BytesIO(content))
        outer = io.BytesIO()
        with zipfile.ZipFile(outer, "w") as archive:
            archive.writestr("capture.tar.gz", tar.getvalue())
        findings = list(CHECK.inspect_blob("evidence.zip", outer.getvalue()))
        self.assertEqual(findings, [(" member 1 member 2:2", "personal home directory")])

    def test_raw_speech_evidence_even_without_a_recognisable_secret(self):
        self.assertEqual(list(CHECK.inspect_blob("docs/evidence/session-events.eld", b"()")),
                         [("", "raw speech session capture")])
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("logs/session-snapshot.eld", "()")
        self.assertEqual(list(CHECK.inspect_blob("docs/evidence/results.zip", data.getvalue())),
                         [(" member 1", "raw speech session capture")])

    def test_symlink_is_scanned_as_a_target_path(self):
        self.assertEqual(list(CHECK.inspect_blob("latest.zip", b"other.zip", symlink=True)), [])
        self.assertEqual(list(CHECK.inspect_blob("latest.zip", LINUX_HOME, symlink=True)),
                         [(":1", "personal home directory")])

    def test_cannot_silently_skip_a_broken_or_oversized_archive(self):
        with patch.object(CHECK, "EXPANDED_LIMIT", 16):
            for name, blob in (("data.gz", gzip.compress(b"x" * 17)),
                               ("broken.zip", b"not a zip"), ("broken.tar.gz", b"incomplete")):
                self.assertEqual(list(CHECK.inspect_blob(name, blob)),
                                 [("", "archive unreadable or exceeds privacy scan limits")])

    def test_heritage_exceptions_cover_only_the_reviewed_file_and_line(self):
        path = "stumpwm/stumpwmrc"
        source = (SCRIPT.parents[1] / path).read_bytes().splitlines()
        line = next(row for row in source if b"/home/" in row and b"end-session" in row)
        self.assertEqual(list(CHECK.text_findings(path, line)), [])
        for name, content in ((path, line + b" " + LINUX_HOME), ("copied", line)):
            self.assertEqual(list(CHECK.text_findings(name, content)),
                             [(1, "personal home directory")])

    def test_git_index_is_scanned_without_exposing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            staged = repo / "notes.txt"
            staged.write_bytes(LINUX_HOME + b"\n" + TOKEN)
            subprocess.run(["git", "add", "--", staged.name], check=True, cwd=repo)
            staged.write_text("clean version on disk\n")
            result = subprocess.run([sys.executable, SCRIPT], cwd=repo, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn(b"'notes.txt':2: signed token", result.stdout)
            for private in (PERSON, TOKEN):
                self.assertNotIn(private, result.stdout + result.stderr)
            (repo / "untracked").write_bytes(LINUX_HOME)
            subprocess.run(["git", "add", "--", staged.name], check=True, cwd=repo)
            subprocess.run([sys.executable, SCRIPT], cwd=repo, check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
