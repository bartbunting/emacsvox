#!/usr/bin/env python3
"""Report XKB modifier presses while the named Caps Lock indicator is on.

The parent Emacs owns focus eligibility and this process's lifetime.  Observe
modifier state only; do not intercept keys or change keyboard configuration.
Output is a line protocol: ready, then modifier for each qualifying press.
"""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import ctypes as c
import ctypes.util
import sys


class StateEvent(c.Structure):
    """XkbStateNotifyEvent from X11/XKBlib.h, using native ABI alignment."""

    _fields_ = [
        ("type", c.c_int), ("serial", c.c_ulong), ("send_event", c.c_int),
        ("display", c.c_void_p), ("time", c.c_ulong), ("xkb_type", c.c_int),
        ("device", c.c_int), ("changed", c.c_uint), ("group", c.c_int),
        ("base_group", c.c_int), ("latched_group", c.c_int),
        ("locked_group", c.c_int), ("mods", c.c_uint), ("base_mods", c.c_uint),
        ("latched_mods", c.c_uint), ("locked_mods", c.c_uint),
        ("compat_state", c.c_int), ("grab_mods", c.c_ubyte),
        ("compat_grab_mods", c.c_ubyte), ("lookup_mods", c.c_ubyte),
        ("compat_lookup_mods", c.c_ubyte), ("ptr_buttons", c.c_int),
        ("keycode", c.c_ubyte), ("event_type", c.c_ubyte),
        ("req_major", c.c_ubyte), ("req_minor", c.c_ubyte),
    ]


class Event(c.Union):
    _fields_ = [("state", StateEvent), ("pad", c.c_long * 24)]


def watch(display_name):
    library = ctypes.util.find_library("X11")
    if not library:
        raise RuntimeError("libX11 unavailable")
    x = c.CDLL(library)
    x.XOpenDisplay.argtypes = [c.c_char_p]
    x.XOpenDisplay.restype = c.c_void_p
    x.XCloseDisplay.argtypes = [c.c_void_p]
    x.XInternAtom.argtypes = [c.c_void_p, c.c_char_p, c.c_int]
    x.XInternAtom.restype = c.c_ulong
    x.XkbGetNamedIndicator.argtypes = [c.c_void_p, c.c_ulong, c.POINTER(c.c_int),
                                      c.POINTER(c.c_int), c.c_void_p, c.c_void_p]
    x.XkbSelectEvents.argtypes = [c.c_void_p, c.c_uint, c.c_uint, c.c_uint]
    x.XkbQueryExtension.argtypes = [c.c_void_p] + [c.POINTER(c.c_int)] * 5
    x.XNextEvent.argtypes = [c.c_void_p, c.POINTER(Event)]
    x.XFlush.argtypes = [c.c_void_p]
    display = x.XOpenDisplay(display_name.encode())
    if not display:
        raise RuntimeError("X display unavailable")
    try:
        opcode, event_base, error_base = c.c_int(), c.c_int(), c.c_int()
        major, minor = c.c_int(1), c.c_int(0)
        if not x.XkbQueryExtension(display, c.byref(opcode), c.byref(event_base),
                                   c.byref(error_base), c.byref(major), c.byref(minor)):
            raise RuntimeError("XKB extension unavailable")
        atom = x.XInternAtom(display, b"Caps Lock", 1)
        index, state = c.c_int(), c.c_int()

        def caps_on():
            if not atom or not x.XkbGetNamedIndicator(
                    display, atom, c.byref(index), c.byref(state), None, None):
                raise RuntimeError("Caps Lock indicator unavailable")
            return bool(state.value)

        caps_on()  # Fail before readiness if this display has no named indicator.
        # Core keyboard, XkbStateNotifyMask.  No keyboard or pointer grab.
        if not x.XkbSelectEvents(display, 0x100, 1 << 2, 1 << 2):
            raise RuntimeError("XKB state notifications unavailable")
        x.XFlush(display)
        print("ready", flush=True)
        event = Event()
        while True:
            x.XNextEvent(display, c.byref(event))
            state_event = event.state
            if (state_event.type == event_base.value
                    and state_event.xkb_type == 2  # XkbStateNotify
                    and state_event.changed & (1 << 1)  # XkbModifierBaseMask
                    and state_event.event_type == 2  # KeyPress, never release
                    and state_event.base_mods & ~2  # Exclude LockMask itself
                    and caps_on()):
                print("modifier", flush=True)
    finally:
        x.XCloseDisplay(display)


if __name__ == "__main__":
    try:
        watch(sys.argv[1])
    except (IndexError, OSError, RuntimeError) as error:
        print(f"unavailable: {error}", flush=True)
        sys.exit(1)
