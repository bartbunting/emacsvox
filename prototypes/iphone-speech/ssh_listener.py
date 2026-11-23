# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""A disposable OpenSSH endpoint owned by the foreground test process."""
import contextlib
from pathlib import Path
import socket
import socketserver
import subprocess
import threading
from phone_tcp import limit_phone_segments

QUIET = subprocess.DEVNULL

class LocalSSH(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self):
        limit_phone_segments(self.socket)
        super().server_bind()


@contextlib.contextmanager
def serve_ssh(sshd, root, *, address="127.0.0.1", port=0, peer=None, host_key=None):
    host = host_key or root / "host"
    if host_key is None:
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", host], check=True)
    else:
        public = subprocess.check_output(["ssh-keygen", "-y", "-P", "", "-f", host], text=True)
        if not public.startswith("ssh-ed25519 "):
            raise ValueError("Choose an Ed25519 host key.")
        (root / "host.pub").write_text(public)
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

    active = set()
    lock = threading.Lock()
    closing = False

    class Connection(socketserver.BaseRequestHandler):
        def handle(self):
            if peer and self.client_address[0] != peer:
                return
            with lock:
                if closing:
                    return
                active.add(self.request)
            try:
                self.run_session()
            finally:
                with lock:
                    active.discard(self.request)

        def run_session(self):
            with subprocess.Popen([sshd, "-i", "-f", config], stdin=self.request,
                                  stdout=self.request, stderr=QUIET) as child:
                try:
                    child.wait(timeout=None if peer else 90)
                except subprocess.TimeoutExpired:
                    child.kill()

    with LocalSSH((address, port), Connection) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield server.server_address[1]
        finally:
            server.shutdown()
            thread.join()
            with lock:
                closing = True
                for connection in active:
                    with contextlib.suppress(OSError):
                        connection.shutdown(socket.SHUT_RDWR)
