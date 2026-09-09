#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Observe legacy protocol fragments with an explicitly selected, muted Omnivox.

Usage: python3 test/diagnose-queue-fragments.py /path/to/omnivox
This characterizes the existing server; it does not test a client queue proof.
"""

import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time


LIMIT = 512 * 1024
FINAL = b"q {NEW}\nemacsvox_marker_dispatch 91\n"


CASES = (
    ("complete-stop", ("q {EARLIER}\n", "s\n"), False),
    ("partial-stop", ("q {EARLIER}\n", "q {", "s\n"), True),
    ("partial-reset", ("q {EARLIER}\n", "q {", "tts_reset\n"), True),
    ("partial-dispatch", ("q {EARLIER}\n", "q {", "d\n"), True),
    ("later-boundary-stop", ("q {EARLIER}\n", "q {", "s\n", "s\n"), False),
    ("complete-code-stop", ("q {EARLIER}\n", "c {opaque}\n", "s\n"), False),
    ("crlf-stop", ("q {EARLIER}\n", "s\r\n"), False),
)


def check_observation(name, output, expected_earlier, expected_pong=False):
    texts = []
    for line in output.splitlines():
        if line.startswith(b"__EMACSVOX_MARKER__ "):
            event = json.loads(base64.b64decode(line.split(b" ", 1)[1]))
            if event.get("dispatch_id") == 91 and event.get("type") == "utterance_started":
                texts.append(event["text"])
    earlier = any("EARLIER" in text for text in texts)
    pong = b"OMNIVOX-REMOTE pong\n" in output
    if (
        earlier != expected_earlier
        or "NEW" not in texts
        or b"__EMACSVOX_TRACKED__ 91 completed" not in output
        or pong != expected_pong
    ):
        raise RuntimeError(f"Unexpected {name} observation: {texts!r}; pong={pong}")
    print(json.dumps({"case": name, "earlier_survives": earlier,
                      "started_texts": texts, "pong": pong}), flush=True)


def read_until(stream, marker):
    output = bytearray()
    deadline = time.monotonic() + 30
    while marker not in output:
        stream.settimeout(max(0.001, deadline - time.monotonic()))
        part = stream.recv(65536)
        if not part:
            return bytes(output)
        output.extend(part)
        if len(output) > 2 * LIMIT:
            raise RuntimeError("Diagnostic response exceeds its bound")
    return bytes(output)


def remote_connection(port, token, session):
    deadline = time.monotonic() + 10
    while True:
        stream = None
        try:
            stream = socket.create_connection(("127.0.0.1", port), timeout=2)
            stream.sendall(f"OMNIVOX-REMOTE 1 {token} {session} speaker\n".encode())
            reply = read_until(stream, b"\n")
            if b"OMNIVOX-REMOTE 1 ready\n" in reply:
                return stream
            if b"OMNIVOX-REMOTE 1 error busy\n" not in reply:
                stream.close()
                raise RuntimeError("Diagnostic remote authentication failed")
            stream.close()
        except (ConnectionRefusedError, ConnectionResetError, TimeoutError):
            if stream is not None:
                stream.close()
        if time.monotonic() >= deadline:
            raise RuntimeError("Diagnostic service did not become ready")
        time.sleep(0.1)


def remote_observations(server):
    # Private ephemeral service; no installed token, tunnel or live lane is used.
    with tempfile.TemporaryDirectory(prefix="emacsvox-fragment-") as directory:
        token = secrets.token_hex(32)
        session = secrets.token_hex(16)
        token_path = Path(directory) / "token"
        with open(token_path, "w", opener=lambda path, flags: os.open(path, flags, 0o600)) as file:
            file.write(token)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        with tempfile.TemporaryFile() as log:
            service = subprocess.Popen(
                [server, "--serve", "--listen", f"127.0.0.1:{port}",
                 "--token-file", str(token_path), "--audio-output", "null"],
                stdin=subprocess.PIPE, stdout=log, stderr=log,
            )
            try:
                cases = [(name, "".join(chunks).encode(), earlier, False)
                         for name, chunks, earlier in CASES]
                cases.extend((
                    ("heartbeat-keeps-queue", b"q {EARLIER}\nOMNIVOX-REMOTE ping\n", True, True),
                    ("absorbed-heartbeat", b"q {EARLIER}\nq {OMNIVOX-REMOTE ping\n", True, False),
                    ("exact-limit-stop", b"q {EARLIER}\ns" + b" " * (LIMIT - 2) + b"\n", False, False),
                ))
                for name, wire, earlier, pong in cases:
                    with remote_connection(port, token, session) as stream:
                        stream.sendall(wire + FINAL)
                        check_observation("remote-" + name,
                                          read_until(stream, b"__EMACSVOX_TRACKED__ 91 completed\n"),
                                          earlier, pong)
                for name, wire in (
                    ("over-limit", b"s" + b" " * (LIMIT - 1) + b"\n"),
                    ("invalid-utf8", b"\xffs\n"),
                    ("nul", b"s\0\n"),
                    ("reserved-prefix", b"OMNIVOX-REMOTE invalid\n"),
                ):
                    with remote_connection(port, token, session) as stream:
                        stream.sendall(wire)
                        try:
                            output = read_until(stream, b"never-a-server-record\n")
                        except ConnectionResetError:
                            output = b""
                        if b"__EMACSVOX_TRACKED__" in output:
                            raise RuntimeError(f"Unexpected playback for remote {name}")
                    print(json.dumps({"case": "remote-" + name, "closed": True}), flush=True)
            finally:
                try:
                    service.communicate(b"quit\n", timeout=10)
                except subprocess.TimeoutExpired:
                    service.terminate()
                    try:
                        service.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        service.kill()
                        service.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server", help="Omnivox executable with eSpeak and null audio output")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--remote", action="store_true", help="also test a private loopback service")
    modes.add_argument("--remote-only", action="store_true", help="only test a private loopback service")
    args = parser.parse_args()
    cases = [(name, "".join(chunks).encode(), earlier) for name, chunks, earlier in CASES]
    cases.extend((
        ("local-exact-limit-stop", b"q {EARLIER}\ns" + b" " * (LIMIT - 1) + b"\n", False),
        ("local-over-limit-stop", b"q {EARLIER}\ns" + b" " * LIMIT + b"\n", True),
        ("local-over-limit-then-stop", b"q {EARLIER}\ns" + b" " * LIMIT + b"\ns\n", False),
        ("local-invalid-utf8", b"q {EARLIER}\n\xffs\n", True),
        ("local-invalid-utf8-then-stop", b"q {EARLIER}\n\xffs\ns\n", False),
    ))
    if args.remote_only:
        cases = []
    for name, wire, expected_earlier in cases:
        # The protocol sees a byte stream; OS write boundaries are immaterial.
        completed = subprocess.run(
            [args.server, "--engine", "espeak", "--audio-output", "null"],
            input=wire + FINAL,
            capture_output=True,
            timeout=30,
            check=True,
        )
        check_observation(name, completed.stdout, expected_earlier)
    if args.remote or args.remote_only:
        remote_observations(args.server)
    print(f"{len(cases)} local" + (" and 14 remote" if args.remote or args.remote_only else "")
          + " muted observations match the characterized server behavior.")


if __name__ == "__main__":
    main()
