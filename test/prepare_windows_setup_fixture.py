#!/usr/bin/env python3
"""Clone a staged installer with a separate identity for native lifecycle tests."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import os
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
args = parser.parse_args()
args.destination.mkdir(parents=True, exist_ok=False)
for name in ('payload',):
    shutil.copytree(args.source / name, args.destination / name, copy_function=os.link)
for path in args.source.iterdir():
    if path.is_file():
        shutil.copyfile(path, args.destination / path.name)
script = args.destination / 'setup.iss'
text = script.read_text()
assert 'B2C8A798-1699-456B-8A64-A6D02C347972' in text
text = text.replace('B2C8A798-1699-456B-8A64-A6D02C347972', 'D78E9D1F-D616-4B21-9B4D-5D97CD825101')
text = text.replace('Emacsvox Windows', 'Emacsvox UI Fixture')
text = text.replace('OutputBaseFilename=emacsvox-', 'OutputBaseFilename=emacsvox-fixture-')
script.write_text(text)
print(script)
