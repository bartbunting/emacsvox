#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Run graphical checks on a private display, never the maintainer's desktop.
set -eu

for program in xvfb-run Xvfb xauth timeout; do
    if ! command -v "$program" >/dev/null 2>&1; then
        echo "Graphical voice tests require $program; no Emacs was started." >&2
        exit 2
    fi
done

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/emacsvox-graphical-voice.XXXXXX")
trap 'rm -f "$log"' EXIT
status=0
EMACSVOX_GRAPHICAL_TEST_LOG="$log" \
    timeout --kill-after=5s 45s \
    xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
    "$1" -Q -l "$root/test/run-graphical-voice-tests.el" || status=$?
cat "$log"
case "$status" in
    124|137) echo "Graphical voice tests timed out; the isolated test session was stopped." >&2 ;;
esac
exit "$status"
