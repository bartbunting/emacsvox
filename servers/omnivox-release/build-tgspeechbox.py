#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

"""Compile TGSpeechBox in the pinned container, then stage it on the WSL host."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

TARGET = "x86_64-pc-windows-gnu"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def data_digest(directory):
    records = [f"{digest(p)}  {p.relative_to(directory).as_posix()}\n"
               for p in sorted(directory.rglob("*")) if p.is_file()]
    return hashlib.sha256("".join(records).encode()).hexdigest()


def inside(repository, relative):
    path = (repository / relative).resolve()
    if not path.is_relative_to(repository):
        raise RuntimeError(f"build output is outside the repository: {relative}")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "stage"))
    parser.add_argument("--repository", type=Path, required=True)
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    sys.path.insert(0, str(repository / "tools"))
    import build_tgspeechbox as tg

    manifest = repository / "target/emacsvox-release/tgspeechbox-build.json"
    lock = repository / "omnivox-tgspeechbox-sys/source-inputs.json"
    source, marker = tg.prepare_source(repository)
    if arguments.mode == "build":
        executable, espeak = tg.build(["--release", "--target", TARGET], source)
        subprocess.run(["x86_64-w64-mingw32-strip", "--strip-all", str(executable)],
                       check=True, env={**os.environ, "SOURCE_DATE_EPOCH": "0"})
        compiler_name = os.environ.get("CXX_x86_64_pc_windows_gnu", "x86_64-w64-mingw32-g++-posix")
        compiler = Path(shutil.which(compiler_name)).resolve()
        record = {
            "schema_version": 1,
            "target": TARGET,
            "commit": tg.git_output(repository, "rev-parse", "HEAD"),
            "source_lock_sha256": digest(lock),
            "executable": executable.relative_to(repository).as_posix(),
            "espeak_output": espeak.relative_to(repository).as_posix(),
            "executable_sha256": digest(executable),
            "espeak_data_sha256": data_digest(espeak / "share/espeak-ng-data"),
            "compiler": subprocess.check_output([str(compiler), "--version"],
                                                 text=True).splitlines()[0],
            "compiler_sha256": digest(compiler),
        }
        manifest.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    else:
        record = json.loads(manifest.read_text())
        if (record["schema_version"] != 1 or record["target"] != TARGET
                or record["commit"] != tg.git_output(repository, "rev-parse", "HEAD")
                or record["source_lock_sha256"] != digest(lock)):
            raise RuntimeError("TGSpeechBox container inputs do not match this checkout")
        executable = inside(repository, record["executable"])
        espeak = inside(repository, record["espeak_output"])
        if (digest(executable) != record["executable_sha256"]
                or data_digest(espeak / "share/espeak-ng-data") != record["espeak_data_sha256"]):
            raise RuntimeError("TGSpeechBox container outputs changed before staging")
        # Inventory generation executes this exact Windows helper through WSL.
        # Compilation remains wholly inside the pinned container.
        tg.stage(repository, executable, espeak, TARGET, source, marker)


if __name__ == "__main__":
    main()
