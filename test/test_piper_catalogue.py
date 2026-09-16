# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline regressions for pinned catalogue discovery and promotion gates."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("piper_catalogue", Path(__file__).resolve().parents[1] / "utils/omnivox-piper-catalogue.py")
CAT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAT)


class PiperCatalogueTests(unittest.TestCase):
    def fixture(self, name="kristin", speakers=1):
        key = f"en_US-{name}-medium"
        directory = f"en/en_US/{name}/medium"
        content = {directory + "/" + key + ".onnx": b"fixture model",
                   directory + "/" + key + ".onnx.json": json.dumps({"num_speakers": speakers, "audio": {"sample_rate": 22050}}).encode(),
                   directory + "/MODEL_CARD": b"Dataset terms and model provenance.\n"}
        index = {key: {"name": name, "language": {"code": "en_US", "name_english": "English"},
                       "quality": "medium", "num_speakers": speakers, "speaker_id_map": {},
                       "files": {p: {"size_bytes": len(data)} for p, data in content.items()}}}
        repo = {"sha": "a" * 40, "siblings": [{"rfilename": p, "size": len(data),
                "blobId": hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest(),
                **({"lfs": {"sha256": hashlib.sha256(data).hexdigest()}} if p.endswith(".onnx") else {})}
                for p, data in content.items()]}
        return index, repo, content

    def prepared(self, work):
        index, repo, content = self.fixture()
        doc = CAT.build_records(index, repo)
        record = doc["records"][0]
        def fetch(url, **_):
            return io.BytesIO(content[url.split("/resolve/" + "a" * 40 + "/")[1]])
        with patch.object(CAT.urllib.request, "urlopen", side_effect=fetch):
            CAT.metadata(work, record)
            CAT.review(record, "Model card reviewed; dataset terms retained", "fixture reviewer")
            CAT.download(work, record, "model")
        return doc, record

    def evidence(self, work, record):
        path = work / "validation" / "evidence.json"
        CAT.write(path, {"test": "native evidence"})
        record["validation"] = {"status": "passed", "entry_sha256": CAT.digest(record["entry"]),
                                "evidence": str(path.relative_to(work)),
                                "evidence_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        return path

    def test_discovery_preserves_existing_identity_and_separates_speakers(self):
        index, repo, _ = self.fixture(speakers=3)
        record = CAT.build_records(index, repo)["records"][0]
        self.assertEqual("piper-en-us-kristin-medium", record["entry"]["id"])
        self.assertEqual([0, 1, 2], [v["speaker_index"] for v in record["entry"]["voices"]])
        self.assertEqual("piper:v1/c/piper-en-us-kristin-medium/0", record["entry"]["voices"][0]["physical_id"])
        self.assertEqual({}, record["verified"])
        self.assertEqual("pending", record["review"]["status"])

    def test_excess_speakers_are_retained_but_blocked(self):
        index, repo, _ = self.fixture(speakers=904)
        record = CAT.build_records(index, repo)["records"][0]
        self.assertEqual(904, len(record["entry"]["voices"]))
        self.assertIn("256", record["blocked"])

    def test_unicode_names_get_stable_ascii_identifiers(self):
        index, repo, _ = self.fixture(name="tugão")
        record = CAT.build_records(index, repo)["records"][0]
        self.assertIn("u00e3", record["entry"]["id"])
        self.assertIn("%C3%A3", record["entry"]["files"][0]["url"])

    def test_moving_revision_mismatched_size_and_ambiguous_speakers_rejected(self):
        index, repo, _ = self.fixture(speakers=2)
        bad = copy.deepcopy(repo)
        bad["sha"] = "main"
        with self.assertRaisesRegex(ValueError, "immutable"):
            CAT.build_records(index, bad)
        bad = copy.deepcopy(repo)
        bad["siblings"][0]["size"] += 1
        with self.assertRaisesRegex(ValueError, "size"):
            CAT.build_records(index, bad)
        index[next(iter(index))]["speaker_id_map"] = {"one": 0, "two": 0}
        with self.assertRaisesRegex(ValueError, "speaker"):
            CAT.build_records(index, repo)

    def test_corrupt_download_is_not_cached_or_verified(self):
        index, repo, _ = self.fixture()
        record = CAT.build_records(index, repo)["records"][0]
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            with patch.object(CAT.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong")):
                with self.assertRaises(ValueError):
                    CAT.download(work, record, "model")
            self.assertFalse(CAT.asset_path(work, record, "model").exists())
            self.assertFalse(list(work.rglob("*.part")))
            self.assertNotIn("model", record["verified"])

    def test_cached_asset_is_rehashed_before_native_loading(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            _, record = self.prepared(work)
            CAT.asset_path(work, record, "model").write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                CAT.download(work, record, "model")

    def test_review_requires_metadata_and_promotion_requires_native_evidence(self):
        index, repo, _ = self.fixture()
        record = CAT.build_records(index, repo)["records"][0]
        with self.assertRaisesRegex(ValueError, "model-card"):
            CAT.review(record, "review", "person")
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            doc, record = self.prepared(work)
            self.assertTrue(CAT.validation_ready(record))
            self.assertFalse(CAT.approved(work, record))
            with self.assertRaisesRegex(ValueError, "No entries"):
                CAT.export(work, doc, work / "out")
            evidence = self.evidence(work, record)
            self.assertTrue(CAT.approved(work, record))
            evidence.write_text("changed")
            self.assertFalse(CAT.approved(work, record))

    def test_changed_source_terms_or_voice_set_invalidates_approval(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            _, record = self.prepared(work)
            self.evidence(work, record)
            for field, value in (("licence", "changed terms"), ("source_revision", "b" * 40), ("voices", [])):
                changed = copy.deepcopy(record)
                changed["entry"][field] = value
                self.assertFalse(CAT.approved(work, changed))

    def test_export_only_contains_approved_entries_in_native_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            doc, record = self.prepared(work)
            self.evidence(work, record)
            pending = copy.deepcopy(record)
            pending["review"] = {"status": "pending"}
            doc["records"].append(pending)
            self.assertEqual(1, CAT.export(work, doc, work / "out"))
            manifest = CAT.read(work / "out" / "manifest.json")
            catalogue = CAT.read(work / "out" / manifest["catalogues"][0])
            self.assertEqual([record["entry"]], catalogue["entries"])
            self.assertEqual({"schema_version", "revision", "entries"}, set(catalogue))
            self.assertNotIn("review", catalogue["entries"][0])

    def test_export_shards_by_native_count_and_actual_encoded_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            doc, record = self.prepared(work)
            doc["records"] = []
            for i in range(129):
                item = copy.deepcopy(record)
                item["entry"]["id"] += f"-{i}"
                item["entry"]["description"] = "é" * 2000
                doc["records"].append(item)
            with patch.object(CAT, "approved", return_value=True):
                self.assertEqual(129, CAT.export(work, doc, work / "out"))
            manifest = CAT.read(work / "out" / "manifest.json")
            self.assertGreater(len(manifest["catalogues"]), 1)
            for name in manifest["catalogues"]:
                path = work / "out" / name
                self.assertLessEqual(path.stat().st_size, 1024 * 1024)
                self.assertLessEqual(len(CAT.read(path)["entries"]), 128)
            old = (work / "out" / manifest["catalogues"][0]).read_bytes()
            doc["records"][0]["entry"]["name"] = "New review"
            with patch.object(CAT, "approved", return_value=True):
                CAT.export(work, doc, work / "out")
            self.assertEqual(old, (work / "out" / manifest["catalogues"][0]).read_bytes())
            for item in doc["records"]:
                item["entry"]["description"] = "é" * 4500
            with patch.object(CAT, "approved", return_value=True):
                CAT.export(work, doc, work / "out")
                manifest = CAT.read(work / "out" / "manifest.json")
                for name in manifest["catalogues"]:
                    self.assertLessEqual((work / "out" / name).stat().st_size, 1024 * 1024)
                preceding = (work / "out" / "manifest.json").read_bytes()
                doc["records"][0]["entry"]["description"] = "é" * 600000
                with self.assertRaisesRegex(ValueError, "One entry"):
                    CAT.export(work, doc, work / "out")
                self.assertEqual(preceding, (work / "out" / "manifest.json").read_bytes())

    @unittest.skipIf(sys.platform == "win32", "Executable fixture uses a POSIX shebang")
    def test_native_report_must_match_generation_and_confirm_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            _, record = self.prepared(work)
            server = work / "validator-fixture"
            script = '''import sys,json,hashlib
from pathlib import Path
args=sys.argv
generation=Path(args[args.index('--validate-voice-library')+1])
report=Path(args[args.index('--validation-report')+1])
report.write_text(json.dumps({'kind':'native-validation-observation',
 'cleanup_confirmed': CLEANUP, 'snapshot': {'generation_sha256': DIGEST,
 'os':'fixture', 'arch':'fixture', 'validator':{'sha256':'fixture'}}}))
'''
            for cleanup, checksum, accepted in (
                    ("True", "hashlib.sha256(generation.read_bytes()).hexdigest()", True),
                    ("False", "hashlib.sha256(generation.read_bytes()).hexdigest()", False),
                    ("True", "'wrong generation'", False)):
                server.write_text(f"#!{sys.executable}\n" + script.replace("CLEANUP", cleanup).replace("DIGEST", checksum))
                server.chmod(0o700)
                candidate = copy.deepcopy(record)
                if accepted:
                    CAT.native_validate(work, candidate, server, server, 1, 256)
                    self.assertTrue(CAT.approved(work, candidate))
                else:
                    with self.assertRaisesRegex(ValueError, "evidence"):
                        CAT.native_validate(work, candidate, server, server, 1, 256)
                    self.assertFalse(CAT.approved(work, candidate))
            server.write_text(f"#!{sys.executable}\nimport sys\nprint('Error: unsupported phoneme type')\nsys.exit(1)\n")
            with self.assertRaisesRegex(ValueError, "unsupported phoneme type"):
                CAT.native_validate(work, copy.deepcopy(record), server, server, 1, 256)

    @unittest.skipIf(sys.platform == "win32", "WSL-specific path check")
    def test_windows_validation_requires_native_report_filesystem(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            _, record = self.prepared(work)
            with patch.object(CAT.subprocess, "check_output", return_value="\\\\wsl.localhost\\Ubuntu\\work\n"):
                with self.assertRaisesRegex(ValueError, "native Windows filesystem"):
                    CAT.native_validate(work, record, work / "omnivox.exe", work / "helper.exe", 1, 256)


if __name__ == "__main__":
    unittest.main()
