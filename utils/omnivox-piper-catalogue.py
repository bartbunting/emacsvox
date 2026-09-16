#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare, review and validate pinned Piper catalogue entries (maintainer tool).

This tool never changes a user's installed voice library. Omnivox still owns
end-user download, installation and activation. Work files and models stay in
--work; export emits only reviewed, natively validated catalogue metadata.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import uuid

REPOSITORY = "https://huggingface.co/rhasspy/piper-voices"
API = "https://huggingface.co/api/models/rhasspy/piper-voices/revision/"
ROLES = {"model": "model.onnx", "config": "model.onnx.json", "model_card": "MODEL_CARD"}
MAX_SPEAKERS = 256  # Current Omnivox runtime projection limit; never truncate a voice set.


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write("\n")
        temporary = Path(f.name)
    os.replace(temporary, path)


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read(32 * 1024 * 1024 + 1)
    if len(data) > 32 * 1024 * 1024:
        raise ValueError("Upstream metadata exceeds 32 MiB")
    return json.loads(data)


def build_records(index, repository):
    revision = repository["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("An immutable upstream commit is required")
    blobs = {v["rfilename"]: v for v in repository["siblings"]}
    records, identities = [], set()
    for key, voice in sorted(index.items()):
        locale, name, quality = voice["language"]["code"], voice["name"], voice["quality"]
        if key != f"{locale}-{name}-{quality}" or not all(c.isalnum() or c in "_-" for c in key):
            raise ValueError(f"Invalid upstream voice key: {key}")
        count = voice["num_speakers"]
        if type(count) is not int or not 1 <= count <= 10000:
            raise ValueError(f"Invalid speaker count: {key}")
        identity = "piper-" + "".join(
            c.lower() if c.isascii() and c.isalnum() else "-" if c in "_-"
            else f"-u{ord(c):04x}-" for c in key)
        if identity in identities:
            raise ValueError(f"Catalogue identity collision: {identity}")
        identities.add(identity)
        names = voice.get("speaker_id_map", {})
        if names and (any(type(i) is not int for i in names.values())
                      or sorted(names.values()) != list(range(count))):
            raise ValueError(f"Incomplete or duplicate speaker indices: {key}")
        speakers = {i: n for n, i in names.items()}
        files, upstream = [], {}
        expected = {"model": key + ".onnx", "config": key + ".onnx.json", "model_card": "MODEL_CARD"}
        directories = set()
        for role, filename in expected.items():
            paths = [p for p in voice["files"] if PurePosixPath(p).name == filename]
            if len(paths) != 1:
                raise ValueError(f"Missing or ambiguous {role}: {key}")
            path = paths[0]
            parts = PurePosixPath(path)
            if parts.is_absolute() or ".." in parts.parts or str(parts) != path or "\\" in path:
                raise ValueError(f"Unsafe upstream path: {path}")
            directories.add(str(parts.parent))
            blob = blobs[path]
            size = blob["size"]
            if type(size) is not int or not 0 < size <= 2 * 1024**3 or size != voice["files"][path]["size_bytes"]:
                raise ValueError(f"Inconsistent upstream size: {path}")
            sha = blob.get("lfs", {}).get("sha256", "")
            if sha and not re.fullmatch(r"[a-f0-9]{64}", sha):
                raise ValueError(f"Invalid upstream digest: {path}")
            files.append({"role": role, "url": f"{REPOSITORY}/resolve/{revision}/{urllib.parse.quote(path)}",
                          "bytes": size, "sha256": sha})
            upstream[role] = {"path": path, "blob_id": blob["blobId"], "lfs_sha256": sha}
        if len(directories) != 1:
            raise ValueError(f"Model and metadata directories disagree: {key}")
        entry = {"id": identity, "provider": "piper", "name": f"{name.replace('_', ' ')} {quality}",
                 "language": locale.replace("_", "-"),
                 "description": f"{voice['language']['name_english']}; {quality} quality; {count} speaker(s).",
                 "source": REPOSITORY, "source_revision": revision,
                 "licence": "Pending model-card review", "licence_url": files[2]["url"],
                 "files": files,
                 "voices": [{"physical_id": f"piper:v1/c/{identity}/{i}",
                             "name": name if count == 1 else f"{name}: {speakers.get(i, str(i))}",
                             "speaker_index": i} for i in range(count)]}
        records.append({"upstream_key": key, "voice_name": name, "quality": quality,
                        "upstream_speaker_id_map": names,
                        "language_name": voice["language"]["name_english"], "entry": entry,
                        "upstream_files": upstream, "verified": {}, "review": {"status": "pending"},
                        "validation": {"status": "pending"},
                        "blocked": f"{count} speakers exceeds native limit {MAX_SPEAKERS}" if count > MAX_SPEAKERS else None})
    return {"schema_version": 1, "source": REPOSITORY, "source_revision": revision,
            "index_sha256": digest(index), "records": records}


def discover(work, revision):
    repo = fetch_json(API + urllib.parse.quote(revision, safe="") + "?blobs=true")
    index = fetch_json(f"{REPOSITORY}/resolve/{repo['sha']}/voices.json")
    document = build_records(index, repo)
    # Re-running the exact same discovery preserves completed work.
    path = work / "review.json"
    if path.exists():
        previous = read(path)
        if (previous["source_revision"], previous["index_sha256"]) == (document["source_revision"], document["index_sha256"]):
            return previous
        raise ValueError("Work directory contains a different revision; use a new --work directory")
    write(work / "upstream-index.json", index)
    write(work / "upstream-repository.json", repo)
    write(path, document)
    return document


def asset_path(work, record, role):
    identity = record["entry"]["id"]
    if not re.fullmatch(r"piper-[a-z0-9-]+", identity):
        raise ValueError("Invalid local catalogue identity")
    return work / "assets" / identity / ROLES[role]


def verify_file(path, asset, upstream):
    sha, git = hashlib.sha256(), hashlib.sha1()
    git.update(f"blob {asset['bytes']}\0".encode())
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            size += len(chunk)
            if size > asset["bytes"]:
                raise ValueError("Asset exceeds pinned size")
            sha.update(chunk)
            git.update(chunk)
    result = sha.hexdigest()
    expected = upstream["lfs_sha256"]
    if size != asset["bytes"] or (expected and result != expected):
        raise ValueError("Asset size or SHA-256 differs from pinned upstream metadata")
    if not expected and git.hexdigest() != upstream["blob_id"]:
        raise ValueError("Asset differs from pinned Git blob")
    return result


def download(work, record, role):
    asset = next(f for f in record["entry"]["files"] if f["role"] == role)
    path = asset_path(work, record, role)
    upstream = record["upstream_files"][role]
    prefix = f"{REPOSITORY}/resolve/{record['entry']['source_revision']}/"
    if not asset["url"].startswith(prefix):
        raise ValueError("Asset URL is outside the pinned repository")
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".part")
        try:
            with urllib.request.urlopen(asset["url"], timeout=30) as response, temporary.open("wb") as stream:
                size = 0
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > asset["bytes"]:
                        raise ValueError("Download exceeds pinned size")
                    stream.write(chunk)
            verify_file(temporary, asset, upstream)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
    sha = verify_file(path, asset, upstream)
    asset["sha256"] = sha
    record["verified"][role] = sha
    return path


