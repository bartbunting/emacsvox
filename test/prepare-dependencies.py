#!/usr/bin/env python3
"""Prepare verified, source-only dependencies for the integration test gate."""

# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_SOURCE_BYTES = 128 * 1024 * 1024
MANIFEST = "manifest.json"


class DependencyError(Exception):
    """A dependency input or prepared tree failed verification."""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def preparer_hash():
    return digest(Path(__file__).read_bytes() + (HERE / "prepare-dependencies.el").read_bytes())


def read_lock(path):
    data = path.read_bytes()
    lock = json.loads(data)
    if lock.get("schema") != 1 or not lock.get("packages"):
        raise DependencyError("Unsupported or empty integration dependency lock")
    names = set()
    for package in lock["packages"]:
        name = package["name"]
        if not re.fullmatch(r"[a-z][a-z0-9-]*", name) or name in names:
            raise DependencyError(f"Invalid or repeated dependency name: {name}")
        names.add(name)
        for field, length in (("commit", 40), ("sha256", 64)):
            if not re.fullmatch(rf"[0-9a-f]{{{length}}}", package[field]):
                raise DependencyError(f"Invalid {field} for {name}")
        url = urllib.parse.urlsplit(package["url"])
        if url.scheme != "https" or not url.hostname or url.username or url.password:
            raise DependencyError(f"Dependency {name} requires an HTTPS URL without credentials")
        root = package["archive_root"]
        subdir = PurePosixPath(package["subdirectory"])
        if (not root or root in (".", "..") or "/" in root or "\\" in root
                or subdir.is_absolute() or ".." in subdir.parts
                or "\\" in str(subdir)):
            raise DependencyError(f"Unsafe archive location for {name}")
        for excluded in package.get("excluded_paths", []):
            path = PurePosixPath(excluded)
            if not path.parts or path.is_absolute() or ".." in path.parts or "\\" in excluded:
                raise DependencyError(f"Unsafe excluded path for {name}")
    return lock, digest(data)


def emacs_version(emacs):
    result = subprocess.run(
        [emacs, "-Q", "--batch", "--eval",
         '(progn (unless (version<= "30.2" emacs-version) '
         '(error "Emacsvox requires Emacs 30.2 or newer")) (princ emacs-version))'],
        check=True, capture_output=True, text=True)
    return result.stdout.strip()


def inventory(directory):
    files = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise DependencyError(f"Unexpected symlink in test dependencies: {path}")
        if path.is_file() and path != directory / MANIFEST:
            files[path.relative_to(directory).as_posix()] = {
                "sha256": digest(path.read_bytes()),
                "executable": bool(path.stat().st_mode & 0o111)}
    return files


def check(directory, lock_hash, version):
    if directory.is_symlink() or not (directory / MANIFEST).is_file():
        raise DependencyError(f"Unprepared dependency directory: {directory}; run make test-deps")
    manifest = json.loads((directory / MANIFEST).read_text())
    if manifest.get("schema") != 1 or manifest.get("lock_sha256") != lock_hash:
        raise DependencyError(f"Dependency lock changed for {directory}; choose a new TEST_DEPS_DIR")
    if manifest.get("emacs_version") != version:
        raise DependencyError(f"Dependencies in {directory} were prepared by another Emacs; "
                              "use a separate checkout and TEST_DEPS_DIR")
    if manifest.get("preparer_sha256") != preparer_hash():
        raise DependencyError(f"Dependency preparer changed for {directory}; choose a new TEST_DEPS_DIR")
    expected = manifest["files"]
    actual = inventory(directory)
    if expected != actual:
        changed = sorted(name for name in expected.keys() | actual.keys()
                         if expected.get(name) != actual.get(name))
        raise DependencyError(f"Prepared dependency files changed in {directory}: "
                              + ", ".join(changed))


