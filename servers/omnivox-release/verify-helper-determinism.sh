#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 EMACSVOX_ROOT ROSLYN_CSC REFERENCE_DIRECTORY" >&2
    exit 2
fi

emacsvox_root=$1
compiler=$2
references=$3
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

build_helpers()
{
    make -C "$emacsvox_root/servers/windows-eloquence" \
        OMNIVOX_CSC="$compiler" OMNIVOX_REFERENCE_DIR="$references" \
        omnivox-helper >/dev/null
    make -C "$emacsvox_root/servers/windows-dectalk" \
        OMNIVOX_CSC="$compiler" OMNIVOX_REFERENCE_DIR="$references" \
        omnivox-helper >/dev/null
}

build_helpers
cp "$emacsvox_root/servers/windows-eloquence/bin/OmnivoxEloquenceHelper32.exe" \
    "$temporary/OmnivoxEloquenceHelper32.exe"
cp "$emacsvox_root/servers/windows-dectalk/bin/OmnivoxDectalkHelper32.exe" \
    "$temporary/OmnivoxDectalkHelper32.exe"

build_helpers
cmp "$temporary/OmnivoxEloquenceHelper32.exe" \
    "$emacsvox_root/servers/windows-eloquence/bin/OmnivoxEloquenceHelper32.exe"
cmp "$temporary/OmnivoxDectalkHelper32.exe" \
    "$emacsvox_root/servers/windows-dectalk/bin/OmnivoxDectalkHelper32.exe"

sha256sum \
    "$emacsvox_root/servers/windows-eloquence/bin/OmnivoxEloquenceHelper32.exe" \
    "$emacsvox_root/servers/windows-dectalk/bin/OmnivoxDectalkHelper32.exe"
