"""Exercise the real Debian archive, relocation, source startup and release guard."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("package_deb", ROOT / "utils/emacsvox-package-deb.py")
DEB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEB)


class DebianPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="emacsvox deb test ")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.work = Path(cls.temporary.name)
        cls.emacs = os.environ.get("EMACS", "emacs")
        cls.archive = DEB.package(ROOT, cls.work / "dist", cls.emacs)
        cls.extracted = cls.work / "extracted"
        subprocess.run(["dpkg-deb", "-R", str(cls.archive), str(cls.extracted)], check=True)
        cls.runtime = cls.extracted / "usr/share/emacsvox"
        cls.environment = {**os.environ, "HOME": str(cls.work / "home"),
                           "XDG_CONFIG_HOME": str(cls.work / "home/.config"),
                           "XDG_CACHE_HOME": str(cls.work / "home/.cache"),
                           "EMACS": cls.emacs, "EMACSVOX_DIR": str(cls.runtime)}
        Path(cls.environment["HOME"]).mkdir()
        for key in ("OMNIVOX_PROGRAM", "TTS_PROGRAM", "EMACSVOX_REMOTE_TOKEN_FILE"):
            cls.environment.pop(key, None)

    def test_dependencies_and_source_payload(self):
        control = (self.extracted / "DEBIAN/control").read_text()
        self.assertIn("Architecture: all\n", control)
        self.assertIn("emacs-nox (>= 1:30.2)", control)
        self.assertIn("Recommends: omnivox (>= 1.7.0)\n", control)
        self.assertNotIn("omnivox", control.split("Depends: ")[1].splitlines()[0])
        self.assertTrue((self.runtime / "lisp/emacsvox-loaddefs.el").is_file())
        self.assertFalse(list(self.runtime.rglob("*.elc")))
        for name in ("local.mk", ".git", "native-install.json", "servers/omnivox-bin"):
            self.assertFalse((self.runtime / name).exists())
        for name in ("postinst", "preinst", "prerm", "postrm", "conffiles"):
            self.assertFalse((self.extracted / "DEBIAN" / name).exists())
        self.assertFalse((self.extracted / "etc").exists())
        self.assertTrue((self.runtime / "sounds/packs/chimes/open-object.ogg").is_file())
        self.assertTrue((self.runtime / "LICENSES/GPL-3.0-or-later.txt").is_file())
        self.assertIn("T. V. Raman", (self.runtime / "lisp/emacsvox.el").read_text())

    def test_remote_diagnose_needs_no_speech_engine_or_token(self):
        result = subprocess.run([str(self.runtime / "bin/emacsvox"), "--remote", "--diagnose"],
                                env=self.environment, capture_output=True, text=True, check=True)
        self.assertIn("no local server", result.stdout)
        self.assertIn(str(self.runtime), result.stdout)
        self.assertEqual([], list(Path(self.environment["HOME"]).iterdir()))

    def test_source_startup_and_offline_resources(self):
        expression = '''(progn
          (load (expand-file-name "lisp/emacsvox-loaddefs.el" emacsvox-directory))
          (require 'eww) (require 'emacsvox-eww)
          (unless (equal "hello world" (emacsvox-dom-inner-text
              '(p nil "hello " (script nil "hidden") (b nil "world"))))
            (error "DOM compatibility failed"))
          (unless (and (fboundp 'emacsvox) (featurep 'emacsvox-eww)
                       (file-readable-p (expand-file-name "emacsvox.info" emacsvox-info-directory))
                       (file-readable-p (expand-file-name "packs/chimes/open-object.ogg" emacsvox-sounds-dir)))
            (error "Installed runtime incomplete"))
          (princ "Package source startup passed"))'''
        result = subprocess.run([str(self.runtime / "bin/emacsvox"), "--", "--batch", "--eval", expression],
                                env={**self.environment, "TTS_PROGRAM": "/bin/cat"},
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("Package source startup passed", result.stdout)

    def test_reproducible_archive_and_provenance(self):
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        second = DEB.package(ROOT, self.work / "second", self.emacs)
        self.assertEqual(digest, hashlib.sha256(second.read_bytes()).hexdigest())
        self.assertIn(digest, second.with_suffix(".deb.sha256").read_text())
        provenance = json.loads((self.extracted / "usr/share/doc/emacsvox/BUILD-INFO.json").read_text())
        self.assertEqual("local development build", provenance["distribution"])
        self.assertIn(provenance["source_sha256"][:12], self.archive.name)

    def test_release_rejects_tree_without_checked_artifact(self):
        # A deliberately dirty isolated Git fixture exercises the actual release
        # guard without making assumptions about the developer checkout's state.
        with tempfile.TemporaryDirectory(prefix="emacsvox-deb-release-") as temporary:
            fixture = Path(temporary)
            subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", str(ROOT), str(fixture)], check=True)
            news = fixture / "etc/NEWS"
            news.write_text(news.read_text().replace(
                "Emacsvox Unreleased", "Emacsvox " + (fixture / "VERSION").read_text().strip()))
            (fixture / "uncommitted-note").write_text("release must refuse this tree\n")
            result = subprocess.run([
                "python3", str(ROOT / "utils/emacsvox-package-deb.py"), "--release",
                "--source", str(fixture), "--output-dir", str(self.work / "release-dist"),
                "--emacs", self.emacs], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("clean", result.stdout + result.stderr)
        self.assertFalse(list((self.work / "release-dist").glob("*.deb")))


if __name__ == "__main__":
    unittest.main()
