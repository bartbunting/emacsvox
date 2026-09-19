#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Repeatable isolated speech/workbench benchmarks and conservative comparisons."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 1
WORKLOAD = "voice-benchmark-1"
ENVIRONMENT = (
    "OMNIVOX_PROGRAM", "OMNIVOX_DECTALK_DLL", "OMNIVOX_DECTALK_DICTIONARY",
    "OMNIVOX_ECI_DLL", "ESPEAK_NG_DATA", "OMNIVOX_AUDIO_BACKEND",
    "OMNIVOX_AUDIO_BUFFER_FRAMES", "OMNIVOX_AUDIO_SAMPLE_RATE", "RUST_LOG",
)
DEFAULT_ROUTES = [
    {"id": "eloquence", "engine": "eloquence", "voice": "v1", "parameter": "breathiness", "value": 35},
    {"id": "dectalk", "engine": "dectalk", "voice": "paul", "parameter": "sm", "value": 61},
    {"id": "espeak", "engine": "espeak", "voice": "espeak:gmw/en"},
]
PRESETS = {"quick": {"repeats": 1, "warm": 3, "cold": 1, "ui": 3, "warmups": 1},
           "full": {"repeats": 3, "warm": 30, "cold": 3, "ui": 20, "warmups": 3}}
CASES = ["character", "word", "line", "dense", "multipart", "replacement"]


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): h.update(block)
    return h.hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def local_path(value, base=ROOT):
    if re.match(r"^[A-Za-z]:[/\\]", value) and platform.system() != "Windows":
        value = "/mnt/" + value[0].lower() + "/" + value[3:].replace("\\", "/")
    path = Path(value).expanduser()
    return (base / path).resolve() if not path.is_absolute() else path.resolve()


def tree_identity(path):
    path = Path(path)
    if path.is_file(): return {"path": str(path), "sha256": digest(path)}
    if not path.is_dir(): raise ValueError(f"Missing benchmark input: {path}")
    files = {str(p.relative_to(path)): digest(p) for p in sorted(path.rglob("*")) if p.is_file()}
    if not files: raise ValueError(f"Empty benchmark input: {path}")
    return {"path": str(path), "sha256": canonical(files), "files": files}


def git_identity(root):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)
    return {"commit": git("rev-parse", "HEAD").decode().strip(),
            "tracked_diff_sha256": hashlib.sha256(git("diff", "HEAD", "--binary")).hexdigest(),
            "status": git("status", "--porcelain").decode()}


def validate_plan(plan, base):
    if plan.get("schema") != SCHEMA: raise ValueError("Unsupported plan schema")
    for key in ("omnivox_root", "emacs"):
        plan[key] = str(local_path(plan[key], base))
        if not Path(plan[key]).exists(): raise ValueError(f"Missing {key}: {plan[key]}")
    if not (Path(plan["omnivox_root"]) / "tools/benchmark_server.py").is_file():
        raise ValueError("Omnivox checkout must include tools/benchmark_server.py")
    if plan.get("audio_output", "null") not in ("null", "default"): raise ValueError("audio_output must be null or default")
    for key in ("rate", "timeout", "seed"):
        if type(plan.get(key)) is not int or plan[key] < 1: raise ValueError(f"Invalid {key}")
    if not 1 <= plan["rate"] <= 1000 or plan["timeout"] > 120: raise ValueError("Rate/timeout outside benchmark bounds")
    if plan.get("display") not in ("batch", "xvfb", "native"): raise ValueError("display must be batch, xvfb or native")
    if plan["display"] == "xvfb" and not shutil.which("xvfb-run"): raise ValueError("xvfb-run is unavailable; select batch or native explicitly")
    for collection in ("targets", "routes"):
        rows = plan.get(collection)
        if not isinstance(rows, list) or not 1 <= len(rows) <= 8: raise ValueError(f"Expected 1 to 8 {collection}")
        ids = [r.get("id", "") for r in rows]
        if len(set(ids)) != len(ids) or any(not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,39}", s) for s in ids):
            raise ValueError(f"Invalid or duplicate {collection} IDs")
    for target in plan["targets"]:
        for key in ("server", "program", "emacsvox_root"):
            target[key] = str(local_path(target[key], base))
            if not Path(target[key]).exists(): raise ValueError(f"Missing target {key}: {target[key]}")
        env = target.setdefault("environment", {})
        if any(key not in ENVIRONMENT or not isinstance(value, str) for key, value in env.items()):
            raise ValueError("Target environment contains an unsupported variable or non-string value")
        env["OMNIVOX_PROGRAM"] = target["program"]
        if type(target.get("native")) is not bool or type(target.get("ui")) is not bool:
            raise ValueError("Targets need explicit native and ui booleans")
        for arg in target.get("server_args", []):
            if not isinstance(arg, str): raise ValueError("server_args must be strings")
    for route in plan["routes"]:
        if any(not isinstance(route.get(k), str) or not route[k] for k in ("engine", "voice")):
            raise ValueError("Routes need exact engine and voice IDs")
        if "parameter" in route and (not isinstance(route["parameter"], str) or not route["parameter"]
                                     or type(route.get("value")) not in (int, float) or not math.isfinite(route["value"])):
            raise ValueError("Native routes need a parameter and numeric value")
        exclusions = route.get("exclude_cases", {})
        if not isinstance(exclusions, dict) or any(k not in CASES or not isinstance(v, str) or not v.strip()
                                                   for k, v in exclusions.items()) or len(exclusions) == len(CASES):
            raise ValueError("Case exclusions need known case names and explicit reasons; keep at least one case")
    plan["runtime_inputs"] = {key: str(local_path(value, base)) for key, value in plan.get("runtime_inputs", {}).items()}
    if not plan["runtime_inputs"]: raise ValueError("Declare runtime_inputs (DLLs, dictionaries, voice data) for reproducible comparisons")
    return plan


