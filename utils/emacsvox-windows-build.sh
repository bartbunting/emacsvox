#!/usr/bin/env bash
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
# Inputs are environment data supplied by PowerShell, never shell source.
work=/emacsvox-build
archive=/emacsvox-source.tar.xz
mkdir -p "$work/source" "$work/logs"
pacman -Q > "$work/logs/msys2-packages.txt"
gcc --version > "$work/logs/gcc-version.txt"
tar -xJf "$archive" -C "$work/source"
cd "$work/source/emacs-$EMACSVOX_NATIVE_VERSION"
# A simple MSYS prefix avoids GNU Make's limitations with spaces in prefixes.
# The complete relocatable Windows tree is moved to its final home afterwards.
./configure --prefix=/emacsvox-output --without-dbus \
    --without-native-compilation --with-gnutls --with-xml2 \
    --with-tree-sitter --with-sqlite3 --with-modules \
    > "$work/logs/configure.log" 2>&1
make -j"$EMACSVOX_NATIVE_JOBS" > "$work/logs/build.log" 2>&1
# Windows domain accounts need MSYS2's numeric identity; an inherited short
# LOGNAME/USERNAME need not be a resolvable MSYS2 account name.
make install "set_installuser=installuser=$(id -u):$(id -g)" > "$work/logs/install.log" 2>&1
cp /ucrt64/bin/*.dll /emacsvox-output/bin/
