#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the Swift SSH client against a disposable WSL OpenSSH and Emacs."""
import argparse
import base64
import contextlib
import getpass
import json
import os
from pathlib import Path
import queue
import shutil
import signal
import socket
import socketserver
import subprocess
import tempfile
import termios
import threading
import time

APP = Path(__file__).resolve().parents[1]
QUIET = subprocess.DEVNULL


def until(label, check, seconds=12):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.07)
    raise RuntimeError("Timed out waiting for " + label)


class LocalSSH(socketserver.ThreadingTCPServer):
    daemon_threads = True


@contextlib.contextmanager
def serve_ssh(sshd, root):
    host = root / "host"
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", host], check=True)
    config = root / "sshd_config"
    lines = [
        f'HostKey "{host}"', f'AuthorizedKeysFile "{root}/authorized_keys"',
        "AuthenticationMethods publickey", "PasswordAuthentication no", "UsePAM no",
        "PermitUserRC no", "DisableForwarding yes", "LogLevel ERROR",
    ]
    # Ubuntu's unpacked server uses matching session and authentication helpers.
    helpers = sshd.parent.parent / "lib/openssh"
    if sshd != Path("/usr/sbin/sshd"):
        for option, binary in [("SshdSessionPath", "sshd-session"), ("SshdAuthPath", "sshd-auth")]:
            if (helpers / binary).is_file():
                lines.append(f'{option} "{helpers / binary}"')
    config.write_text("\n".join(lines) + "\n")
    subprocess.run([sshd, "-t", "-f", config], check=True)

    class Connection(socketserver.BaseRequestHandler):
        def handle(self):
            with subprocess.Popen([sshd, "-i", "-f", config], stdin=self.request,
                                  stdout=self.request, stderr=QUIET) as child:
                try:
                    child.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    child.kill()

    with LocalSSH(("127.0.0.1", 0), Connection) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield server.server_address[1]
        finally:
            server.shutdown()
            thread.join()


@contextlib.contextmanager
def listen_for_navigation(root):
    armed = threading.Event()
    marker = threading.Event()
    path = root / "speech.sock"
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(str(path))
        listener.listen(1)

        def read():
            conn, _ = listener.accept()
            with conn, conn.makefile("rb") as stream:
                stopped = queued = False
                for packet in stream:
                    if not armed.is_set():
                        continue
                    line = packet.strip()
                    if line == b"s":
                        stopped, queued = True, False
                    elif line.startswith(b"q ") and line[2:].strip(b" {}") == b"Cobalt lighthouse":
                        queued = True
                    elif line == b"d":
                        if stopped and queued:
                            marker.set()
                        queued = False

        threading.Thread(target=read, daemon=True).start()
        yield path, armed, marker


@contextlib.contextmanager
def test_emacs(root, speech):
    env = dict(os.environ, EMACSVOX_SSH_TEST_DIR=str(root), EMACSVOX_PHONE_SOCKET=str(speech),
               XDG_RUNTIME_DIR=str(root), GDK_BACKEND="x11")
    with subprocess.Popen(["xvfb-run", "-a", APP / "test-session", "-l", APP / "test/ssh-session.el"],
                          cwd=APP, env=env, stdout=QUIET, stderr=QUIET, start_new_session=True) as proc:
        try:
            marker = root / "server-path"
            until("isolated Emacs server", lambda: marker.is_file() and marker.stat().st_size, 45)
            yield marker.read_text()
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)


class Client:
    def __init__(self, command):
        self.proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.events = queue.Queue()

        def collect():
            for line in self.proc.stdout:
                self.events.put(line.strip())
            self.events.put("closed")

        threading.Thread(target=collect, daemon=True).start()

    def ready(self):
        seen = set()
        while seen != {"ready", "display"}:
            event = self.events.get(timeout=15)
            if event not in {"ready", "display"}:
                raise RuntimeError("SSH startup failed: " + event)
            seen.add(event)

    def command(self, line):
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def keys(self, data):
        self.command("input " + base64.b64encode(data).decode())

    def close(self):
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait(timeout=4)
        self.proc.stdin.close()
        self.proc.stdout.close()