def init_plan(args):
    program = args.program or os.environ.get("OMNIVOX_PROGRAM")
    if not program: raise ValueError("Use --program or launch init from the development launcher")
    environment = {key: os.environ[key] for key in ENVIRONMENT if key in os.environ}
    environment.setdefault("RUST_LOG", "warn")
    runtime_inputs = {}
    for key in ("OMNIVOX_DECTALK_DLL", "OMNIVOX_DECTALK_DICTIONARY", "OMNIVOX_ECI_DLL", "ESPEAK_NG_DATA"):
        if environment.get(key): runtime_inputs[key] = str(local_path(environment[key]))
    for value in args.runtime_input:
        key, separator, path = value.partition("=")
        if not separator or not key: raise ValueError("--runtime-input requires NAME=PATH")
        runtime_inputs[key] = str(local_path(path))
    target = {"id": "current", "server": str(ROOT / "servers/omnivox"), "program": str(local_path(program)),
              "emacsvox_root": str(ROOT), "environment": environment, "native": True, "ui": True}
    targets = [target]
    if args.baseline_program:
        targets.insert(0, {**target, "id": "baseline", "program": str(local_path(args.baseline_program)),
                           "environment": dict(environment), "native": False, "ui": False})
    routes = [dict(route) for route in DEFAULT_ROUTES]
    if program.lower().endswith(".exe"):
        routes[-1]["voice"] = "espeak:gmw\\en"
    plan = {"schema": SCHEMA, "omnivox_root": str(local_path(args.omnivox_root)),
            "emacs": str(local_path(args.emacs)), "rate": 225, "timeout": 30, "seed": 71423,
            "audio_output": "null", "display": "xvfb" if shutil.which("xvfb-run") else "batch",
            "runtime_inputs": runtime_inputs, "targets": targets, "routes": routes}
    plan = validate_plan(plan, Path.cwd())
    path = Path(args.plan)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as stream: json.dump(plan, stream, indent=2); stream.write("\n")
    print(path.resolve())


def schedule(plan, preset, resources):
    rng = random.Random(plan["seed"])
    jobs = []
    for repeat in range(preset["repeats"]):
        block = []
        for route in plan["routes"]:
            for target in plan["targets"]:
                flavours = ["legacy"] + (["layered", "native"] if target["native"] and route.get("parameter") else [])
                for flavour in flavours:
                    for mode in ("cold", "warm"):
                        block.append({"target": target["id"], "route": route, "flavour": flavour,
                                      "mode": mode, "iterations": preset[mode], "repeat": repeat})
                if target["ui"]:
                    block.append({"target": target["id"], "route": route, "flavour": "editor", "mode": "ui",
                                  "iterations": preset["ui"], "repeat": repeat})
        rng.shuffle(block)
        jobs.extend(block)
    if resources:
        for target in plan["targets"]:
            for route in plan["routes"]:
                jobs.append({"target": target["id"], "route": route, "flavour": "native" if target["native"] and route.get("parameter") else "legacy",
                             "mode": "resources", "iterations": preset["warm"], "repeat": 0})
    return jobs