def metadata(work, record):
    for role in ("config", "model_card"):
        download(work, record, role)
    config = read(asset_path(work, record, "config"))
    if config.get("num_speakers") != len(record["entry"]["voices"]):
        raise ValueError("Config speaker count differs from index")
    mapping = config.get("speaker_id_map", {})
    if mapping and sorted(mapping.values()) != list(range(config["num_speakers"])):
        raise ValueError("Config speaker indices are incomplete")
    if mapping != record.get("upstream_speaker_id_map", mapping):
        raise ValueError("Config speaker names differ from index")
    record["sample_rate"] = config.get("audio", {}).get("sample_rate")
    record["phoneme_type"] = config.get("phoneme_type", "espeak")


def review(record, note, reviewer):
    if not all(record["verified"].get(role) for role in ("config", "model_card")):
        raise ValueError("Fetch and read model-card metadata before review")
    if not note.strip() or not reviewer.strip():
        raise ValueError("Review requires an attribution and terms summary")
    record["entry"]["licence"] = note.strip()
    record["review"] = {"status": "approved", "reviewer": reviewer, "note": note,
                        "entry_sha256": digest(record["entry"])}


def validation_ready(record):
    entry = record["entry"]
    return (not record["blocked"] and record["review"].get("status") == "approved"
            and record["review"].get("entry_sha256") == digest(entry)
            and all(record["verified"].get(f["role"]) == f["sha256"] and f["sha256"] for f in entry["files"]))


