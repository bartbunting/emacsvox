#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Run pinned graphical integrations without using the maintainer's display.
set -eu

for program in xvfb-run Xvfb xauth timeout; do
    if ! command -v "$program" >/dev/null 2>&1; then
        echo "Graphical integration tests require $program; no Emacs was started." >&2
        exit 2
    fi
done

"$1" -Q --batch --eval \
    '(unless (featurep (quote x)) (error "Graphical integration tests require an Emacs build with X11 support"))'

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/emacsvox-graphical-integration.XXXXXX")
trap 'rm -f "$log"' EXIT
status=0
EMACSVOX_GRAPHICAL_TEST_LOG="$log" TTS_PROGRAM=log-null GDK_BACKEND=x11 \
    timeout --kill-after=5s 60s \
    xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
    "$1" -Q -l "$root/test/run-integration-tests.el" || status=$?
cat "$log"
case "$status" in
    124|137) echo "Graphical integration tests timed out; the isolated session was stopped." >&2 ;;
esac
exit "$status"