def child_environment(target, directory):
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("OMNIVOX_", "EMACSVOX_", "ESPEAK_", "TTS_")) and key != "RUST_LOG"}
    environment.update(target["environment"])
    environment["OMNIVOX_LOG_DIRECTORY"] = str(directory / "server-logs")
    return environment


def run_child(command, env, log, timeout):
    with Path(log).open("w") as output:
        process = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=(os.name != "nt"))
        try:
            status = process.wait(timeout=timeout)
            if status: raise RuntimeError(f"Benchmark worker exited {status}; see {log}")
        finally:
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=subprocess.DEVNULL, check=False)
                else: os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    if os.name != "nt": os.killpg(process.pid, signal.SIGKILL)
                    else: process.kill()
                    process.wait(timeout=5)


def percentile(values, percent):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * percent) - 1)]


def summarize(index, directory):
    series = {}
    for entry in index["jobs"]:
        if entry.get("status") != "complete" or entry["mode"] == "resources": continue
        raw = json.loads((directory / entry["report"]).read_text())
        for sample in raw["timing_samples"]:
            for metric, value in sample.items():
                if not metric.endswith("_ms") or type(value) not in (int, float): continue
                if not math.isfinite(value) or value < 0: raise ValueError("Invalid timing sample")
                key = "/".join((entry["target"], entry["route"]["id"], entry["flavour"], entry["mode"], sample["case"], metric))
                series.setdefault(key, []).append(value)
    return {key: {"n": len(values), "median_ms": percentile(values, .5), "p95_ms": percentile(values, .95),
                  "max_ms": max(values), "over_100ms": sum(v > 100 for v in values)}
            for key, values in sorted(series.items())}


def markdown_summary(index):
    lines = ["# Voice benchmark", "", f"Status: {index['status']}. Preset: {index['preset']}.",
             "", "Software source observations and preview completion; physical audible onset is not measured.",
             "Quick runs check the harness. Tail-latency conclusions need repeated full runs."]
    for route in index["configuration"]["routes"]:
        for case, reason in route.get("exclude_cases", {}).items():
            lines.extend(["", f"Excluded {route['id']}/{case}: {reason}"])
    lines.extend(["", "| Target / route / path / mode / case / metric | Samples | Median ms | p95 ms | Max ms |",
                  "|---|---:|---:|---:|---:|"])
    for key, stats in index["summary"].items():
        lines.append(f"| {key} | {stats['n']} | {stats['median_ms']:.2f} | {stats['p95_ms']:.2f} | {stats['max_ms']:.2f} |")
    lines.extend(["", "Resource samples are separate raw reports; unavailable providers do not mean zero memory use.",
                  "Cold UI first-open, asynchronous ready time, synchronous command time and preview completion are different measurements.", ""])
    return "\n".join(lines)