def archive(package, cache):
    path = cache / (package["sha256"] + ".tar")
    if path.exists():
        if path.is_symlink() or digest(path.read_bytes()) != package["sha256"]:
            raise DependencyError(f"Cached dependency checksum mismatch: {path}")
        return path
    print(f"Downloading {package['name']} from {package['url']}", flush=True)
    try:
        with urllib.request.urlopen(package["url"], timeout=30) as response:
            if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                raise DependencyError("Dependency download redirected away from HTTPS")
            data = response.read(MAX_ARCHIVE_BYTES + 1)
    except urllib.error.URLError as error:
        raise DependencyError(f"Cannot download {package['name']}: {error}") from error
    if len(data) > MAX_ARCHIVE_BYTES:
        raise DependencyError(f"Dependency archive too large: {package['name']}")
    if digest(data) != package["sha256"]:
        raise DependencyError(f"Downloaded dependency checksum mismatch: {package['name']}")
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temporary:
        temporary.write(data)
        temporary_path = Path(temporary.name)
    try:
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)
    return path


def extract(path, package, destination):
    prefix = PurePosixPath(package["archive_root"]) / package["subdirectory"]
    total = 0
    seen = set()
    with tarfile.open(path) as source:
        for member in source:
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or "\\" in member.name:
                raise DependencyError(f"Unsafe dependency archive path: {member.name}")
            try:
                relative = name.relative_to(prefix)
            except ValueError:
                continue
            if relative.as_posix() in package.get("excluded_paths", []):
                continue
            if not relative.parts or member.isdir():
                continue
            if not member.isfile() or relative in seen:
                raise DependencyError(f"Unsupported or repeated archive entry: {member.name}")
            if relative.suffix in (".elc", ".eln"):
                raise DependencyError(f"Compiled Lisp in source dependency: {member.name}")
            total += member.size
            if total > MAX_SOURCE_BYTES:
                raise DependencyError(f"Dependency sources too large: {package['name']}")
            seen.add(relative)
            target = destination.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.extractfile(member) as reader, target.open("wb") as writer:
                shutil.copyfileobj(reader, writer)
            # Preserve executable scripts, but never archive ownership or special bits.
            target.chmod(0o755 if member.mode & 0o111 else 0o644)
    if not any(destination.glob("*.el")):
        raise DependencyError(f"No Lisp sources found for {package['name']}")


def prepare(lock, lock_hash, directory, cache, emacs, version):
    if directory.exists() or directory.is_symlink():
        check(directory, lock_hash, version)
        return
    directory.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".emacsvox-test-deps-", dir=directory.parent))
    try:
        for package in lock["packages"]:
            extract(archive(package, cache), package, stage / package["name"])
        environment = os.environ.copy()
        environment["EMACSVOX_TEST_DEPS_STAGE"] = str(stage)
        environment["EMACSVOX_TEST_DEPS_NAMES"] = json.dumps(
            [package["name"] for package in lock["packages"]])
        subprocess.run([emacs, "-Q", "--batch", "-l", str(HERE / "prepare-dependencies.el")],
                       env=environment, check=True)
        manifest = {"schema": 1, "lock_sha256": lock_hash, "emacs_version": version,
                    "preparer_sha256": preparer_hash(),
                    "packages": [package["name"] for package in lock["packages"]],
                    "files": inventory(stage)}
        (stage / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        if directory.exists() or directory.is_symlink():
            raise DependencyError(f"Dependency destination appeared during preparation: {directory}")
        stage.rename(directory)
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emacs", required=True, help="Selected Emacs executable")
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=HERE.parent / ".test-deps-cache")
    parser.add_argument("--lock", type=Path, default=HERE / "integration-dependencies.json")
    parser.add_argument("--check", action="store_true", help="Verify without downloading or writing")
    args = parser.parse_args()
    try:
        lock, lock_hash = read_lock(args.lock)
        version = emacs_version(args.emacs)
        # Keep the final component unresolved so a destination symlink is rejected.
        directory = args.directory.absolute()
        if args.check:
            check(directory, lock_hash, version)
        else:
            prepare(lock, lock_hash, directory, args.cache, args.emacs, version)
        print(f"Verified {len(lock['packages'])} test dependencies for Emacs {version}: {directory}")
    except (DependencyError, OSError, ValueError, KeyError, tarfile.TarError,
            subprocess.CalledProcessError) as error:
        print(f"Test dependency preparation failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