def native_validate(work, record, server, helper, timeout, memory):
    if record["blocked"]:
        raise ValueError(record["blocked"])
    if record["review"].get("entry_sha256") != digest(record["entry"]):
        raise ValueError("Entry requires current model-card review")
    download(work, record, "model")
    if not validation_ready(record):
        raise ValueError("Reviewed entry or verified files changed")
    # Paths in generations are native paths. WSL callers can select a Windows server.
    def native(path):
        if server.suffix.lower() == ".exe" and os.name != "nt":
            return subprocess.check_output(["wslpath", "-w", str(path.resolve())], text=True).strip()
        return str(path.resolve())
    entry = record["entry"]
    assets = {f["role"]: {"path": native(asset_path(work, record, f["role"])),
                         "bytes": f["bytes"], "sha256": f["sha256"]} for f in entry["files"]}
    generation = {"schema_version": 1, "target_id": str(uuid.uuid4()), "profile_id": str(uuid.uuid4()),
                  "generation_id": str(uuid.uuid4()), "disabled_physical_ids": [], "flite": None,
                  "piper": {"models": [{"identity": {"catalogue_key": entry["id"]},
                      "model": assets["model"], "config": assets["config"],
                      "voices": [{"physical_id": v["physical_id"], "speaker_index": v["speaker_index"],
                                  "display_name": v["name"], "language": entry["language"]} for v in entry["voices"]]}]}}
    run = work / "validation" / entry["id"] / str(uuid.uuid4())
    write(run / "generation.json", generation)
    report = run / "evidence.json"
    environment = {k: v for k, v in os.environ.items() if not k.startswith("OMNIVOX_")}
    environment["OMNIVOX_AUDIO_OUTPUT"] = "null"
    command = [str(server), "--validate-voice-library", native(run / "generation.json"),
               "--piper-helper", native(helper), "--validation-report", native(report),
               "--validation-timeout-seconds", str(timeout), "--validation-memory-mib", str(memory)]
    with (run / "output.log").open("wb") as log:
        with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=log, stderr=log, env=environment) as process:
            try:
                result = process.wait(timeout=timeout + 90)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                # EOF lets Omnivox's supervisor retire its children and confirm cleanup.
                process.stdin.close()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                raise
    if result != 0:
        raise ValueError(f"Native validation failed; see {run / 'output.log'}")
    evidence = read(report)
    snapshot = evidence["snapshot"]
    if (evidence.get("kind") != "native-validation-observation" or not evidence.get("cleanup_confirmed")
            or snapshot["generation_sha256"] != hashlib.sha256((run / "generation.json").read_bytes()).hexdigest()):
        raise ValueError("Native evidence does not match this generation and cleanup")
    record["validation"] = {"status": "passed", "entry_sha256": digest(entry),
                            "platform": snapshot["os"], "arch": snapshot["arch"],
                            "validator_sha256": snapshot["validator"]["sha256"],
                            "evidence": str(report.relative_to(work)),
                            "evidence_sha256": hashlib.sha256(report.read_bytes()).hexdigest()}


def approved(work, record):
    validation = record["validation"]
    if not validation_ready(record) or validation.get("status") != "passed" or validation.get("entry_sha256") != digest(record["entry"]):
        return False
    path = (work / validation["evidence"]).resolve()
    if not path.is_relative_to(work.resolve()) or not path.is_file():
        return False
    return hashlib.sha256(path.read_bytes()).hexdigest() == validation["evidence_sha256"]