def run_plan(args):
    path = Path(args.plan).resolve()
    plan = validate_plan(json.loads(path.read_text()), path.parent)
    preset = PRESETS[args.preset]
    output = Path(args.output or ROOT / ".benchmarks" / f"run-{time.time_ns()}").resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    runtime_inputs = {key: tree_identity(value) for key, value in plan["runtime_inputs"].items()}
    tools = Path(plan["omnivox_root"]) / "tools"
    harness = {p.name: digest(p) for p in [Path(__file__), ROOT / "utils/voice_benchmark_server.py", ROOT / "utils/voice-benchmark.el", tools / "benchmark_server.py", tools / "process_metrics.py"]}
    index = {"schema": SCHEMA, "workload": WORKLOAD, "status": "running", "created_at": datetime.now(timezone.utc).isoformat(),
             "preset": args.preset, "configuration": plan, "harness": harness, "runtime_inputs": runtime_inputs,
             "host": {"platform": platform.platform(), "machine": platform.machine(), "hostname": platform.node(), "python": platform.python_version()},
             "emacs_version": subprocess.check_output([plan["emacs"], "--version"], text=True).splitlines()[0],
             "targets": {}, "jobs": [], "summary": {}}
    for target in plan["targets"]:
        if target["ui"]:
            subprocess.run(["make", "--no-print-directory", "bytecode-check", "EMACS=" + plan["emacs"]], cwd=target["emacsvox_root"], check=True)
        program = Path(target["program"])
        payload = {str(p.relative_to(program.parent)): digest(p) for p in sorted(program.parent.rglob("*"))
                   if p.is_file() and p.suffix.lower() in (".exe", ".dll", ".dic", ".so", ".dylib")}
        index["targets"][target["id"]] = {"source": git_identity(target["emacsvox_root"]), "program_sha256": digest(program),
                                         "payload": payload, "launcher_sha256": digest(target["server"])}
    write_json(output / "index.json", index)
    write_json(output / "plan.json", plan)
    try:
        for ordinal, item in enumerate(schedule(plan, preset, args.resources), 1):
            target = next(t for t in plan["targets"] if t["id"] == item["target"])
            name = f"{ordinal:04d}-{item['target']}-{item['route']['id']}-{item['flavour']}-{item['mode']}"
            directory = output / name
            directory.mkdir(mode=0o700)
            (directory / "state").mkdir()
            job = {**item, "omnivox_root": plan["omnivox_root"], "emacsvox_root": target["emacsvox_root"],
                   "server": target["server"], "server_args": target.get("server_args", []), "timeout": plan["timeout"],
                   "rate": plan["rate"], "audio_output": plan["audio_output"],
                   "cases": [case for case in CASES if case not in item["route"].get("exclude_cases", {})],
                   "warmups": preset["warmups"], "replacement_burst": 5, "state_directory": str(directory / "state"),
                   "resource_process_name": "omnivox.exe" if target["program"].lower().endswith(".exe") else None}
            write_json(directory / "job.json", job)
            env = child_environment(target, directory)
            report = directory / "raw.json"
            entry = {**item, "report": str(report.relative_to(output)), "status": "running"}
            index["jobs"].append(entry)
            write_json(output / "index.json", index)
            print(f"{ordinal}: {name}", flush=True)
            if item["mode"] == "ui":
                env.update(EMACSVOX_BENCHMARK_JOB=str(directory / "job.json"), EMACSVOX_BENCHMARK_OUTPUT=str(report))
                command = [plan["emacs"], "-Q"]
                if plan["display"] == "batch": command.append("--batch")
                command += ["-l", str(ROOT / "utils/voice-benchmark.el")]
                if plan["display"] == "xvfb": command = ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24 -nolisten tcp", *command]
            else:
                command = [sys.executable, str(ROOT / "utils/voice_benchmark_server.py"), str(directory / "job.json"), str(report)]
            run_child(command, env, directory / "worker.log", max(90, item["iterations"] * plan["timeout"] * 8))
            entry.update(status="complete", sha256=digest(report))
            write_json(output / "index.json", index)
        index["status"] = "complete"
    except BaseException as error:
        index["status"] = "failed"
        index["error"] = str(error)
        raise
    finally:
        index["summary"] = summarize(index, output)
        write_json(output / "index.json", index)
        (output / "report.md").write_text(markdown_summary(index))
    print(output / "report.md")


def load_report(path):
    path = Path(path)
    if path.is_dir(): path /= "index.json"
    index = json.loads(path.read_text())
    if index.get("schema") != SCHEMA or index.get("status") != "complete": raise ValueError("Comparison requires complete benchmark runs")
    for entry in index["jobs"]:
        if entry.get("status") != "complete" or digest(path.parent / entry["report"]) != entry.get("sha256"):
            raise ValueError("Raw benchmark evidence is missing or changed")
    if summarize(index, path.parent) != index["summary"]: raise ValueError("Stored summary disagrees with raw samples")
    return index


def comparable(a, b):
    for key in ("schema", "workload", "host", "emacs_version", "harness"):
        if a[key] != b[key]: raise ValueError(f"Incompatible benchmark {key}")
    if {k: v["sha256"] for k, v in a["runtime_inputs"].items()} != {k: v["sha256"] for k, v in b["runtime_inputs"].items()}:
        raise ValueError("Runtime input hashes differ")
    for key in ("rate", "audio_output", "display", "routes"):
        if a["configuration"][key] != b["configuration"][key]: raise ValueError(f"Incompatible configuration: {key}")


