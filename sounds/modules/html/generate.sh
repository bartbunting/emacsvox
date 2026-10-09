#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Generate a short, quiet HTML table cue with a smooth onset and decay.
set -eu
cd "$(dirname "$0")"
sox -n -r 44100 -c 1 html-table.ogg \
    synth 0.08 sine 900 fade h 0.005 0.08 0.07 gain -28
