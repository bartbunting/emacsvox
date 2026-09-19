# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Evidence integrity, comparison semantics and isolated benchmark execution."""
import argparse
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "utils" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

benchmark = module("voice_benchmark")
server = module("voice_benchmark_server")


class BenchmarkTests(unittest.TestCase):
    def evidence(self, directory, values):
        directory.mkdir()
        raw = {"timing_samples": [{"case": "line", "dispatch_to_source_ms": value} for value in values]}
        benchmark.write_json(directory / "raw.json", raw)
        report = {"schema": 1, "workload": "test", "status": "complete", "host": {"name": "test"},
                  "emacs_version": "31", "harness": {"driver": "123"}, "runtime_inputs": {"dll": {"sha256": "abc"}},
                  "configuration": {"rate": 225, "audio_output": "null", "display": "batch", "routes": [],
                                    "targets": [{"id": "current", "environment": {"RUST_LOG": "warn", "OMNIVOX_PROGRAM": "/worker"}}]},
                  "jobs": [{"status": "complete", "report": "raw.json", "sha256": benchmark.digest(directory / "raw.json"),
                            "target": "current", "route": {"id": "eloquence"}, "flavour": "native", "mode": "warm"}]}
        report["summary"] = benchmark.summarize(report, directory)
        benchmark.write_json(directory / "index.json", report)
        return report

    def arguments(self, before, after):
        return argparse.Namespace(before=str(before), after=str(after), before_target="current", after_target="current",
                                  flavour="all", mode="all", output=None, absolute_ms=5., relative_percent=15., minimum_samples=20,
                                  fail_on_regression=True)

    def test_changed_raw_evidence_cannot_be_compared(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "run"
            self.evidence(path, [10] * 20)
            self.assertEqual(benchmark.load_report(path)["status"], "complete")
            (path / "raw.json").write_text('{"timing_samples": []}')
            with self.assertRaisesRegex(ValueError, "missing or changed"): benchmark.load_report(path)

    def test_summary_cannot_hide_a_slow_sample(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "run"
            index = self.evidence(path, [10] * 18 + [100, 200])
            key = next(iter(index["summary"]))
            self.assertEqual(index["summary"][key]["p95_ms"], 100)
            index["summary"][key]["p95_ms"] = 10
            benchmark.write_json(path / "index.json", index)
            with self.assertRaisesRegex(ValueError, "summary"): benchmark.load_report(path)

    def test_regression_requires_absolute_and_relative_thresholds(self):
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()):
            root = Path(root)
            self.evidence(root / "before", [10] * 20)
            self.evidence(root / "small", [14] * 20)
            self.evidence(root / "slow", [20] * 20)
            self.assertEqual(benchmark.compare(self.arguments(root / "before", root / "small")), 0)
            self.assertEqual(benchmark.compare(self.arguments(root / "before", root / "slow")), 1)

    def test_short_smoke_runs_do_not_prove_no_regression(self):
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()):
            root = Path(root)
            self.evidence(root / "before", [10] * 3)
            self.evidence(root / "after", [10] * 3)
            self.assertEqual(benchmark.compare(self.arguments(root / "before", root / "after")), 3)

    def test_exclusions_are_visible_and_changed_workloads_not_comparable(self):
        with tempfile.TemporaryDirectory() as root:
            index = self.evidence(Path(root) / "run", [10] * 20)
            index['preset'] = 'full'
            index['configuration']['routes'] = [{'id': 'espeak', 'exclude_cases': {'dense': 'Missing anchor'}}]
            self.assertIn('Excluded espeak/dense: Missing anchor', benchmark.markdown_summary(index))
            changed = copy.deepcopy(index)
            changed['configuration']['routes'][0].pop('exclude_cases')
            with self.assertRaisesRegex(ValueError, 'routes'): benchmark.comparable(index, changed)

    def test_changed_audio_or_dll_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            original = self.evidence(Path(root) / "run", [10] * 20)
            for key, value in (("audio_output", "default"), ("rate", 450)):
                changed = copy.deepcopy(original); changed["configuration"][key] = value
                with self.assertRaises(ValueError): benchmark.comparable(original, changed)
            changed = copy.deepcopy(original); changed["runtime_inputs"]["dll"]["sha256"] = "different"
            with self.assertRaises(ValueError): benchmark.comparable(original, changed)

    def test_failed_and_missing_jobs_are_not_successful_evidence(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "run"; index = self.evidence(path, [10])
            index["status"] = "failed"; benchmark.write_json(path / "index.json", index)
            with self.assertRaises(ValueError): benchmark.load_report(path)

    def test_schedule_balances_repeated_targets_and_is_reproducible(self):
        plan = {"seed": 123, "targets": [{"id": "old", "native": False, "ui": False}, {"id": "new", "native": True, "ui": True}],
                "routes": [{"id": "eloquence", "parameter": "breathiness"}]}
        a = benchmark.schedule(plan, benchmark.PRESETS["full"], True)
        self.assertEqual(a, benchmark.schedule(plan, benchmark.PRESETS["full"], True))
        for repeat in range(3):
            for target in ("old", "new"):
                for mode in ("warm", "cold"):
                    self.assertEqual(sum(j["repeat"] == repeat and j["target"] == target and j["mode"] == mode and j["flavour"] == "legacy" for j in a), 1)
        self.assertTrue(all(j["mode"] == "resources" for j in a[-2:]))

    def test_child_failure_is_reported_and_log_retained(self):
        with tempfile.TemporaryDirectory() as root:
            log = Path(root) / "log"
            with self.assertRaisesRegex(RuntimeError, "exited 7"):
                benchmark.run_child([sys.executable, "-c", "print('failure detail'); raise SystemExit(7)"], {}, log, 5)
            self.assertIn("failure detail", log.read_text())

    def test_native_timeline_preserves_workload_and_anchor_identity(self):
        backend = server.load_backend(ROOT.parent / "omnivox")
        old = backend.timeline_for_case("dense", 12, 34, logical_voice_id=backend.BENCHMARK_LOGICAL_VOICE_ID)
        before = copy.deepcopy(old)
        new = server.layered_timeline(old)
        self.assertEqual(old, before)
        self.assertEqual(new["actions"], old["actions"])
        self.assertEqual(new["spans"][0]["span"]["text"], old["spans"][0]["text"])
        self.assertEqual(new["spans"][0]["span"]["context"], {})
        self.assertEqual(new["protocol_version"], 5)
        self.assertEqual(new["dispatch_id"], 34)

    def test_native_and_common_registrations_differ_only_in_sparse_override(self):
        route = {"engine": "eloquence", "voice": "v1", "parameter": "breathiness", "value": 0}
        identity = {"schema_id": "qualified"}
        common = server.native_definition("test", route, identity, "layered")
        native = server.native_definition("test", route, identity, "native")
        row = native["definition"]["choices"][0]
        self.assertEqual(row["native"]["parameters"]["breathiness"]["value"], 0)
        row["native"] = None
        self.assertEqual(common, native)


if __name__ == "__main__": unittest.main()
