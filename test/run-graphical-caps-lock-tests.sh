#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# The nested shell receives Xvfb's DISPLAY, never the desktop display.
set -eu
for program in xvfb-run Xvfb xauth timeout python3 xset; do
    command -v "$program" >/dev/null 2>&1 || { echo "Missing test utility: $program" >&2; exit 2; }
done
log=$(mktemp "${TMPDIR:-/tmp}/emacsvox-caps-lock-test.XXXXXX")
trap 'rm -f "$log"' EXIT
status=0
EMACSVOX_CAPS_LOCK_TEST_LOAD=compiled EMACSVOX_CAPS_LOCK_TEST_LOG="$log" GDK_BACKEND=x11 \
    timeout --kill-after=5s 45s xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
    sh -c 'export EMACSVOX_CAPS_LOCK_TEST_DISPLAY="$DISPLAY"; exec "$1" -Q --no-splash -l test/run-caps-lock-tests.el' \
    sh "$1" || status=$?
cat "$log"
exit "$status"
