"""Exercise public Make staging targets with private payloads and tool boundaries.

No compiler, Docker daemon, Windows process, live runtime, or personal cache is
used. Hashing, copying, Make, Git, provenance, and activation are real.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "test/fixtures/windows-staging/tool.py"
TARGET = "x86_64-pc-windows-gnu"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fields(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines())


class WindowsStagingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="emacsvox staging test ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.emacsvox = self.root / "emacsvox source"
        self.omnivox = self.root / "omnivox source"
        self.release = self.emacsvox / "servers/omnivox-release"
        self.runtime = self.emacsvox / "servers/omnivox-bin"
        self.output = self.omnivox / "target/emacsvox-release"
        self.binaries = self.output / TARGET / "release"
        self.local = self.root / "Local App Data"
        self.events_file = self.root / "events.jsonl"
        self.env = {
            "PATH": str(self.root / "tools") + ":/usr/bin:/bin",
            "HOME": str(self.root / "home"), "LC_ALL": "C.UTF-8",
            "TMPDIR": str(self.root / "tmp"),
            "STAGING_EVENTS": str(self.events_file),
            "STAGING_LOCAL_APP_DATA": str(self.local),
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_DATE": "2026-09-07T00:00:00Z",
            "GIT_COMMITTER_DATE": "2026-09-07T00:00:00Z",
        }
        for path in (self.release, self.omnivox, self.local, self.root / "tools",
                     self.root / "home", self.root / "tmp"):
            path.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "Makefile", self.emacsvox / "Makefile")
        shutil.copy2(ROOT / "servers/omnivox-release/toolchain.lock",
                     self.release / "toolchain.lock")
        for name in ("stage-main-dev.sh", "stage-runtime.sh"):
            source = ROOT / "servers/omnivox-release" / name
            if source.exists():
                shutil.copy2(source, self.release / name)
        self.lock = {
            line.split("=", 1)[0]: line.split("=", 1)[1]
            for line in (self.release / "toolchain.lock").read_text().splitlines()
            if line and not line.startswith("#")
        }
        self.piper = (self.release / "cache" / ("piper-" + self.lock["omnivox_piper_version"])
                      / ("companion-" + self.lock["omnivox_piper_archive_sha256"]) / "piper")
        self.env["STAGING_PIPER_DIR"] = str(self.piper)
        for name in ("docker", "powershell.exe", "wslpath", "cp", "mv",
                     "x86_64-w64-mingw32-objdump", "x86_64-w64-mingw32-g++-posix"):
            self.tool(self.root / "tools" / name)
        for name in ("verify-toolchain.sh", "verify-helper-determinism.sh",
                     "prepare-piper-companion.sh", "prepare-piper-development-companion.sh",
                     "verify-runtime.sh", "verify-runtime-live.sh", "verify-main-live.sh"):
            self.tool(self.release / name)
        for repository in (self.emacsvox, self.omnivox):
            self.write(repository / "tracked-input", "unchanged\n")
            self.git(repository, "init", "-q")
            self.git(repository, "add", "tracked-input")
            self.git(repository, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "-qm", "fixture")
        self.write(self.emacsvox / "servers/omnivox", "fixture launcher\n")
        for path in (self.release / "Dockerfile", self.omnivox / "Cargo.lock",
                     self.omnivox / "LICENSE", self.omnivox / "windows-helpers/COPYING",
                     self.omnivox / "windows-helpers/bin/OmnivoxEloquenceHelper32.exe",
                     self.omnivox / "windows-helpers/bin/OmnivoxDectalkHelper32.exe",
                     self.binaries / "omnivox.exe", self.binaries / "omnivox.unstripped.exe",
                     self.output / "windows-runtime/libstdc++-6.dll",
                     self.output / "windows-runtime/libgcc_s_seh-1.dll",
                     self.piper / "omnivox-piper-helper.exe", self.piper / "espeak-ng-data/phontab"):
            self.write(path, path.name + " fixture\n")
        self.csc = self.release / "cache" / ("roslyn-" + self.lock["roslyn_version"]) / "tasks/net472/csc.exe"
        self.write(self.csc, "fixture csc\n")
        self.espeak = self.output / "release/build/espeak-rs-sys-fixture/out/share/espeak-ng-data"
        self.write(self.espeak / "phontab", "phonemes\n")
        for companion, license_name in (("rhvoice", "RHVoice-LICENSE.txt"),
                                        ("flite", "Flite-COPYING.txt"),
                                        ("rutts", "RuTTS-LICENSE.txt"),
                                        ("tgspeechbox", "TGSpeechBox-LICENSE.txt")):
            directory = self.binaries / companion
            for name in (f"omnivox-{companion}-helper.exe", "SOURCE-PROVENANCE.json",
                         "SHA256SUMS", "third-party-licenses/" + license_name):
                self.write(directory / name, name + " fixture\n")
        for name in ("VOICE-INVENTORY.json", "VOICE-INVENTORY-22050.json",
                     "VOICE-INVENTORY-44100.json", "espeak-ng-data/phontab", "packs/lang/en-us.yaml",
                     "third-party-licenses/eSpeak-NG-GPL-3.0.txt"):
            self.write(self.binaries / "tgspeechbox" / name, name + " fixture\n")
        self.write(self.omnivox / "tools/build_tgspeechbox.py",
                   "import os\nwith open(os.environ['STAGING_EVENTS'], 'a') as f:\n"
                   "    f.write('\"build-tgspeechbox\"\\n')\n")
        self.write(self.binaries / "flite/voice sample.txt", "payload with spaces\n")

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def tool(self, path):
        shutil.copy2(TOOL, path)
        path.chmod(0o755)

    def git(self, root, *args):
        return subprocess.run(["git", "-C", str(root), *args], env=self.env,
                              capture_output=True, text=True, check=True).stdout.strip()

    def stage(self, target="windows-omnivox", *variables, success=True, env=None):
        self.events_file.write_text("")
        result = subprocess.run(["make", "--no-print-directory", target,
                                 "OMNIVOX_DIR=" + str(self.omnivox), *variables],
                                cwd=self.emacsvox, env={**self.env, **(env or {})},
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def events(self):
        return [json.loads(line) for line in self.events_file.read_text().splitlines()]

    def current(self):
        return (self.runtime / "current").resolve(strict=True)

    def assert_payload(self, development=False):
        current = self.current()
        provenance = fields(current / "PROVENANCE")
        self.assertEqual(current.name, provenance["build_id"])
        self.assertEqual("emacsvox-omnivox-provenance-v1", provenance["format"])
        self.assertEqual("local-dirty-worktree" if development else "release-clean-worktree",
                         provenance["build_kind"])
        self.assertEqual(self.git(self.emacsvox, "rev-parse", "HEAD"), provenance["emacsvox_commit"])
        self.assertEqual(self.git(self.omnivox, "rev-parse", "HEAD"), provenance["omnivox_commit"])
        self.assertEqual(digest(self.binaries / "omnivox.exe"), provenance["omnivox_executable_sha256"])
        self.assertEqual(digest(self.omnivox / "Cargo.lock"), provenance["cargo_lock_sha256"])
        self.assertEqual(digest(self.release / "toolchain.lock"), provenance["toolchain_lock_sha256"])
        self.assertEqual("none" if development else "piper", provenance["omnivox_features"])
        self.assertEqual("not-included" if development else "official-omnivox-release",
                         provenance["piper_companion"])
        self.assertEqual(development, (current / "tgspeechbox").exists())
        self.assertEqual(not development, (current / "piper").exists())
        self.assertFalse((current / "omnivox.unstripped.exe").exists())
        self.assertEqual((self.binaries / "omnivox.unstripped.exe").read_bytes(),
                         (self.release / "cache/diagnostics" / current.name / "omnivox.unstripped.exe").read_bytes())
        expected = {"omnivox.exe", "libstdc++-6.dll", "libgcc_s_seh-1.dll",
                    "OmnivoxEloquenceHelper32.exe", "OmnivoxDectalkHelper32.exe",
                    "WINDOWS-HELPERS-COPYING", "OMNIVOX-LICENSE", "PROVENANCE"}
        for name in ("rhvoice", "flite", "rutts", "tgspeechbox" if development else "piper"):
            source = self.piper if name == "piper" else self.binaries / name
            for path in source.rglob("*"):
                if path.is_file():
                    relative = Path(name) / path.relative_to(source)
                    expected.add(str(relative))
                    self.assertEqual(path.read_bytes(), (current / relative).read_bytes())
        manifest = dict(line.split("  ", 1)[::-1] for line in (current / "SHA256SUMS").read_text().splitlines())
        self.assertEqual(expected, set(manifest))
        windows = Path((current / "windows-runtime.path").read_text().strip()[2:])
        for name, checksum in manifest.items():
            self.assertEqual(checksum, digest(current / name))
            self.assertEqual((current / name).read_bytes(), (windows / name).read_bytes())
        self.assertTrue(os.access(current / "omnivox.exe", os.X_OK))
        cache = Path((current / "espeak-ng-data.path").read_text().strip()[2:])
        self.assertEqual("phonemes\n", (cache / "espeak-ng-data/phontab").read_text())
        self.assertEqual(provenance["espeak_data_sha256"] + "\n",
                         (cache / "omnivox-espeak-data.sha256").read_text())
        self.assertEqual(["activate", "verify-runtime.sh", "verify-runtime-live.sh"], self.events()[-3:])
        return provenance

    def test_clean_staging_and_repeatable_payload(self):
        self.stage()
        self.assert_payload()
        current = self.current()
        snapshot = {str(p.relative_to(current)): p.read_bytes() for p in current.rglob("*") if p.is_file()}
        self.stage()
        self.assertEqual(current, self.current())
        self.assertEqual(snapshot, {str(p.relative_to(current)): p.read_bytes() for p in current.rglob("*") if p.is_file()})

    def test_development_records_both_dirty_sources(self):
        for repository in (self.emacsvox, self.omnivox):
            self.write(repository / "tracked-input", "local changes\n")
        self.stage("windows-omnivox-dev")
        provenance = self.assert_payload(development=True)
        for repository, field in ((self.emacsvox, "emacsvox_worktree_sha256"),
                                  (self.omnivox, "omnivox_worktree_sha256")):
            diff = subprocess.run(["git", "-C", str(repository), "diff", "--binary", "HEAD", "--"],
                                  env=self.env, capture_output=True, check=True).stdout
            self.assertEqual(hashlib.sha256(diff).hexdigest(), provenance[field])

    def test_clean_guard_rejects_each_dirty_repository_before_building(self):
        for repository in (self.emacsvox, self.omnivox):
            for staged in (False, True):
                with self.subTest(repository=repository.name, staged=staged):
                    self.write(repository / "tracked-input", "dirty\n")
                    if staged:
                        self.git(repository, "add", "tracked-input")
                    result = self.stage(success=False)
                    self.assertIn("Refusing to stage Omnivox from tracked changes", result.stderr)
                    self.assertEqual([], self.events())
                    self.write(repository / "tracked-input", "unchanged\n")
                    self.git(repository, "add", "tracked-input")

    def test_invalid_feature_combinations_fail_before_building(self):
        for variable in ("OMNIVOX_INCLUDE_PINNED_PIPER=0", "OMNIVOX_INCLUDE_TGSPEECHBOX=1",
                         "OMNIVOX_PIPER_PREPARED=bad", "OMNIVOX_RECORD_RHVOICE=bad",
                         "OMNIVOX_PIPER_COMPANION_STATE=github-actions-native-development-build"):
            with self.subTest(variable=variable):
                self.stage("windows-omnivox", variable, success=False)
                self.assertEqual([], self.events())

    def test_missing_companion_preserves_current(self):
        self.stage()
        previous = self.current()
        (self.binaries / "flite/SHA256SUMS").unlink()
        result = self.stage(success=False)
        self.assertIn("Prepared companion file is missing", result.stderr)
        self.assertEqual(previous, self.current())
        self.assertNotIn("activate", self.events())

    def test_corrupt_existing_payload_is_rejected(self):
        self.stage()
        previous = self.current()
        self.write(previous / "omnivox.exe", "corrupt\n")
        result = self.stage(success=False)
        self.assertIn("Existing content-addressed payload differs", result.stderr)
        self.assertEqual(previous, self.current())
        self.assertNotIn("activate", self.events())

    def test_interruption_and_activation_failure_preserve_current(self):
        self.stage()
        previous = self.current()
        self.write(self.binaries / "omnivox.exe", "changed executable\n")
        self.stage(success=False, env={"STAGING_FAIL_OPERATION": "cp",
                                       "STAGING_FAIL_SUFFIX": "/omnivox.exe.new", "STAGING_INTERRUPT": "1"})
        self.assertEqual(previous, self.current())
        self.assertTrue(list((self.runtime / "versions").glob("*/omnivox.exe.new")))
        self.stage(success=False, env={"STAGING_FAIL_OPERATION": "mv", "STAGING_FAIL_SUFFIX": "/current"})
        self.assertEqual(previous, self.current())
        self.assertTrue((self.runtime / "current.new").is_symlink())
        self.stage()
        self.assertNotEqual(previous, self.current())
        self.assert_payload()

    def test_final_verification_failure_occurs_after_activation(self):
        self.stage()
        previous = self.current()
        self.write(self.binaries / "omnivox.exe", "changed executable\n")
        self.stage(success=False, env={"STAGING_FAIL_VERIFY": "verify-runtime.sh"})
        self.assertNotEqual(previous, self.current())
        self.assertEqual(["activate", "verify-runtime.sh"], self.events()[-2:])
        self.assertNotIn("verify-runtime-live.sh", self.events())

    def test_main_only_reuse_rejects_changed_companion(self):
        self.stage("windows-omnivox-dev")
        previous = self.current()
        # Only the tracked fixture input belongs to the original commit. Ignore
        # precreated build inputs so this tests one deliberate source change.
        self.write(self.omnivox / ".git/info/exclude", "*\n")
        self.write(self.omnivox / "windows-helpers/helper.cs", "changed helper\n")
        self.git(self.omnivox, "add", "-f", "windows-helpers/helper.cs")
        result = self.stage("windows-omnivox-main-dev", success=False)
        self.assertIn("Main-only staging cannot reuse companions", result.stderr)
        self.assertEqual(previous, self.current())
        self.assertNotIn("build", self.events())

    def test_optional_native_piper_and_external_voice_inputs(self):
        model = self.root / "user voices/model.onnx"
        library = self.root / "RHVoice data/RHVoice.dll"
        data = self.root / "RHVoice data/payload"
        config = self.root / "RHVoice config"
        for path in (model, Path(str(model) + ".json"), library,
                     data / "languages/en", data / "voices/alice", config / "settings"):
            self.write(path, path.name + " user input\n")
        self.write(self.emacsvox / "servers/windows-dectalk/runtime/DECtalk.dll", "dectalk\n")
        self.write(self.emacsvox / "servers/windows-dectalk/runtime/dtalk_us.dic", "dictionary\n")
        self.stage("windows-omnivox-piper-dev", "OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE=fixture.zip",
                   "OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE_SHA256=" + "a" * 64,
                   env={"OMNIVOX_PIPER_MODEL": "W:" + str(model),
                        "OMNIVOX_RHVOICE_LIBRARY": "W:" + str(library),
                        "OMNIVOX_RHVOICE_DATA": str(data), "OMNIVOX_RHVOICE_CONFIG": str(config)})
        current = self.current()
        provenance = fields(current / "PROVENANCE")
        self.assertEqual("local-dirty-worktree", provenance["build_kind"])
        self.assertEqual("github-actions-native-development-build", provenance["piper_companion"])
        self.assertEqual("external-user-supplied-windows-cache", provenance["piper_model"])
        self.assertEqual(digest(model), provenance["piper_model_sha256"])
        self.assertEqual("recorded-windows-paths", provenance["rhvoice_configuration"])
        self.assertEqual(digest(library), provenance["rhvoice_library_sha256"])
        self.assertEqual("bundled-pinned-archive", provenance["dectalk_runtime"])
        self.assertEqual("local-omnivox-experimental-build", provenance["tgspeechbox_companion"])
        self.assertEqual("dectalk\n", (current / "DECtalk.dll").read_text())
        for filename, source in (("piper-model.path", model),
                                 ("piper-model-config.path", Path(str(model) + ".json"))):
            cached = Path((current / filename).read_text().strip()[2:])
            self.assertTrue(cached.is_relative_to(self.local))
            self.assertEqual(source.read_bytes(), cached.read_bytes())
        self.assertEqual("W:" + str(library) + "\n", (current / "rhvoice-library.path").read_text())
        self.assertEqual("W:" + str(data) + "\n", (current / "rhvoice-data.path").read_text())
        self.assertEqual("W:" + str(config) + "\n", (current / "rhvoice-config.path").read_text())

    def test_invalid_external_model_configuration_does_not_activate(self):
        model = self.root / "model.onnx"
        self.write(model, "user model\n")
        result = self.stage(env={"OMNIVOX_PIPER_MODEL": str(model)}, success=False)
        self.assertIn("Piper model configuration is not adjacent", result.stderr)
        self.assertFalse((self.runtime / "current").exists())
        self.assertNotIn("activate", self.events())

    def test_mismatched_windows_cache_is_rejected(self):
        self.stage()
        previous = self.current()
        windows = Path((previous / "windows-runtime.path").read_text().strip()[2:])
        self.write(windows / "omnivox.exe", "corrupt Windows-local payload\n")
        result = self.stage(success=False)
        self.assertIn("Existing Windows-local payload differs", result.stderr)
        self.assertEqual(previous, self.current())
        self.assertNotIn("activate", self.events())


if __name__ == "__main__":
    unittest.main()
