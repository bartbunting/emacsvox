#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare a native Piper fixture and run isolated compiled Emacs Apply tests.

Requires complete staged Omnivox/Piper payloads and current Emacsvox byte-code.
Supports POSIX or a Windows server launched through WSL. Retains the private
test root (including startup environment records) for diagnosis.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--omnivox-source", type=Path, required=True)
    parser.add_argument("--emacs", type=Path, required=True)
    args = parser.parse_args()
    server = args.server.resolve()
    windows = server.suffix == ".exe"
    helper = server.parent / "piper" / ("omnivox-piper-helper.exe" if windows else "omnivox-piper-helper")
    if not helper.is_file():
        raise RuntimeError("A complete staged Piper companion is required")

    def native(path):
        return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip() if windows else str(path)

    temporary_parent = None
    if windows:
        temporary = subprocess.check_output(["cmd.exe", "/c", "echo", "%TEMP%"], text=True).strip()
        temporary_parent = subprocess.check_output(["wslpath", "-u", temporary], text=True).strip()
    root = Path(tempfile.mkdtemp(prefix="omnivox-emacs-apply-", dir=temporary_parent))
    print(f"Private native test root retained: {native(root)}", flush=True)
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("OMNIVOX_") and key != "ESPEAK_NG_DATA"}
    environment["OMNIVOX_VOICE_ROOT"] = native(root)
    environment["WSLENV"] = ":".join(
        [entry for entry in environment.get("WSLENV", "").split(":")
         if entry and entry.split("/", 1)[0] != "OMNIVOX_VOICE_ROOT"] + ["OMNIVOX_VOICE_ROOT"])
    response = subprocess.run([str(server), "--voice-library-service"],
                              input='{"request_id":1,"command":"host"}\n', env=environment,
                              capture_output=True, text=True, timeout=30, check=True)
    host = json.loads(response.stdout.removeprefix("OMNIVOX-LOCAL "))
    assert host["type"] == "host", host
    source = args.omnivox_source.resolve() / "test-fixtures" / "piper-speakers"
    model, config = root / "alpha.onnx", root / "alpha.onnx.json"
    shutil.copyfile(source / "alpha.onnx", model)
    shutil.copyfile(source / "config.json", config)

    def asset(path):
        data = path.read_bytes()
        return {"path": native(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    import_id, operation = str(uuid.uuid4()), str(uuid.uuid4())
    generation = {"schema_version": 1, "target_id": host["target_id"], "profile_id": host["profile_id"],
                  "generation_id": str(uuid.uuid4()), "disabled_physical_ids": [], "flite": None,
                  "piper": {"models": [{"identity": {"import_id": import_id}, "model": asset(model),
                      "config": asset(config), "voices": [
                          {"physical_id": f"piper:v1/i/{import_id}/{speaker}", "speaker_index": speaker,
                           "display_name": f"Fixture {speaker}", "language": None} for speaker in [0, 1]]}]}}
    plan = {"schema_version": 1, "operation_kind": "native_validation", "operation_id": operation,
            "platform": "windows" if windows else "macos" if sys.platform == "darwin" else "linux",
            "generation_json": json.dumps(generation), "validator_path": native(server),
            "helpers": {"piper": native(helper)}, "timeout_seconds": 60,
            "memory_bytes": 4096 * 1024 * 1024, "runtime_policy": "bundled-companions-v1"}
    request = root / "validation-request.json"
    request.write_text(json.dumps(plan))
    subprocess.run([str(server), "--prepare-voice-validation", native(request), native(root / "operations")],
                   env=environment, check=True, timeout=30)
    # The validation parent must retain stdin until the supervisor completes.
    with subprocess.Popen([str(server), "--run-voice-validation-operation", native(root),
                           host["profile_id"], operation], env=environment, stdin=subprocess.PIPE) as process:
        try:
            if process.wait(timeout=120):
                raise RuntimeError("Native fixture validation failed")
        finally:
            if process.poll() is None:
                process.stdin.close()
                process.wait(timeout=15)
    environment.update(EMACSVOX_LIBRARY_TEST_ROOT=native(root),
                       EMACSVOX_LIBRARY_TEST_SERVER=str(server), EMACSVOX_LIBRARY_TEST_IMPORT=operation)
    runner = Path(__file__).resolve().with_suffix(".el")
    subprocess.run([str(args.emacs), "-Q", "--batch", "-l", str(runner)], env=environment,
                   check=True, timeout=600)


if __name__ == "__main__":
    main()