def check_session(probe, emacsclient, root, port, server, arm_speech, speech):
    key, other = root / "seed", root / "wrong-seed"
    for path in [key, other]:
        path.write_bytes(os.urandom(32))
        path.chmod(0o600)
    pub = subprocess.check_output([probe, "public-key", key], text=True)
    authorized = root / "authorized_keys"
    authorized.write_text(pub)
    pin = root / "host.pub"

    def command(identity=key, host_key=pin):
        return [probe, "connect", identity, str(port), getpass.getuser(), host_key, server, emacsclient]

    def reject(args, expected):
        run = subprocess.run(args, stdin=QUIET, capture_output=True, text=True, timeout=18)
        if run.returncode == 0 or run.stdout.splitlines() != ["error " + expected]:
            raise RuntimeError(f"Expected {expected}, got {run.stdout.strip()!r}")

    reject(command(host_key=authorized), "hostKeyMismatch")
    reject(command(identity=other), "keyRejected")
    authorized.write_text("no-pty " + pub)
    reject(command(), "requestRejected")
    authorized.write_text(pub)
    missing = command()
    missing[-2] = str(root / "missing-server")
    run = subprocess.run(missing, input="wait\n", capture_output=True, text=True, timeout=18)
    assert run.returncode == 0 and "exit status(1)" in run.stdout.splitlines()
    assert not (root / "missing-server").exists()
    print("Rejected a changed host key, an untrusted identity and a refused PTY.", flush=True)

    def observe(form):
        value = subprocess.check_output([emacsclient, "-s", server, "-e", form], text=True, timeout=20)
        return value.strip()

    def frame_value(form):
        return observe("(let ((f (seq-find (lambda (f) (not (display-graphic-p f))) (frame-list)))) "
                       "(when f (let ((w (frame-selected-window f))) "
                       "(with-current-buffer (window-buffer w) (save-excursion (goto-char (window-point w)) "
                       + form + ")))))")

    def on_frame(form):
        return frame_value(form) == "t"

    original = observe("(emacs-pid)")
    def same_buffer():
        return on_frame("(eq (window-buffer (frame-selected-window f)) iphone-ssh-test-buffer)")

    def select_sample(client):
        client.keys(b"\x18bPhone SSH sample\r")
        until("existing Agent Shell buffer", same_buffer)

    frame_gone = "(seq-every-p #'display-graphic-p (frame-list))"
    with contextlib.closing(Client(command())) as first:
        first.ready()
        until("TTY frame", lambda: on_frame("(= (frame-width f) 80)"))
        height = int(frame_value("(frame-height f)"))
        tty = json.loads(frame_value("(terminal-name (frame-terminal f))"))
        fd = os.open(tty, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
        try:
            assert termios.tcgetwinsize(fd) == (24, 80)
            first.command("resize 104 36")
            until("kernel PTY resize", lambda: termios.tcgetwinsize(fd) == (36, 104))
            until("Emacs frame resize", lambda: on_frame(
                f"(and (= (frame-width f) 104) (= (frame-height f) {height + 12}))"))
        finally:
            os.close(fd)
        select_sample(first)
        arm_speech.set()
        first.keys(b"\x0e")  # C-n in an existing response
        until("destination response row", lambda: on_frame(
            "(and (string-search \"Cobalt lighthouse\" (thing-at-point 'line t)) t)"))
        until("stop, destination text and dispatch on the phone backend", speech.is_set)
        file = root / "keyboard.txt"
        first.keys(b"\x18\x06" + os.fsencode(file) + b"\r")
        until("file buffer", lambda: on_frame("(equal buffer-file-name " + json.dumps(str(file)) + ")"))
        first.keys("Café from the terminal".encode() + b"\r\x18\x13")
        until("UTF-8 file saved exactly once", lambda: file.is_file() and file.read_bytes() == "Café from the terminal\n".encode())
        first.keys(b"\x1bxforward-ch")  # M-x plus a partial command
        until("command in the phone minibuffer", lambda: on_frame(
            '(and (minibufferp) (equal (minibuffer-contents-no-properties) "forward-ch"))'))
        first.keys(b"\x07")
        until("C-g returns to the edited file", lambda: on_frame(
            "(equal buffer-file-name " + json.dumps(str(file)) + ")"))
        first.command("disconnect")
        assert first.proc.wait(timeout=5) == 0
    until("old TTY frame to close", lambda: observe(frame_gone) == "t")
    with contextlib.closing(Client(command())) as second:
        second.ready()
        select_sample(second)
        assert observe("(emacs-pid)") == original
        second.keys(b"\x1850")  # C-x 5 0 deletes this frame
        second.command("wait")
        assert second.events.get(timeout=8) == "exit status(0)"
        assert second.proc.wait(timeout=8) == 0
    until("second frame to close", lambda: observe(frame_gone) == "t")
    print("Passed PTY resize, Agent Shell navigation and speech dispatch, UTF-8 editing, "
          "Meta and Control input, disconnect and reattachment to the same buffer.")


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--sshd", type=Path, default=Path("/usr/sbin/sshd"))
    args.add_argument("--probe", type=Path, default=APP / "ssh/.build/debug/SessionProbe")
    args.add_argument("--emacsclient", default=shutil.which("emacsclient"))
    opt = args.parse_args()
    cache = Path.home() / ".cache/emacsvox"
    cache.mkdir(parents=True, exist_ok=True)
    # StrictModes checks every parent of authorized_keys. Use a private home directory.
    with tempfile.TemporaryDirectory(prefix="ssh-", dir=cache) as temp:
        root = Path(temp)
        with serve_ssh(opt.sshd.resolve(), root) as port, listen_for_navigation(root) as (socket_path, arm, marker):
            with test_emacs(root, socket_path) as server:
                check_session(opt.probe.resolve(), opt.emacsclient, root, port, server, arm, marker)


if __name__ == "__main__":
    main()
