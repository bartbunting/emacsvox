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
        elif command == "pad":
            size = os.get_terminal_size(1)
            emit(f"\x1b[2J\x1b[{size.lines};{size.columns}H \x1b[H")
        elif command == "probe":
            emit("speech probe\r\n")
        elif command in ("menu", "token"):
            # Survey output as used by glab 1.53, with no authentication.
            question = "? How would you like to sign in?  [Use arrows to move, type to filter]"
            emit("\x1b7\x1b[?25l\x1b8\x1b[0G\x1b[2K" + question)
            emit("\r\n> Token\r\n  Web\r\n\x1b7\x1b[1A\x1b[0G\x1b[1A\x1b[0G")
            if command == "token":
                if os.read(0, 1) != b"\r":
                    raise RuntimeError("Expected Enter")
                emit("\x1b8\x1b[?25h\x1b8\x1b[0G\x1b[2K" + "\x1b[1A\x1b[0G\x1b[2K" * 3)
                emit("? How would you like to sign in? Token\r\n\r\n")
                emit("? Paste your authentication token: \x1b7\x1b[999;999f\x1b8")
                if os.read(0, 1) != b"\x03":
                    raise RuntimeError("Expected cancellation without credentials")
                emit("\r\nREADY> ")
                command = ""
                continue
            if os.read(0, 3) != b"\x1b[B":
                raise RuntimeError("Expected down arrow")
            emit("\x1b8\x1b[0G\x1b[2K" + "\x1b[1A\x1b[0G\x1b[2K" * 3)
            emit(question + "\r\n  Token\r\n> Web\r\n\x1b7\x1b[1A\x1b[0G")
            if os.read(0, 1) != b"\r":
                raise RuntimeError("Expected Enter")
            emit("\x1b8\x1b[?25hSelected Web\r\n")
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
