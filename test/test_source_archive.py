"""Exercise Git's real export rules and reject incomplete source archives."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "source_archive", ROOT / "utils/emacsvox-check-source-archive.py")
ARCHIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ARCHIVE)


class SourceArchiveTests(unittest.TestCase):
    def fixture(self, work, omit=(), extra=(), links=()):
        archive = work / "fixture.tar"
        with tarfile.open(archive, "w") as output:
            for name in [n for n in ARCHIVE.REQUIRED if n not in omit] + list(extra):
                contents = b"2026.9.4\n" if name == "VERSION" else b"fixture\n"
                info = tarfile.TarInfo("emacsvox-2026.9.4/" + name)
                info.size = len(contents)
                output.addfile(info, io.BytesIO(contents))
            for name, target in links:
                info = tarfile.TarInfo("emacsvox-2026.9.4/" + name)
                info.type = tarfile.SYMTYPE
                info.linkname = target
                output.addfile(info)
        return archive

    def test_real_git_export_contains_installation_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = work / "source.tar"
            version = (ROOT / "VERSION").read_text().strip()
            environment = {**os.environ, "GIT_INDEX_FILE": str(work / "index")}
            for arguments in (["read-tree", "HEAD"], ["add", "-A"]):
                subprocess.run(["git", *arguments], cwd=ROOT, env=environment, check=True)
            fixture = subprocess.check_output(["git", "hash-object", "-w", "--stdin"],
                                              cwd=ROOT, input=b"; nested archive fixture\n").decode().strip()
            subprocess.run(["git", "update-index", "--add", "--cacheinfo",
                            f"100644,{fixture},lisp/integrations/archive-fixture.el"],
                           cwd=ROOT, env=environment, check=True)
            tree = subprocess.check_output(["git", "write-tree"], cwd=ROOT,
                                           env=environment, text=True).strip()
            subprocess.run(["git", "archive", "--worktree-attributes", "--format=tar",
                            f"--prefix=emacsvox-{version}/", f"--output={archive}", tree],
                           cwd=ROOT, check=True)
            root = ARCHIVE.extract(archive, work / "extracted tree")
            self.assertEqual((root / "lisp/integrations/archive-fixture.el").read_text(),
                             "; nested archive fixture\n")
            self.assertTrue((root / "etc/lisp-directories").is_file())
            tools = subprocess.check_output(["git", "ls-files", "utils/"], cwd=ROOT, text=True)
            for name in tools.splitlines():
                self.assertTrue((root / name).is_file(), name)
            self.assertTrue((root / "bin/emacsvox-install").stat().st_mode & 0o111)
            subprocess.run(["make", "--dry-run", "check-emacs"], cwd=root,
                           check=True, capture_output=True, text=True)

    def test_missing_helpers_rejected_before_running_installation(self):
        for missing in ("utils/emacsvox-install-common.sh",
                        "utils/emacsvox-windows-common.ps1", "utils/emacsvox-remote-startup.el"):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                with self.assertRaisesRegex(RuntimeError, "missing required files"):
                    ARCHIVE.extract(self.fixture(work, omit=(missing,)), work / "out")
                self.assertFalse((work / "out").exists())

    def test_dangling_link_to_excluded_content_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            archive = self.fixture(work, links=(("servers/linux-outloud/ladspa-asoundrc",
                                                "../../scapes/ladspa-asoundrc"),))
            with self.assertRaisesRegex(RuntimeError, "dangling source archive link"):
                ARCHIVE.extract(archive, work / "out")
            self.assertFalse((work / "out").exists())

    def test_local_configuration_bytecode_and_path_escape_rejected(self):
        for unwanted in ("local.mk", "native-install.json", "lisp/emacsvox.elc", "../escaped"):
            with self.subTest(unwanted=unwanted), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                with self.assertRaisesRegex(RuntimeError, "unexpected source archive payload"):
                    ARCHIVE.extract(self.fixture(work, extra=(unwanted,)), work / "out")
                self.assertFalse((work / "out").exists())


if __name__ == "__main__":
    unittest.main()
