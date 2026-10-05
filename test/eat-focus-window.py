#!/usr/bin/env python3
"""Own X11 keyboard focus briefly on the isolated EAT test display."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import ctypes as c
import time
import sys

x = c.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes = [c.c_char_p]
x.XOpenDisplay.restype = c.c_void_p
x.XDefaultRootWindow.argtypes = [c.c_void_p]
x.XDefaultRootWindow.restype = c.c_ulong
x.XCreateSimpleWindow.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_int,
                                c.c_uint, c.c_uint, c.c_uint, c.c_ulong, c.c_ulong]
x.XCreateSimpleWindow.restype = c.c_ulong
x.XMapWindow.argtypes = [c.c_void_p, c.c_ulong]
x.XSetInputFocus.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_ulong]
x.XFlush.argtypes = [c.c_void_p]
x.XCloseDisplay.argtypes = [c.c_void_p]
display = x.XOpenDisplay(None)
if not display:
    raise RuntimeError('No X display')
try:
    if len(sys.argv) == 2:
        x.XSetInputFocus(display, int(sys.argv[1], 0), 1, 0)
        x.XFlush(display)
        sys.exit(0)
    window = x.XCreateSimpleWindow(display, x.XDefaultRootWindow(display),
                                   900, 10, 200, 100, 0, 0, 0xffffff)
    x.XMapWindow(display, window)
    x.XFlush(display)
    time.sleep(0.1)
    x.XSetInputFocus(display, window, 1, 0)
    x.XFlush(display)
    print('focused', flush=True)
    time.sleep(15)
finally:
    x.XCloseDisplay(display)
