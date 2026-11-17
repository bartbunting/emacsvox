#!/usr/bin/env python3
"""Set a lock indicator or focus only on the private Caps Lock test display."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import ctypes as c
import ctypes.util
import os
import sys

display_name = os.environ.get("EMACSVOX_CAPS_LOCK_TEST_DISPLAY")
if not display_name or display_name != os.environ.get("DISPLAY"):
    raise RuntimeError("Use the private graphical Caps Lock test runner")

x = c.CDLL(ctypes.util.find_library("X11"))
x.XOpenDisplay.argtypes = [c.c_char_p]
x.XOpenDisplay.restype = c.c_void_p
x.XCloseDisplay.argtypes = [c.c_void_p]
x.XSync.argtypes = [c.c_void_p, c.c_int]
x.XkbLockModifiers.argtypes = [c.c_void_p, c.c_uint, c.c_uint, c.c_uint]
x.XSetInputFocus.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_ulong]
x.XStringToKeysym.argtypes = [c.c_char_p]
x.XStringToKeysym.restype = c.c_ulong
x.XKeysymToKeycode.argtypes = [c.c_void_p, c.c_ulong]
x.XKeysymToKeycode.restype = c.c_ubyte
display = x.XOpenDisplay(display_name.encode())
if not display:
    raise RuntimeError("Private display unavailable")
try:
    action = sys.argv[1]
    if action in ("on", "off"):
        # Core keyboard; LockMask is bit 1, independently of indicator LED bits.
        if not x.XkbLockModifiers(display, 0x100, 2, 2 if action == "on" else 0):
            raise RuntimeError("XKB lock operation failed")
    elif action == "focus":
        x.XSetInputFocus(display, int(sys.argv[2], 0), 1, 0)
    elif action == "blur":
        x.XSetInputFocus(display, 0, 1, 0)  # None: no window has keyboard focus.
    elif action in ("press", "release"):
        xt = c.CDLL(ctypes.util.find_library("Xtst"))
        xt.XTestFakeKeyEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]
        key = x.XKeysymToKeycode(display, x.XStringToKeysym(sys.argv[2].encode()))
        if not key or not xt.XTestFakeKeyEvent(display, key, action == "press", 0):
            raise RuntimeError("Private key event failed")
    else:
        raise ValueError(action)
    x.XSync(display, 0)
finally:
    x.XCloseDisplay(display)
