#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 RELEASE_DIR OMNIVOX_DIR ARCHIVE ARCHIVE_SHA256" >&2
    exit 2
fi

release_dir=$1
omnivox_dir=$2
source_archive=$3
expected_archive_sha256=$4

for command_name in git python3 sha256sum unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required Piper development staging tool is missing: $command_name" >&2
        exit 1
    fi
done

case "$expected_archive_sha256" in
    *[!0-9a-f]* | '')
        echo "Piper development archive SHA-256 must be lowercase hexadecimal" >&2
        exit 1
        ;;
esac
if [ "${#expected_archive_sha256}" -ne 64 ]; then
    echo "Piper development archive SHA-256 must contain 64 characters" >&2
    exit 1
fi
if [ ! -f "$source_archive" ]; then
    echo "Piper development archive is not readable: $source_archive" >&2
    exit 1
fi

if ! git -C "$omnivox_dir" diff --quiet --ignore-submodules -- ||
   ! git -C "$omnivox_dir" diff --cached --quiet --ignore-submodules -- ||
   [ -n "$(git -C "$omnivox_dir" status --porcelain --untracked-files=normal)" ]; then
    echo "The Omnivox checkout must be clean before using a native CI companion" >&2
    echo "Commit and push Omnivox, then build a new native Piper artifact." >&2
    exit 1
fi

actual_archive_sha256=$(sha256sum "$source_archive" | cut -d ' ' -f1)
if [ "$actual_archive_sha256" != "$expected_archive_sha256" ]; then
    echo "Piper development archive checksum does not match" >&2
    exit 1
fi

omnivox_commit=$(git -C "$omnivox_dir" rev-parse HEAD)
cache_dir=$release_dir/cache/piper-development
archive=$cache_dir/artifact-$expected_archive_sha256.zip
destination=$cache_dir/companion-$expected_archive_sha256
mkdir -p "$cache_dir"

if [ ! -f "$archive" ]; then
    temporary_archive=$(mktemp "$cache_dir/.piper-development-archive.XXXXXX")
    trap 'rm -f -- "$temporary_archive"' 0 1 2 15
    cp "$source_archive" "$temporary_archive"
    mv "$temporary_archive" "$archive"
    trap - 0 1 2 15
fi
if [ "$(sha256sum "$archive" | cut -d ' ' -f1)" != \
     "$expected_archive_sha256" ]; then
    echo "Existing content-addressed Piper archive differs: $archive" >&2
    exit 1
fi

validate_companion()
{
    companion=$1
    for required in omnivox-piper-helper.exe piper.dll onnxruntime.dll \
        onnxruntime_providers_shared.dll SOURCE-PROVENANCE.json SHA256SUMS \
        espeak-ng-data/phontab; do
        if [ ! -f "$companion/$required" ]; then
            echo "Piper development companion file is missing: $required" >&2
            return 1
        fi
    done
    if find "$companion" -type l -print -quit | grep -q .; then
        echo "Piper development companion contains a symbolic link" >&2
        return 1
    fi
    if ! python3 - "$companion/SOURCE-PROVENANCE.json" \
        "$omnivox_commit" <<'PY'
import json
import pathlib
import sys

provenance_path = pathlib.Path(sys.argv[1])
expected_commit = sys.argv[2]
with provenance_path.open(encoding="utf-8") as stream:
    provenance = json.load(stream)

expected = {
    "artifact": "omnivox-piper-companion-windows-x64",
    "target": "x86_64-pc-windows-msvc",
    "voice_model_included": False,
}
for key, value in expected.items():
    if provenance.get(key) != value:
        raise SystemExit(f"Piper provenance has unexpected {key}: {provenance.get(key)!r}")

omnivox = provenance.get("omnivox")
if not isinstance(omnivox, dict):
    raise SystemExit("Piper provenance has no Omnivox source record")
if omnivox.get("commit") != expected_commit:
    raise SystemExit(
        "Piper provenance commit does not match the Omnivox checkout: "
        f"{omnivox.get('commit')!r} != {expected_commit!r}"
    )
if omnivox.get("tracked_worktree_dirty") is not False:
    raise SystemExit("Piper provenance does not identify a clean CI source tree")
PY
    then
        return 1
    fi
    (cd "$companion" && sha256sum --check SHA256SUMS >/dev/null)
}

if [ ! -d "$destination/piper" ] || \
   ! validate_companion "$destination/piper"; then
    temporary_directory=$(mktemp -d "$cache_dir/.piper-development.XXXXXX")
    trap 'rm -rf -- "$temporary_directory"' 0 1 2 15
    unzip -Z1 "$archive" | while IFS= read -r member; do
        case "$member" in
            piper | piper/ | piper/*) ;;
            *)
                echo "Unsafe Piper development archive member: $member" >&2
                exit 1
                ;;
        esac
        case "/$member/" in
            *'/../'* | *'/./'* | *\\*)
                echo "Unsafe Piper development archive member: $member" >&2
                exit 1
                ;;
        esac
    done
    unzip -q "$archive" -d "$temporary_directory"
    validate_companion "$temporary_directory/piper"
    if [ -e "$destination" ]; then
        echo "Refusing to replace invalid Piper development cache: $destination" >&2
        exit 1
    fi
    mv "$temporary_directory" "$destination"
    trap - 0 1 2 15
fi

printf '%s\n' "$destination/piper"
