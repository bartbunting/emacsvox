#!/usr/bin/env python3
"""Check staged repository files for private workstation and credential data."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import bz2
import gzip
import hashlib
import io
import lzma
import os
import re
import subprocess
import sys
import tarfile
import zipfile
import zlib


HOME = re.compile(
    rb"(?<![\w./\\-])(?:file://)?(?:/home/|/Users/|/mnt/[a-z]/Users/|[a-z]:[\\/]+Users[\\/]+)"
    rb"([a-z0-9_][\w.-]*)", re.I)
PORTABLE_USERS = {b"example", b"user", b"username", b"name"}
RULES = {
    "signed token": re.compile(rb"\beyJ[\w-]+\.eyJ[\w-]+\.[\w-]{12,}"),
    "listener token": re.compile(rb"[?&](?:amp;)?(?:partnertok|tdtok|sabc)=[\w%+/-]+", re.I),
    "private key": re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----"),
    "private VPN hostname": re.compile(rb"[\w-]\.ts\.net\b", re.I),
}

# Exact reviewed lines from historical sources, generated heritage Info, and
# fixtures which specifically exercise named paths. Editing the line reopens it.
HOME_EXCEPTIONS = {
    "blog-archive/articles.html": {
        "303e1b228156c0fdab962223ca826147c00a9cb19067eb605b55cb4d60c41468",
    },
    "blog-archive/full.xml": {
        "63e705ec76bf04441456968273fb43fcfeb31fc22ebab7fa1f6253892167b902",
    },
    "info/Makefile": {
        "1fb5e5790187786044318820a9496fdde7d1e9ac0f7b2609dcbefc717d320f40",
    },
    "info/emacsvox-heritage.info": {
        "9b87b61a6d0bec461d331069185785156425aeb8f6ff0613fdd28559041f1d57",
        "1c66be812260eba0f63a184bdbbfebb6adbdc9b96bc7b29d4053ec0164c85d62",
        "94efc21f8045d3cfd96dc9c0881bf643e2fbcc9cfeba0e580757f7c35afb7442",
    },
    "info/structure.texi": {
        "4bda3881a84047cce178c9aaa43d8264057d2de7f32b5d018a8868ced45d9c39",
    },
    "info/web-browsing.texi": {
        "e90ffac31ac578db399a5d89b64d8e6c5a9e7cd3a4269fba4905907f7b7bd664",
        "a3369ab6adb17c6d3f1b35d50bc35e0076c97e1f3ccaaaeb3f2d3ffa9d9f5fe1",
    },
    "stumpwm/stumpwmrc": {
        "e12c5a73c8115f05ec93b72b74e71bafd06f2d7122bb5dd6670ebafbbd6d2aa7",
    },
    "test/emacsvox-docs-check-tests.el": {
        "59e73698a8772d9313609d974b1adfeaa41a7b4fd461e689a53029ef3411b679",
    },
    "test/emacsvox-launcher-tests.el": {
        "ce5e1731273bae0e45b6c7ba325c5fa8c982d5a3ba547421a3ef32e8a69bdcf3",
        "88fbc0594652b09a8f99e5861b77dca210825cf4aa2f9be42c3e1199d9a2230a",
    },
    "test/emacsvox-self-document-tests.el": {
        "8c399d238792103796ee2039ae6c7236f615b170b9749a3a445bf3cc6cac281d",
    },
    "tvr/console-keymaps/rc.local": {
        "7d734b116be958cadad7c63ea90857e2fe707983f6447c51ea9492821ea901bf",
    },
    "tvr/not-used/psgml-prepare.el": {
        "57da7b6870abc98684d14cfc3f52b591d0ad87050ee2d03b4fcdb49dcfd360f5",
    },
}

# Count expanded bytes across the entire archive, including nested containers.
EXPANDED_LIMIT = 32 * 1024 * 1024
RAW_SPEECH_FILES = {b"session-events.eld", b"session-snapshot.eld"}
MEMBER_LIMIT = 2000
DEPTH_LIMIT = 4
COMPRESSIONS = (
    (b"\x1f\x8b", (b".gz", b".tgz"), gzip.open),
    (b"BZh", (b".bz2", b".tbz2"), bz2.open),
    (b"\xfd7zXZ\x00", (b".xz", b".txz"), lzma.open),
)


def text_findings(path, data):
    """Yield line numbers and rule names. Never return the matched data."""
    for number, line in enumerate(data.split(b"\n"), 1):
        if any(match[1].lower() not in PORTABLE_USERS for match in HOME.finditer(line)):
            if hashlib.sha256(line).hexdigest() not in HOME_EXCEPTIONS.get(path, ()):
                yield number, "personal home directory"
        for label, pattern in RULES.items():
            if pattern.search(line):
                yield number, label


def inspect_blob(path, data, *, symlink=False):
    """Inspect text and common archives in memory, without following member links."""
    remaining = EXPANDED_LIMIT
    members = 0

    def read_member(stream, size=None):
        nonlocal remaining
        if size is not None and size > remaining:
            raise ValueError("expansion limit")
        content = stream.read(remaining + 1 if size is None else size)
        remaining -= len(content)
        if remaining < 0 or (size is not None and len(content) != size):
            raise ValueError("invalid expanded size")
        return content

    def scan(content, name, location, depth):
        nonlocal members
        if depth > DEPTH_LIMIT:
            raise ValueError("nesting limit")
        if depth:
            for _, label in text_findings("", name):
                yield location, label
        lower_name = name.lower()
        if path.startswith("docs/evidence/") and lower_name.rsplit(b"/", 1)[-1] in RAW_SPEECH_FILES:
            yield location, "raw speech session capture"
        for magic, suffixes, opener in COMPRESSIONS:
            if content.startswith(magic) or lower_name.endswith(suffixes):
                inner_name = lower_name.rpartition(b".")[0]
                if lower_name.endswith((b".tgz", b".tbz2", b".txz")):
                    inner_name += b".tar"
                with opener(io.BytesIO(content), "rb") as stream:
                    yield from scan(read_member(stream), inner_name, location, depth + 1)
                return
        if content.startswith((b"PK\x03\x04", b"PK\x05\x06")) or lower_name.endswith(b".zip"):
            with zipfile.ZipFile(io.BytesIO(content)) as archive:
                for member in archive.infolist():
                    members += 1
                    if members > MEMBER_LIMIT:
                        raise ValueError("member limit")
                    with archive.open(member) as stream:
                        yield from scan(read_member(stream, member.file_size),
                                        os.fsencode(member.filename),
                                        f"{location} member {members}", depth + 1)
        elif content[257:262] == b"ustar" or name.lower().endswith(b".tar"):
            with tarfile.open(fileobj=io.BytesIO(content), mode="r:") as archive:
                for member in archive:
                    members += 1
                    if members > MEMBER_LIMIT:
                        raise ValueError("member limit")
                    item = f"{location} member {members}"
                    member_name = os.fsencode(member.name)
                    if member.isfile():
                        with archive.extractfile(member) as stream:
                            yield from scan(read_member(stream, member.size), member_name,
                                            item, depth + 1)
                    else:
                        for _, label in text_findings("", member_name + b"\n" + os.fsencode(member.linkname)):
                            yield item, label
        else:
            if content.startswith((b"\xff\xfe", b"\xfe\xff")):
                content = content.decode("utf-16").encode()
            elif b"\0" in content[:8192]:
                return
            for number, label in text_findings("" if depth else path, content):
                yield f"{location}:{number}", label

    if symlink:
        for number, label in text_findings(path, data):
            yield f":{number}", label
        return
    try:
        yield from scan(data, os.fsencode(path), "", 0)
    except (ValueError, EOFError, OSError, RuntimeError, tarfile.TarError,
            zipfile.BadZipFile, lzma.LZMAError, zlib.error):
        yield "", "archive unreadable or exceeds privacy scan limits"


def main():
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).rstrip(b"\n")
    entries = subprocess.check_output(["git", "ls-files", "--stage", "-z"], cwd=root)
    checked = findings = 0
    with subprocess.Popen(["git", "cat-file", "--batch"], cwd=root, stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE) as objects:
        try:
            for entry in entries.split(b"\0"):
                if not entry:
                    continue
                metadata, raw_path = entry.split(b"\t", 1)
                mode, oid, stage = metadata.split()
                if stage != b"0":
                    print("Resolve the conflicted Git index before running the privacy check.")
                    return 1
                if mode == b"160000":  # The submodule's files belong to its own repository.
                    continue
                path = os.fsdecode(raw_path)
                name_findings = list(text_findings("", raw_path))
                display = "[redacted filename]" if name_findings else ascii(path)
                objects.stdin.write(oid + b"\n")
                objects.stdin.flush()
                actual, kind, size = objects.stdout.readline().split()
                if actual != oid or kind != b"blob":
                    raise ValueError("unexpected Git object")
                data = objects.stdout.read(int(size))
                if len(data) != int(size) or objects.stdout.read(1) != b"\n":
                    raise ValueError("incomplete Git object")
                for _, label in name_findings:
                    print(f"{display}: {label}")
                    findings += 1
                for location, label in inspect_blob(path, data, symlink=mode == b"120000"):
                    print(f"{display}{location}: {label}")
                    findings += 1
                checked += 1
        finally:
            objects.stdin.close()
    if objects.returncode:
        return 1
    print(f"Privacy check: {checked} staged files, {findings} findings.")
    return int(bool(findings))


if __name__ == "__main__":
    sys.exit(main())
