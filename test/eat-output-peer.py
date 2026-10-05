#!/usr/bin/env python3
"""Disposable local PTY peer for EAT output tests; no network or child commands."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import termios
import time
import tty


def emit(text):
    os.write(1, text.encode())


original = termios.tcgetattr(0)
try:
    tty.setraw(0)
    emit("READY> ")
    command = ""
    while True:
        char = os.read(0, 1)
        if not char:
            break
        if char not in (b"\r", b"\n"):
            command += char.decode()
            emit(char.decode())
            continue
        emit("\r\n")
        if command == "margin":
            emit("x" * os.get_terminal_size(1).columns)
            time.sleep(0.15)
            emit("\r\nnext\r\n")
        elif command == "redraw":
            emit("\x1b[2J\x1b[Hredrawn-screen\r\n")
        else:
            operation, count = command.split()
            for index in range(int(count)):
                emit(("same" if operation == "same" else f"row-{index + 1:02}") + "\r\n")
                if operation == "split":
                    time.sleep(0.12)
        emit("READY> ")
        command = ""
finally:
    termios.tcsetattr(0, termios.TCSANOW, original)
