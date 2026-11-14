#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Create unique, silent, valid WAV fixtures for the disposable audit."""

import struct
import sys
import wave
from pathlib import Path

output = Path(sys.argv[1])
for count in (1, 10, 40):
    directory = output / f"recordings-{count}"
    directory.mkdir(parents=True, exist_ok=True)
    for index in range(count):
        with wave.open(str(directory / f"cue-{index}.wav"), "wb") as recording:
            recording.setnchannels(1)
            recording.setsampwidth(2)
            recording.setframerate(8000)
            recording.writeframes(struct.pack("<h", index + 1) * 800)
