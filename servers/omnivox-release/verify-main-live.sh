#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 OMNIVOX_RUNTIME_DIR" >&2
    exit 2
fi

runtime_root=$1
current=$(readlink -f -- "$runtime_root/current")
versions_root=$(readlink -f -- "$runtime_root/versions")
case "$current/" in
    "$versions_root"/*/) ;;
    *)
        echo "Omnivox current does not resolve below $versions_root" >&2
        exit 1
        ;;
esac

for expected in \
    'build_kind=local-dirty-worktree' \
    'build_method=incremental-main-executable-reuse'; do
    if ! grep -Fxq "$expected" "$current/PROVENANCE"; then
        echo "Main-only Omnivox provenance is missing: $expected" >&2
        exit 1
    fi
done
build_id=$(sed -n 's/^build_id=//p' "$current/PROVENANCE")
if [ "$build_id" != "$(basename -- "$current")" ]; then
    echo "Main-only Omnivox build identity is inconsistent" >&2
    exit 1
fi

windows_runtime=$(wslpath -u "$(sed -n '1p' "$current/windows-runtime.path")")
windows_program=$windows_runtime/omnivox.exe
if [ ! -x "$windows_program" ] ||
   ! cmp -s "$current/omnivox.exe" "$windows_program" ||
   ! cmp -s "$current/PROVENANCE" "$windows_runtime/PROVENANCE"; then
    echo "Windows-local main Omnivox payload differs from the staged runtime" >&2
    exit 1
fi

espeak_data_path=$(sed -n '1p' "$current/espeak-ng-data.path")
case ":${WSLENV-}:" in
    *:ESPEAK_NG_DATA:* | *:ESPEAK_NG_DATA/*) ;;
    *) WSLENV="${WSLENV:+$WSLENV:}ESPEAK_NG_DATA" ;;
esac
export WSLENV
voices=$(ESPEAK_NG_DATA="$espeak_data_path" \
    "$windows_program" --engine espeak --list-voices-alist)
if ! printf '%s\n' "$voices" |
    grep -Fq '("espeak:gmw\\en-US" "English (America)" "en-us" "Compact")'; then
    echo "Main-only staged Omnivox did not report its default eSpeak voice" >&2
    exit 1
fi

printf '%s\n' \
    "verified_main_build_id=$build_id" \
    "live_main_runtime=$windows_runtime"
