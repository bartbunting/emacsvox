#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Test menus on a private display with disposable preferences.
set -eu
for program in xvfb-run Xvfb xauth timeout; do
    if ! command -v "$program" >/dev/null 2>&1; then
        echo "Graphical menu tests require $program; no Emacs was started." >&2
        exit 2
    fi
done
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile=$(mktemp -d "${TMPDIR:-/tmp}/emacsvox-menu-test.XXXXXX")
log="$profile/results.log"
trap 'rm -rf "$profile"' EXIT
status=0
export EMACSVOX_MENU_TEST_PROFILE="$profile"
if [ -z "${EMACSVOX_MENU_TEST_PACKAGE_DIR:-}" ]; then
    python3 "$root/test/prepare-dependencies.py" --check --emacs "$1" \
        --directory "${EMACSVOX_TEST_DEPS_DIR:?Prepare TEST_DEPS_DIR first}" > "$log" 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        timeout --kill-after=5s 120s "$1" -Q --batch \
            -l "$root/test/prepare-menu-dependencies.el" >> "$log" 2>&1 || status=$?
    fi
    if [ "$status" -ne 0 ]; then cat "$log"; exit "$status"; fi
    export EMACSVOX_TEST_DEPS_DIR="$profile/dependencies"
    export EMACSVOX_MENU_TEST_PINNED=1
fi
EMACSVOX_MENU_TEST_PROFILE="$profile" EMACSVOX_GRAPHICAL_TEST_LOG="$log" GDK_BACKEND=x11 \
    timeout --kill-after=5s 180s \
    xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
    "$1" -Q -l "$root/test/run-graphical-menu-tests.el" || status=$?
if [ -f "$log" ]; then cat "$log"; fi
case "$status" in
    124|137) echo "Graphical menu tests timed out; the isolated session was stopped." >&2 ;;
esac
exit "$status"
