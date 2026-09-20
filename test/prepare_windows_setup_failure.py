#!/usr/bin/env python3
"""Stage an intentionally failing installer solely for rollback acceptance."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import importlib.util
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('setup', ROOT / 'utils/emacsvox-windows-setup.py')
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--staging-directory', type=Path, required=True)
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='emacsvox-failed-setup-') as temporary:
        root = Path(temporary)
        for name in SETUP.INPUTS:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        template = root / 'utils/emacsvox-windows-setup.iss'
        original = template.read_text()
        trigger = "  Error := RunHelper('Configure',"
        if original.count(trigger) != 1:
            raise ValueError('Setup configuration hook changed; update the failure fixture')
        template.write_text(original.replace(trigger,
            "  RaiseException('Intentional configuration failure for rollback acceptance');\n" + trigger))
        print(SETUP.prepare(arguments.bundle.resolve(), arguments.staging_directory.resolve(), root=root))


if __name__ == '__main__':
    main()
