#!/usr/bin/python3
"""Controlled external tools for the Windows staging fixtures; never run Docker."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]


def record(event):
    with open(os.environ["STAGING_EVENTS"], "a") as output:
        output.write(json.dumps(event) + "\n")


if name == "docker":
    if args[:2] == ["image", "inspect"]:
        print("sha256:fixture-image")
    elif args[-2:] == ["rustc", "--version"]:
        print("rustc fixture")
    elif args[-2:] == ["x86_64-w64-mingw32-gcc-win32", "--version"]:
        print("mingw fixture")
    elif args[:1] == ["run"] and "sh" in args:
        record("build")  # Prepared fixture files stand in for compiler output.
    else:
        raise SystemExit(f"Unexpected Docker invocation: {args!r}")
elif name == "powershell.exe":
    if "LocalApplicationData" in args[-1]:
        print("W:" + os.environ["STAGING_LOCAL_APP_DATA"] + "\r")
    elif "/version" in args[-1]:
        print("csc fixture\r")
    else:
        raise SystemExit(f"Unexpected PowerShell invocation: {args!r}")
elif name == "wslpath":
    if args[0] == "-u":
        if not args[1].startswith("W:"):
            raise SystemExit(f"Unexpected Windows fixture path: {args[1]!r}")
        print(args[1][2:])
    elif args[0] in ("-w", "-m"):
        print("W:" + args[1])
    else:
        raise SystemExit(f"Unexpected wslpath invocation: {args!r}")
elif name == "x86_64-w64-mingw32-objdump":
    print("DLL Name: KERNEL32.dll")
elif name == "x86_64-w64-mingw32-g++-posix":
    print("fixture POSIX C++ compiler")
elif name in ("cp", "mv"):
    destination = args[-1]
    if (os.environ.get("STAGING_FAIL_OPERATION") == name
            and destination.endswith(os.environ.get("STAGING_FAIL_SUFFIX", "!"))):
        if os.environ.get("STAGING_INTERRUPT") == "1":
            subprocess.run(["/usr/bin/" + name, *args], check=True)
            os.kill(os.getppid(), signal.SIGTERM)
        raise SystemExit("Injected staging failure: " + destination)
    result = subprocess.run(["/usr/bin/" + name, *args])
    if name == "mv" and destination.endswith("/current") and result.returncode == 0:
        record("activate")
    raise SystemExit(result.returncode)
elif name == "prepare-piper-development-companion.sh":
    record("prepare-development-piper")
    print(os.environ["STAGING_PIPER_DIR"])
elif name in ("verify-toolchain.sh", "verify-helper-determinism.sh",
              "prepare-piper-companion.sh", "verify-runtime.sh",
              "verify-runtime-live.sh", "verify-main-live.sh"):
    record(name)
    if name.startswith("verify-runtime"):
        current = Path(args[0]) / "current"
        if not current.is_symlink() or not (current / "SHA256SUMS").is_file():
            raise SystemExit("Final verification ran before activation")
    if name == os.environ.get("STAGING_FAIL_VERIFY"):
        raise SystemExit("Injected final verification failure")
else:
    raise SystemExit(f"Unexpected fixture tool: {name}")
