#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Observe legacy protocol fragments with an explicitly selected, muted Omnivox.

Usage: python3 test/diagnose-queue-fragments.py /path/to/omnivox
This characterizes the existing server; it does not test a client queue proof.
"""

import argparse
import base64
import json
import subprocess


CASES = (
    ("complete-stop", ("q {EARLIER}\n", "s\n"), False),
    ("partial-stop", ("q {EARLIER}\n", "q {", "s\n"), True),
    ("partial-reset", ("q {EARLIER}\n", "q {", "tts_reset\n"), True),
    ("partial-dispatch", ("q {EARLIER}\n", "q {", "d\n"), True),
    ("later-boundary-stop", ("q {EARLIER}\n", "q {", "s\n", "s\n"), False),
    ("complete-code-stop", ("q {EARLIER}\n", "c {opaque}\n", "s\n"), False),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server", help="Omnivox executable with eSpeak and null audio output")
    args = parser.parse_args()
    for name, chunks, expected_earlier in CASES:
        # The protocol sees a byte stream; OS write boundaries are immaterial.
        script = "".join(chunks) + "q {NEW}\nemacsvox_marker_dispatch 91\n"
        completed = subprocess.run(
            [args.server, "--engine", "espeak", "--audio-output", "null"],
            input=script,
            text=True,
            capture_output=True,
            timeout=30,
            check=True,
        )
        texts = []
        for line in completed.stdout.splitlines():
            if line.startswith("__EMACSVOX_MARKER__ "):
                event = json.loads(base64.b64decode(line.split(" ", 1)[1]))
                if event.get("dispatch_id") == 91 and event.get("type") == "utterance_started":
                    texts.append(event["text"])
        earlier = any("EARLIER" in text for text in texts)
        if (
            earlier != expected_earlier
            or "NEW" not in texts
            or "__EMACSVOX_TRACKED__ 91 completed" not in completed.stdout
        ):
            raise RuntimeError(f"Unexpected {name} observation: {texts!r}; {completed.stderr[-1000:]}")
        print(json.dumps({"case": name, "earlier_survives": earlier, "started_texts": texts}), flush=True)
    print("Six muted fragment observations match the characterized server behavior.")


if __name__ == "__main__":
    main()
