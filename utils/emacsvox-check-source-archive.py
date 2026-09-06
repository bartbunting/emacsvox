#!/usr/bin/env python3
"""Install an extracted source archive in a private home before release."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile


REQUIRED = (
    "VERSION", "COPYING", "AUTHORS", "THIRD_PARTY_NOTICES", "Makefile",
    "bin/emacsvox", "bin/emacsvox-install", "bin/emacsvox-wsl-install",
    "bin/emacsvox-install.ps1", "bin/emacsvox.ps1",
    "utils/emacsvox-install-common.sh", "utils/emacsvox-windows-common.ps1",
    "utils/emacsvox-windows-build.sh", "utils/emacsvox-windows-startup.el",
    "utils/emacsvox-native-bytecode.el", "utils/emacsvox-remote-startup.el",
    "utils/emacsvox-remote-check.el", "utils/emacsvox-version-check",
    "utils/emacsvox-header-check", "etc/wsl-install.conf", "etc/windows-install.conf",
    "lisp/emacsvox-setup.el", "info/emacsvox.info",
)


def extract(archive, destination):
    """Check the distribution boundary and extract without trusting tar paths."""
    with tarfile.open(archive) as source:
        members = source.getmembers()
        roots = {PurePosixPath(m.name).parts[0] for m in members if m.name}
        if len(roots) != 1:
            raise RuntimeError("source archive must contain one versioned root")
        prefix = roots.pop()
        if not re.fullmatch(r"emacsvox-[0-9]{4}\.(?:[1-9]|1[0-2])\.(?:0|[1-9][0-9]*)", prefix):
            raise RuntimeError("invalid source archive root")
        names = {m.name.rstrip("/") for m in members}
        missing = [name for name in REQUIRED if f"{prefix}/{name}" not in names]
        if missing:
            raise RuntimeError("source archive is missing required files: " + ", ".join(missing))
        for member in members:
            parts = PurePosixPath(member.name).parts
            if (member.name.startswith("/") or ".." in parts
                    or member.name.endswith(".elc")
                    or any(part in {".git", "local.mk", "native-install.json"} for part in parts)):
                raise RuntimeError(f"unexpected source archive payload: {member.name}")
        source.extractall(destination, filter="data")
    root = destination / prefix
    if (root / "VERSION").read_text().strip() != prefix.removeprefix("emacsvox-"):
        raise RuntimeError("source archive VERSION does not match its root")
    return root


def run(command, root, environment, expected=0, timeout=90):
    result = subprocess.run(command, cwd=root, env=environment,
                            capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    if result.returncode != expected:
        raise RuntimeError(f"{command[0]} exited {result.returncode}:\n{output}")
    return output


def check(archive, emacs):
    emacs = shutil.which(emacs)
    if not emacs:
        raise RuntimeError("selected Emacs executable not found")
    with tempfile.TemporaryDirectory(prefix="emacsvox source archive ") as temporary:
        work = Path(temporary)
        root = extract(archive, work)
        home = work / "home"
        home.mkdir()
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("EMACSVOX_", "OMNIVOX_", "TTS_", "XDG_"))
                       and key not in {"HOME", "EMACS", "MAKEFLAGS", "MFLAGS"}}
        environment.update(HOME=str(home), EMACS=emacs, MAKEFLAGS="-j2",
                           EMACSVOX_DIR=str(root),
                           XDG_CONFIG_HOME=str(home / ".config"),
                           XDG_CACHE_HOME=str(home / ".cache"),
                           XDG_STATE_HOME=str(home / ".local/state"),
                           EMACSVOX_REMOTE_TOKEN_FILE=str(home / "missing-token"))
        installer = str(root / "bin/emacsvox-install")
        doctor = run([installer, "--role", "remote-emacs", "--check"], root, environment)
        if "Local speech components: none" not in doctor or list(home.iterdir()):
            raise RuntimeError("archive installer doctor did not preserve a private home")
        print("Source archive installer doctor passed", flush=True)
        installed = run([installer, "--role", "remote-emacs"], root, environment, timeout=900)
        if "Remote Emacs installation complete" not in installed:
            raise RuntimeError("archive installation did not complete")
        run(["make", "bytecode-check", f"EMACS={emacs}"], root, environment)
        launcher = str(root / "bin/emacsvox")
        expression = '''(progn
          (unless (and (featurep 'emacsvox)
                       (file-readable-p (expand-file-name "emacsvox.info" emacsvox-info-directory)))
            (error "Archive startup or offline manual missing"))
          (princ "Archive startup passed"))'''
        started = run([launcher, "--", "--batch", "--eval", expression], root,
                      {**environment, "TTS_PROGRAM": "/bin/cat"})
        if "Archive startup passed" not in started:
            raise RuntimeError("fresh archive startup did not complete")
        remote = run([launcher, "--remote", "--check"], root, environment, expected=1)
        if "Set omnivox-remote-token-file to a private local file" not in remote:
            raise RuntimeError("remote check did not reach credential validation:\n" + remote)
        print("Source archive installation, byte-code, fresh startup, offline manual "
              "and remote helper checks passed", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--emacs", default=os.environ.get("EMACS", "emacs"))
    args = parser.parse_args()
    try:
        check(args.archive.resolve(), args.emacs)
    except (OSError, RuntimeError, tarfile.TarError, subprocess.SubprocessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
