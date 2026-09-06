#!/usr/bin/env python3
"""Build a source-only Emacsvox Debian package without modifying the checkout."""

# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
from email.utils import formatdate
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
MAINTAINER = "Bart Bunting <bartbunting@users.noreply.github.com>"
DEPENDS = " | ".join(f"{name} (>= 1:30.2)" for name in
                      ("emacs", "emacs-gtk", "emacs-pgtk", "emacs-lucid", "emacs-nox"))
RECOMMENDS = "omnivox (>= 1.7.0)"
RUNTIME_FILES = {
    "VERSION", "README.org", "COPYING", "AUTHORS", "THIRD_PARTY_NOTICES",
    "bin/emacsvox", "bin/emacsvox-omnivox-components",
    "servers/omnivox", "servers/omnivox-log-filter",
    "utils/emacsvox-remote-startup.el", "utils/emacsvox-remote-check.el",
}
RUNTIME_TREES = {"sounds", "etc", "xsl", "js", "LICENSES"}


def output(*command, cwd=ROOT, env=None):
    return subprocess.check_output(command, cwd=cwd, env=env, text=True).strip()


def source_identity(root):
    """Hash tracked and unignored source, including work in progress and modes."""
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root).split(b"\0")
    digest = hashlib.sha256()
    files = []
    for raw in sorted(set(names) - {b""}):
        name = os.fsdecode(raw)
        path = root / name
        digest.update(raw + b"\0")
        if path.is_symlink():
            digest.update(b"symlink\0" + os.fsencode(os.readlink(path)))
        elif path.is_file():
            digest.update(str(path.stat().st_mode & 0o777).encode() + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
            files.append(name)
        else:
            digest.update(b"deleted\0")
    return files, {
        "source_commit": output("git", "rev-parse", "HEAD", cwd=root),
        "source_sha256": digest.hexdigest(),
        "source_epoch": output("git", "show", "-s", "--format=%ct", "HEAD", cwd=root),
    }


def include(name):
    path = Path(name)
    if any(part.startswith(".") for part in path.parts):
        return False
    if path.suffix in {".elc", ".pyc", ".o", ".exe", ".dll"}:
        return False
    return (name in RUNTIME_FILES or path.parts[0] in RUNTIME_TREES
            or path.parts[:2] == ("media", "radio")
            or (path.parent == Path("lisp") and path.suffix == ".el")
            or (path.parent == Path("info") and ".info" in path.name))


def copy_file(source, destination):
    if source.is_symlink() or not source.is_file():
        raise RuntimeError(f"missing regular payload file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    destination.chmod(0o755 if source.stat().st_mode & 0o111 else 0o644)


def write_gzip(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(gzip.compress(contents, mtime=0))


def package(root, destination, emacs, release=False):
    root = root.resolve()
    destination = destination.resolve()
    emacs = shutil.which(emacs)
    if not emacs:
        raise RuntimeError("Emacs build executable not found")
    emacs_version = output(emacs, "-Q", "--batch", "--eval",
                           '(progn (unless (version<= "30.2" emacs-version) '
                           '(error "Emacs 30.2 or newer required")) (princ emacs-version))')
    if release:
        # A release deb cannot bypass the existing clean-source, complete-test,
        # documentation and checked-source-archive gates, even via this script.
        subprocess.run(["make", "release-artifact-check", f"EMACS={emacs}",
                        f"DIST_DIR={destination}"], cwd=root, check=True)
    files, identity = source_identity(root)
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"[0-9]{4}\.(?:[1-9]|1[0-2])\.(?:0|[1-9][0-9]*)", version):
        raise RuntimeError("invalid canonical VERSION")
    package_version = (f"{version}-1" if release else
                       f"{version}+git{identity['source_commit'][:7]}."
                       f"{identity['source_sha256'][:12]}-0local1")
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f"emacsvox_{package_version}_all.deb"
    with tempfile.TemporaryDirectory(prefix=".emacsvox-deb-", dir=destination) as temporary:
        work = Path(temporary)
        stage = work / "package"
        runtime = stage / "usr/share/emacsvox"
        for name in files:
            if include(name):
                copy_file(root / name, runtime / name)
        for name in RUNTIME_FILES | {"lisp/emacsvox-setup.el", "info/emacsvox.info",
                                     "sounds/packs/chimes/open-object.ogg"}:
            if not (runtime / name).is_file():
                raise RuntimeError(f"required package input missing: {name}")
        # Generate in the staging tree with no personal packages and never copy
        # ignored checkout autoloads or byte-code into a distribution.
        private_home = work / "home"
        private_home.mkdir()
        environment = {**os.environ, "HOME": str(private_home),
                       "SOURCE_DATE_EPOCH": identity["source_epoch"],
                       "EMACSVOX_DEB_LISP": str(runtime / "lisp")}
        subprocess.run([emacs, "-Q", "--batch", "--eval",
                        '(progn (require \'loaddefs-gen) '
                        '(let ((dir (getenv "EMACSVOX_DEB_LISP"))) '
                        '(loaddefs-generate dir (expand-file-name "emacsvox-loaddefs.el" dir))))'],
                       env=environment, cwd=work, check=True)
        launcher = stage / "usr/bin/emacsvox"
        launcher.parent.mkdir(parents=True)
        launcher.write_text(
            '#!/bin/sh\n# Copyright (C) 2026 Emacsvox contributors\n'
            '# SPDX-License-Identifier: GPL-2.0-or-later\n'
            'exec /usr/share/emacsvox/bin/emacsvox "$@"\n')
        launcher.chmod(0o755)
        docs = stage / "usr/share/doc/emacsvox"
        for name in ("COPYING", "AUTHORS", "THIRD_PARTY_NOTICES"):
            copy_file(root / name, docs / name)
        copy_file(root / "packaging/debian/README.Debian", docs / "README.Debian")
        copy_file(root / "packaging/debian/copyright", docs / "copyright")
        copy_file(root / "packaging/debian/emacsvox.1", work / "emacsvox.1")
        write_gzip(stage / "usr/share/man/man1/emacsvox.1.gz",
                   (work / "emacsvox.1").read_bytes())
        write_gzip(docs / "NEWS.gz", (root / "etc/NEWS").read_bytes())
        write_gzip(docs / "changelog.Debian.gz", (
            f"emacsvox ({package_version}) unstable; urgency=medium\n\n"
            "  * Package the Emacsvox runtime, sources, sounds and offline manual.\n\n"
            f" -- {MAINTAINER}  {formatdate(int(identity['source_epoch']))}\n"
        ).encode())
        # Retain the full licence texts and file-specific notices in the runtime.
        # The manual remains available through Emacsvox's Info directory.
        provenance = {**identity, "package_version": package_version,
                      "autoload_emacs": emacs_version,
                      "distribution": "release candidate" if release else "local development build"}
        (docs / "BUILD-INFO.json").write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
        control = stage / "DEBIAN"
        control.mkdir()
        payload = sorted(p for p in stage.rglob("*") if p.is_file())
        size = sum((p.stat().st_size + 1023) // 1024 for p in payload)
        (control / "control").write_text(
            f"Package: emacsvox\nVersion: {package_version}\nArchitecture: all\n"
            f"Maintainer: {MAINTAINER}\nSection: editors\nPriority: optional\n"
            f"Installed-Size: {size}\nDepends: {DEPENDS}\nRecommends: {RECOMMENDS}\n"
            "Suggests: elpa-hydra, sox, curl, xsltproc\n"
            "Homepage: https://github.com/bartbunting/emacsvox\n"
            "Description: speech interface and audio desktop for GNU Emacs\n"
            " Provides speech-enabled editing, navigation and application integrations.\n"
            " Includes Lisp sources, auditory icons, offline manuals and an isolated\n"
            " launcher. Supports local Omnivox or remote workstation speech.\n"
            " Does not activate speech in other Emacs sessions or build GNU Emacs.\n")
        (control / "md5sums").write_text("".join(
            f"{hashlib.md5(p.read_bytes()).hexdigest()}  {p.relative_to(stage)}\n"
            for p in payload))
        for path in [stage, *stage.rglob("*")]:
            path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
            os.utime(path, (int(identity["source_epoch"]),) * 2)
        candidate = work / archive.name
        subprocess.run(["dpkg-deb", "--root-owner-group", "-Zxz", "--build",
                        str(stage), str(candidate)], env=environment, check=True)
        if source_identity(root)[1] != identity:
            raise RuntimeError("source changed while packaging; rerun the build")
        if release:
            subprocess.run(["make", "release-artifact-check", f"EMACS={emacs}",
                            f"DIST_DIR={destination}"], cwd=root, check=True)
        candidate.replace(archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(".deb.sha256").write_text(f"{digest}  {archive.name}\n")
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--emacs", default=os.environ.get("EMACS", "emacs"))
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--development", action="store_true", help="label uncommitted work as a local build")
    mode.add_argument("--release", action="store_true", help="require the checked release source artifact")
    args = parser.parse_args()
    try:
        print(package(args.source, args.output_dir, args.emacs, args.release))
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
