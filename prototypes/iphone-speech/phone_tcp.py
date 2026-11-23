# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Set the TCP segment size before a phone connection negotiates its MSS."""
import os
from pathlib import Path
import socket
import sys


def limit_phone_segments(listener):
    # A 1280-byte WSL uplink also has to carry Tailscale's outer packet.
    listener.setsockopt(socket.IPPROTO_TCP, socket.TCP_MAXSEG, 1120)


if __name__ == "__main__":
    port, host, *args = sys.argv[1:]
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        limit_phone_segments(listener)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((host, int(port)))
        listener.set_inheritable(True)
        os.environ["EMACSVOX_PHONE_LISTEN_FD"] = str(listener.fileno())
        # Node calls listen when the Emacs frame launcher signals readiness.
        os.execvp("node", ["node", str(Path(__file__).with_name("relay.cjs")), host, *args])
