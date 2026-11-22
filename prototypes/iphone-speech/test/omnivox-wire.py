#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run the first phone protocol checks against a disposable stdio worker."""
import argparse
import asyncio
import base64
import json
import os
from pathlib import Path


async def check(command, icon):
    proc = await asyncio.create_subprocess_exec(
        *command, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL, limit=512 * 1024,
        env={**os.environ, "OMNIVOX_LOG_SYNTHESIS_TEXT": "0"})

    async def send(*lines):
        proc.stdin.write(("\n".join(lines) + "\n").encode())
        await proc.stdin.drain()

    async def reply():
        line = await asyncio.wait_for(proc.stdout.readline(), 15)
        if not line:
            raise RuntimeError("Worker closed its response stream")
        return line.rstrip(b"\r\n")

    async def control(kind, number, response_type=None, **fields):
        request = {"protocol_version": 1, "request_id": number, "type": kind, **fields}
        payload = base64.b64encode(json.dumps(request).encode()).decode()
        await send("omnivox_control {" + payload + "}")
        prefix, _, data = (await reply()).partition(b" ")
        if prefix != b"__OMNIVOX_CONTROL__":
            raise RuntimeError(f"Expected a control response to {kind}")
        result = json.loads(base64.b64decode(data, validate=True))
        if (result["type"], result["request_id"], result["protocol_version"]) != (response_type or kind, number, 1):
            raise RuntimeError(f"Incorrect response to {kind}, request {number}")
        return result

    async def dispatch(number, expected, *records):
        await send(*records, f"emacsvox_tracked_dispatch {number}")
        if await reply() != f"__EMACSVOX_TRACKED__ {number} {expected}".encode():
            raise RuntimeError(f"Dispatch {number} did not report {expected}")

    try:
        capabilities = await control("capabilities", 1)
        required = {"engine_inventory", "tracked_playback_completion"}
        if missing := required.difference(capabilities["features"]):
            raise RuntimeError("Missing capabilities: " + ", ".join(sorted(missing)))
        inventory = await control("inventory", 2)
        voices = [(engine["id"], voice["id"]) for engine in inventory["engines"] for voice in engine["voices"]]
        if not voices or any(identity["engine_id"] != engine or not identity["voice_id"] for engine, identity in voices):
            raise RuntimeError("Inventory did not supply usable physical voice IDs")
        if "exact_voice_preview" in capabilities["features"]:
            preferred = inventory["preferred_engine_id"]
            available = [voice for engine in inventory["engines"] if engine["id"] == preferred
                         for voice in engine["voices"] if voice["availability"]["status"] == "available"]
            if not available:
                raise RuntimeError("No available voice to preview on the preferred engine")
            voice = next((v for v in available if (v.get("language") or "").startswith("en")), available[0])
            identity = voice["id"]
            sample = await control("preview", 3, "preview_completed", selector={"kind": "exact", **identity},
                                   text="Sample", acss={"average_pitch": 0.6})
            if sample.get("realized") != identity or sample.get("status") != "completed":
                raise RuntimeError("Exact preview did not complete on the selected voice")
            print("Exact voice preview completed on the requested physical ID.")
        bad = "a {" + icon + ".missing.ogg}"
        await dispatch(10, "completed", "t 660 40", "a {" + icon + "}", "sh 10", "q {Sample}")
        # Immediate play leaves the missing queued icon for dispatch to report.
        await dispatch(11, "failed", bad, "p {" + icon + "}")
        await dispatch(12, "completed", bad, "s")
        await dispatch(13, "completed", "q {Fresh}", "t 440 12")
        await send("tts_exit")
        if await asyncio.wait_for(proc.wait(), 5) != 0:
            raise RuntimeError("Worker did not exit cleanly")
        print(f"Passed negotiation and inventory with {len(voices)} voice IDs.")
        print("Passed tone and icon dispatch, immediate play retaining the batch, Stop and fresh speech.")
    finally:
        if proc.returncode is None:
            proc.kill()
            await proc.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    bundled = Path(__file__).resolve().parents[3] / "sounds/packs/accent/open-object.ogg"
    parser.add_argument("--icon", default=str(bundled), help="recording path or resource ID accepted by this worker")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="disposable worker command with its arguments")
    args = parser.parse_args()
    argv = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not argv or "\n" in args.icon or "\r" in args.icon:
        parser.error("supply a worker command and a single-line icon path")
    try:
        asyncio.run(check(argv, args.icon))
    except TimeoutError:
        raise SystemExit("Timed out waiting for the worker")
