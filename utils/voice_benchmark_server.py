#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Private worker for voice_benchmark.py; reuse Omnivox's lifecycle harness."""
from __future__ import annotations

import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import sys
import threading
import time


def load_backend(directory):
    path = Path(directory) / "tools" / "benchmark_server.py"
    spec = importlib.util.spec_from_file_location("omnivox_benchmark", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def layered_timeline(timeline):
    """Keep the existing workload and anchors, changing only its wire layer."""
    return {**timeline, "protocol_version": 5, "registry_generation": 1,
            "spans": [{"mode": "engine_layered", "span": {
                **span, "context": {}, "placement": {"pan": None}}}
                      for span in timeline["spans"]]}


def native_definition(logical_id, route, identity, flavour):
    native = None
    if flavour == "native":
        native = {"engine_id": route["engine"], "schema_id": identity["schema_id"],
                  "parameters": {route["parameter"]: {"op": "set", "value": route["value"]}}}
    return {"mode": "engine_layered", "definition": {
        "id": logical_id, "language": None,
        "shared": {"acss": dict.fromkeys(("rate", "average_pitch", "pitch_range", "stress", "richness", "volume")),
                   "rate_offset": None,
                   "effects": dict.fromkeys(("gain", "low_pass", "high_pass", "pan", "reverb", "echo", "chorus"))},
        "choices": [{"id": "benchmark-choice", "selector": {"kind": "exact",
                      "engine_id": route["engine"], "voice_id": route["voice"]},
                     "adjustments": {}, "native": native}]}}


def run(job):
    b = load_backend(job["omnivox_root"])
    route, flavour = job["route"], job["flavour"]
    identities = b.IdentitySequence()
    control_id = 100_000_000

    class Session(b.ServerSession):
        def __init__(self):
            self.receipts = {}
            command = [job["server"], *job.get("server_args", []), "--audio-output", job["audio_output"]]
            super().__init__(command, route["engine"], job["timeout"])

        def control(self, request):
            nonlocal control_id
            control_id += 1
            return self.request_control({"protocol_version": 1, "request_id": control_id, **request})[0]

        def receive_line(self, deadline):
            observed, line = super().receive_line(deadline)
            if line.startswith(b.MARKER_PREFIX):
                event = b.decode_record(line[len(b.MARKER_PREFIX):])
                if event.get("type") == "voice_choice_applied":
                    self.receipts[event["dispatch_id"]] = event
            return observed, line

        def send_timeline(self, timeline, multipart_parts=0):
            if flavour == "legacy":
                return super().send_timeline(timeline, multipart_parts)
            timeline = layered_timeline(timeline)
            if multipart_parts:
                for line in b.multipart_timeline_lines(timeline, multipart_parts):
                    sent = self.send_line(line.replace("emacsvox_timeline_part 3 ", "emacsvox_timeline_part 5 ", 1))
                return sent
            return self.send_line(f"emacsvox_timeline {b.encode_record(timeline)}")

        def catalogue(self):
            deadline, pages, cursor, identity = time.monotonic() + job["timeout"], [], None, None
            while time.monotonic() < deadline:
                response = self.control({"type": "get_engine_parameters_v1", "engine_id": route["engine"],
                                         "voice_id": route["voice"], "cursor": cursor,
                                         "expected_catalogue_revision": identity["catalogue_revision"] if identity else None})
                result = response.get("result", {})
                if result.get("status") == "busy":
                    time.sleep(max(.05, result.get("retry_after_ms", 50) / 1000))
                    continue
                if response.get("type") != "engine_parameters_v1" or result.get("status") != "ready":
                    raise RuntimeError(f"Catalogue unavailable: {response}")
                if identity and identity != result["identity"]:
                    raise RuntimeError("Catalogue changed while paging")
                identity = result["identity"]
                pages.extend(result["parameters"])
                cursor = result["next_cursor"]
                if cursor is None:
                    return identity, pages
            raise TimeoutError("Catalogue remained busy")

        def prepare(self):
            capabilities, ready_at = self.negotiate(90_000_000)
            self.send_line(f"tts_set_speech_rate {job['rate']}")
            catalogue = None
            if flavour == "legacy":
                b.configure_exact_voice(self, capabilities, route["engine"], route["voice"], 90_000_001)
            else:
                required = {"engine_voice_parameters_v1", "presentation_timeline_v5"}
                if not required.issubset(capabilities.get("features", [])):
                    raise RuntimeError(f"Worker lacks native features: {required - set(capabilities.get('features', []))}")
                catalogue, parameters = self.catalogue()
                if flavour == "native" and not any(p["id"] == route["parameter"] for p in parameters):
                    raise RuntimeError("Requested native parameter is not described")
                response = self.control({"type": "register_logical_voices_v3", "registry_generation": 1,
                    "definitions": [native_definition(b.BENCHMARK_LOGICAL_VOICE_ID, route, catalogue, flavour)],
                    "fallback_policy": {"preferred_engines": [], "allow_same_language_on_requested_engine": False,
                                        "global_default": None, "fallback_engines": []}})
                if response.get("type") != "logical_voices_registered_v3" or response.get("unresolved_logical_voice_ids"):
                    raise RuntimeError(f"Native registration failed: {response}")
                if flavour == "native" and not any(s.get("status") == "supported" and s.get("choice_id") == "benchmark-choice"
                                                   for s in response.get("native_status", [])):
                    raise RuntimeError(f"Native settings not supported: {response}")
            return {"server_version": capabilities.get("server_version"), "catalogue": catalogue,
                    "process_start_to_ready_ms": b.milliseconds(ready_at, self.started_at_ns)}

        def verify(self, sample):
            if flavour != "native":
                return
            receipt = self.receipts.get(sample["dispatch_id"], {})
            application = receipt.get("native_application", {})
            if application.get("status") != "applied" or application.get("masked_parameters"):
                raise RuntimeError(f"Native settings not applied intact: {receipt}")
            response = self.control({"type": "explain_voice_parameters_v1",
                                     "source": {"mode": "applied", "plan_id": application["plan_id"]}})
            result = response.get("result", {})
            if result.get("status") != "ready" or not any(
                p.get("id") == route["parameter"] and p.get("value") == route["value"] and p.get("read_back") is True
                for p in result.get("parameters", [])):
                raise RuntimeError(f"Native readback mismatch: {response}")
            sample["native_verified"] = True
            sample["native_identity"] = application["identity"]

    def execute(session, case, sequence=identities):
        sample = b.execute_case(session, case, sequence, route["engine"], job["replacement_burst"], route["voice"])
        session.verify(sample)  # Outside the measured dispatch interval.
        session.receipts.clear()
        return sample

    samples, sessions = [], []
    try:
        if job["mode"] == "resources":
            sys.path.insert(0, str(Path(job["omnivox_root"]) / "tools"))
            import process_metrics
            observer = process_metrics.ProcessTreeObserver(job["server"], job.get("resource_process_name"))
            session = Session(); sessions.append(session)
            observer.bind(session.process.pid)
            session.prepare()
            observations = [{"iteration": 0, "tree": observer.sample()}]
            for i in range(job["iterations"]):
                execute(session, "line")
                if (i + 1) % max(1, job["iterations"] // 4) == 0:
                    observations.append({"iteration": i + 1, "tree": observer.sample()})
            return {"provider": observer.description(), "observations": observations,
                    "timing_samples": [], "sampling_outside_latency_runs": True}
        for case in job["cases"]:
            session = None
            prepared = None
            if job["mode"] == "warm":
                session = Session(); sessions.append(session)
                prepared = session.prepare()
                samples.append({"case": "server_ready", "iteration": 0,
                                "process_start_to_ready_ms": prepared["process_start_to_ready_ms"]})
                for _ in range(job["warmups"]): execute(session, case)
            for iteration in range(job["iterations"]):
                if session is None:
                    session = Session(); sessions.append(session)
                    prepared = session.prepare()
                sample = execute(session, case)
                sample.update(case=case, iteration=iteration, server_version=prepared["server_version"], catalogue=prepared["catalogue"])
                if job["mode"] == "cold":
                    sample["process_start_to_ready_ms"] = prepared["process_start_to_ready_ms"]
                    sample["process_start_to_source_ms"] = b.milliseconds(sample["source_observed_at_monotonic_ns"], session.started_at_ns)
                    session.close(); sessions.remove(session); session = None
                samples.append(sample)
            if session:
                session.close(); sessions.remove(session)
        if job["mode"] == "warm" and job.get("concurrent", True):
            main, notify = Session(), Session(); sessions.extend((main, notify))
            main.prepare(); notify.prepare()
            seq1, seq2 = b.IdentitySequence(), b.IdentitySequence()
            barrier = threading.Barrier(2, timeout=job["timeout"])
            def lane(session, sequence):
                barrier.wait()
                return execute(session, "line", sequence)
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                for i in range(job["warmups"] + job["iterations"]):
                    futures = [pool.submit(lane, main, seq1), pool.submit(lane, notify, seq2)]
                    for label, future in zip(("main", "notification"), futures):
                        sample = future.result(timeout=job["timeout"] + 5)
                        if i >= job["warmups"]:
                            samples.append({**sample, "case": f"concurrent_{label}", "iteration": i - job["warmups"]})
        return {"measurement": "client source and terminal observations; no acoustic onset",
                "clock": "time.perf_counter_ns", "timing_samples": samples}
    finally:
        for session in sessions: session.close()


if __name__ == "__main__":
    job = json.loads(Path(sys.argv[1]).read_text())
    result = run(job)
    Path(sys.argv[2]).write_text(json.dumps(result, indent=2) + "\n")