def compare(args):
    before, after = load_report(args.before), load_report(args.after)
    comparable(before, after)
    selected = []
    for report, target_id in ((before, args.before_target), (after, args.after_target)):
        target = next((t for t in report["configuration"]["targets"] if t["id"] == target_id), None)
        if target is None: raise ValueError(f"Unknown comparison target: {target_id}")
        selected.append({"environment": {k: v for k, v in target["environment"].items() if k != "OMNIVOX_PROGRAM"},
                         "server_args": target.get("server_args", [])})
    if selected[0] != selected[1]: raise ValueError("Runtime environment or server arguments differ")
    old = {k.split("/", 1)[1]: v for k, v in before["summary"].items() if k.startswith(args.before_target + "/")}
    new = {k.split("/", 1)[1]: v for k, v in after["summary"].items() if k.startswith(args.after_target + "/")}
    def included(key):
        fields = key.split("/")
        return (args.flavour == "all" or fields[1] == args.flavour) and (args.mode == "all" or fields[2] == args.mode)
    old = {k: v for k, v in old.items() if included(k)}
    new = {k: v for k, v in new.items() if included(k)}
    if not old or not new: raise ValueError("Requested comparison target has no measurements")
    rows, flagged, insufficient = [], 0, 0
    for key in sorted(old.keys() | new.keys()):
        a, b = old.get(key), new.get(key)
        if not a or not b:
            rows.append(f"| {key} | — | — | — | missing on one side |")
            insufficient += 1
            continue
        delta = b["p95_ms"] - a["p95_ms"]
        enough = min(a["n"], b["n"]) >= args.minimum_samples
        slower = delta > max(args.absolute_ms, a["p95_ms"] * args.relative_percent / 100)
        status = "too few samples" if not enough else ("investigate slowdown" if slower else "within threshold")
        flagged += int(enough and slower)
        insufficient += int(not enough)
        rows.append(f"| {key} | {a['p95_ms']:.2f} | {b['p95_ms']:.2f} | {delta:+.2f} | {status} |")
    text = "\n".join(["# Voice benchmark comparison", "", f"Flagged series: {flagged}; incomplete/low-sample series: {insufficient}.",
        f"Flag when p95 rises by more than both {args.absolute_ms:g} ms and {args.relative_percent:g}%. Minimum {args.minimum_samples} samples.",
        "This is a regression screen, not a statistical proof of unchanged performance.", "",
        "| Route / path / mode / case / metric | Before p95 ms | After p95 ms | Change ms | Assessment |", "|---|---:|---:|---:|---|", *rows, ""])
    if args.output:
        with Path(args.output).open("x") as stream: stream.write(text)
        print(args.output)
    else: print(text)
    if args.fail_on_regression:
        if flagged: return 1
        if insufficient: return 3
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init", help="Write a local editable plan; refuses to overwrite")
    init.add_argument("plan")
    init.add_argument("--program")
    init.add_argument("--baseline-program")
    init.add_argument("--omnivox-root", default=str(ROOT.parent / "omnivox"))
    init.add_argument("--emacs", default=os.environ.get("EMACS", shutil.which("emacs") or "emacs"))
    init.add_argument("--runtime-input", action="append", default=[], metavar="NAME=PATH")
    run = sub.add_parser("run", help="Run in private workers and a new output directory")
    run.add_argument("plan"); run.add_argument("output", nargs="?", help="New directory (default: .benchmarks/run-TIMESTAMP)")
    run.add_argument("--preset", choices=PRESETS, default="full")
    run.add_argument("--resources", action="store_true", help="Add a separate process-tree resource phase")
    comparison = sub.add_parser("compare", help="Verify and compare retained reports")
    comparison.add_argument("before"); comparison.add_argument("after")
    comparison.add_argument("--before-target", default="current"); comparison.add_argument("--after-target", default="current")
    comparison.add_argument("--flavour", choices=("all", "legacy", "layered", "native", "editor"), default="all")
    comparison.add_argument("--mode", choices=("all", "cold", "warm", "ui"), default="all")
    comparison.add_argument("--output"); comparison.add_argument("--absolute-ms", type=float, default=5)
    comparison.add_argument("--relative-percent", type=float, default=15)
    comparison.add_argument("--minimum-samples", type=int, default=20)
    comparison.add_argument("--fail-on-regression", action="store_true")
    args = parser.parse_args()
    if args.command == "compare" and (args.minimum_samples < 1 or not math.isfinite(args.absolute_ms)
                                      or not math.isfinite(args.relative_percent) or min(args.absolute_ms, args.relative_percent) < 0):
        parser.error("Comparison thresholds must be finite and nonnegative; sample minimum must be positive")
    try:
        if args.command == "init": init_plan(args)
        elif args.command == "run": run_plan(args)
        else: return compare(args)
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__": raise SystemExit(main())
