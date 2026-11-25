# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Send a physical key chord to the graphical frame on the test's private Xvfb."""
import ctypes as c
import os
import sys

if ("/xvfb-run." not in os.environ["XAUTHORITY"] or
        not os.environ["DISPLAY"].startswith(":") or int(os.environ["DISPLAY"][1:]) < 99):
    raise RuntimeError("A private xvfb-run display is required")

x11 = c.CDLL("libX11.so.6")
xtest = c.CDLL("libXtst.so.6")
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = c.c_void_p
x11.XSetInputFocus.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_ulong]
x11.XKeysymToKeycode.argtypes = [c.c_void_p, c.c_ulong]
x11.XStringToKeysym.argtypes = [c.c_char_p]
x11.XStringToKeysym.restype = c.c_ulong
x11.XSync.argtypes = [c.c_void_p, c.c_int]
xtest.XTestFakeKeyEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]
display = x11.XOpenDisplay(None)
if not display:
    raise RuntimeError("Could not open isolated display")
x11.XSetInputFocus(display, int(sys.argv[1], 0), 2, 0)
codes = [x11.XKeysymToKeycode(display, x11.XStringToKeysym(s.encode())) for s in sys.argv[2:]]
if not all(codes):
    raise ValueError("Unknown key")
for code in codes:
    xtest.XTestFakeKeyEvent(display, code, 1, 0)
for code in reversed(codes):
    xtest.XTestFakeKeyEvent(display, code, 0, 0)
x11.XSync(display, 0)
