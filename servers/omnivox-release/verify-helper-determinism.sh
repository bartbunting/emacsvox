#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 OMNIVOX_ROOT ROSLYN_CSC REFERENCE_DIRECTORY" >&2
    exit 2
fi

omnivox_root=$1
compiler=$2
references=$3
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

build_helpers()
{
    make -C "$omnivox_root" \
        OMNIVOX_CSC="$compiler" OMNIVOX_REFERENCE_DIR="$references" \
        windows-helpers >/dev/null
}

build_helpers
cp "$omnivox_root/windows-helpers/bin/OmnivoxEloquenceHelper32.exe" \
    "$temporary/OmnivoxEloquenceHelper32.exe"
cp "$omnivox_root/windows-helpers/bin/OmnivoxDectalkHelper32.exe" \
    "$temporary/OmnivoxDectalkHelper32.exe"

build_helpers
cmp "$temporary/OmnivoxEloquenceHelper32.exe" \
    "$omnivox_root/windows-helpers/bin/OmnivoxEloquenceHelper32.exe"
cmp "$temporary/OmnivoxDectalkHelper32.exe" \
    "$omnivox_root/windows-helpers/bin/OmnivoxDectalkHelper32.exe"

sha256sum \
    "$omnivox_root/windows-helpers/bin/OmnivoxEloquenceHelper32.exe" \
    "$omnivox_root/windows-helpers/bin/OmnivoxDectalkHelper32.exe"
