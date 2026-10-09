"""Check transfer of pinned container outputs to host-side inventory staging."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "servers/omnivox-release/build-tgspeechbox.py"
SPEC = importlib.util.spec_from_file_location("tgspeechbox_build", SCRIPT)
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class ContainerTransferTests(unittest.TestCase):
    def test_paths_cannot_escape_the_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(RuntimeError, "outside the repository"):
                build.inside(root, "../unexpected")

    def test_only_unchanged_outputs_reach_inventory_generation(self):
        for alteration in (None, "binary", "data", "source"):
            with self.subTest(alteration=alteration), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                output = root / "target/emacsvox-release"
                data = output / "espeak/share/espeak-ng-data"
                data.mkdir(parents=True)
                (data / "phontab").write_bytes(b"phonemes")
                executable = output / "helper.exe"
                executable.write_bytes(b"built helper")
                lock = root / "omnivox-tgspeechbox-sys/source-inputs.json"
                lock.parent.mkdir()
                lock.write_text("locked input")
                record = dict(schema_version=1, target=build.TARGET, commit="commit",
                              source_lock_sha256=build.digest(lock),
                              executable=executable.relative_to(root).as_posix(),
                              espeak_output="target/emacsvox-release/espeak",
                              executable_sha256=build.digest(executable),
                              espeak_data_sha256=build.data_digest(data))
                (output / "tgspeechbox-build.json").write_text(json.dumps(record))
                if alteration == "binary":
                    executable.write_bytes(b"changed helper")
                elif alteration == "data":
                    (data / "phontab").write_bytes(b"changed data")
                elif alteration == "source":
                    lock.write_text("different inputs")
                tg = Mock()
                tg.prepare_source.return_value = (root / "source", {})
                tg.git_output.return_value = "commit"
                with patch.dict("sys.modules", {"build_tgspeechbox": tg}), \
                     patch("sys.argv", [str(SCRIPT), "stage", "--repository", str(root)]), \
                     patch("sys.path", list(__import__("sys").path)):
                    if alteration:
                        with self.assertRaises(RuntimeError):
                            build.main()
                        tg.stage.assert_not_called()
                    else:
                        build.main()
                        tg.stage.assert_called_once_with(
                            root, executable, output / "espeak", build.TARGET, root / "source", {})


if __name__ == "__main__":
    unittest.main()