def export(work, document, destination):
    groups = {}
    for record in document["records"]:
        if approved(work, record):
            groups.setdefault(record["entry"]["language"], []).append(record["entry"])
    if not groups:
        raise ValueError("No entries have current review, verified files and native validation")
    files, models = [], {}
    def publish(language, entries):
        catalogue = {"schema_version": 1, "revision": document["source_revision"], "entries": entries}
        name = f"piper-{language}-{hashlib.sha256(encoded(catalogue)).hexdigest()[:16]}.json"
        write(destination / name, catalogue)
        files.append(name)
    for language, entries in sorted(groups.items()):
        batch = []
        for entry in entries:
            candidate = {"schema_version": 1, "revision": document["source_revision"], "entries": batch + [entry]}
            if len(batch) == 128 or len(encoded(candidate)) > 1024 * 1024:
                if batch:
                    publish(language, batch)
                batch = []
            candidate["entries"] = batch + [entry]
            if len(encoded(candidate)) > 1024 * 1024:
                raise ValueError("One entry exceeds native byte limit")
            batch.append(entry)
        if batch:
            publish(language, batch)
    for record in document["records"]:
        if approved(work, record):
            models[record["entry"]["id"]] = {key: record[key] for key in ("voice_name", "quality", "language_name")}
    report = {"source": document["source"], "source_revision": document["source_revision"],
              "index_sha256": document["index_sha256"], "records": [
                  {"id": r["entry"]["id"], "model_card": r["entry"]["files"][2],
                   "review": r["review"], "blocked": r["blocked"],
                   "error": r["error"].split("; see ")[0] if r.get("error") else None,
                   "exported": approved(work, r),
                   "validation": {k: v for k, v in r["validation"].items() if k != "evidence"}}
                  for r in document["records"]]}
    write(destination / "review-report.json", report)
    write(destination / "manifest.json", {"schema_version": 1, "catalogues": files, "models": models})
    return sum(len(v) for v in groups.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("discover", "metadata", "review", "validate", "export", "status"))
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--revision", default="main")
    parser.add_argument("--id", action="append", default=[])
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--note")
    parser.add_argument("--reviewer")
    parser.add_argument("--server", type=Path)
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--memory-mib", type=int, default=2048)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    if not 1 <= args.jobs <= 8:
        parser.error("--jobs must be between 1 and 8")
    if args.command == "discover":
        document = discover(work, args.revision)
    else:
        document = read(work / "review.json")
    records = [r for r in document["records"] if not args.id or r["entry"]["id"] in args.id]
    if set(args.id) - {r["entry"]["id"] for r in records}:
        parser.error("Unknown catalogue ID")
    if args.command in ("metadata", "validate"):
        if args.command == "validate" and (not args.server or not args.helper):
            parser.error("--server and --helper are required")
        if args.command == "validate" and not args.id:
            records = [r for r in records if not r["blocked"]
                       and r["review"].get("entry_sha256") == digest(r["entry"])
                       and not approved(work, r)]
        failed = False
        def task(record):
            record = copy.deepcopy(record)
            try:
                if args.command == "metadata":
                    metadata(work, record)
                else:
                    record["validation"] = {"status": "pending"}
                    native_validate(work, record, args.server.resolve(), args.helper.resolve(), args.timeout, args.memory_mib)
                record.pop("error", None)
            except Exception as error:
                record["error"] = str(error)
                if args.command == "validate":
                    record["validation"] = {"status": "failed"}
            return record
        positions = {r["entry"]["id"]: i for i, r in enumerate(document["records"])}
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(task, r) for r in records]
            for future in as_completed(futures):
                record = future.result()
                failed |= bool(record.get("error"))
                document["records"][positions[record["entry"]["id"]]] = record
                write(work / "review.json", document)
                print(record["entry"]["id"], record.get("error", "ready"), flush=True)
    elif args.command == "review":
        if not args.id or not args.note or not args.reviewer:
            parser.error("Review requires explicit --id, --note and --reviewer")
        for record in records:
            review(record, args.note, args.reviewer)
        write(work / "review.json", document)
    elif args.command == "export":
        if not args.output:
            parser.error("--output is required")
        print(f"Exported {export(work, document, args.output)} validated entries")
    print(json.dumps({"revision": document["source_revision"], "models": len(document["records"]),
                      "reviewed": sum(r["review"]["status"] == "approved" for r in document["records"]),
                      "validated": sum(approved(work, r) for r in document["records"]),
                      "blocked": sum(bool(r["blocked"]) for r in document["records"]),
                      "errors": sum(bool(r.get("error")) for r in document["records"])}))
    if args.command in ("metadata", "validate") and failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
