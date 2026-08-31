#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 RELEASE_DIR OMNIVOX_DIR" >&2
    exit 2
fi

release_dir=$1
omnivox_dir=$2
# shellcheck source=toolchain.lock
. "$release_dir/toolchain.lock"

for command_name in curl git sha256sum unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required Piper staging tool is missing: $command_name" >&2
        exit 1
    fi
done

actual_commit=$(git -C "$omnivox_dir" rev-parse HEAD)
if [ "$actual_commit" != "$omnivox_piper_commit" ]; then
    echo "Omnivox is at $actual_commit, but the pinned Piper companion was built from $omnivox_piper_commit" >&2
    echo "Use the matching Omnivox release checkout or update the reviewed Piper lock." >&2
    exit 1
fi

cache_dir=$release_dir/cache/piper-$omnivox_piper_version
archive=$cache_dir/$omnivox_piper_archive
destination=$cache_dir/companion-$omnivox_piper_archive_sha256
mkdir -p "$cache_dir"

archive_is_current=false
if [ -f "$archive" ]; then
    actual_archive_sha256=$(sha256sum "$archive" | cut -d ' ' -f1)
    if [ "$actual_archive_sha256" = "$omnivox_piper_archive_sha256" ]; then
        archive_is_current=true
    fi
fi

if ! $archive_is_current; then
    temporary_archive=$(mktemp "$cache_dir/.piper-archive.XXXXXX")
    trap 'rm -f -- "$temporary_archive"' 0 1 2 15
    curl --fail --location --retry 3 \
        --output "$temporary_archive" "$omnivox_piper_archive_url"
    actual_archive_sha256=$(sha256sum "$temporary_archive" | cut -d ' ' -f1)
    if [ "$actual_archive_sha256" != "$omnivox_piper_archive_sha256" ]; then
        echo "Downloaded Piper companion checksum does not match toolchain.lock" >&2
        exit 1
    fi
    mv -f "$temporary_archive" "$archive"
    trap - 0 1 2 15
fi

validate_companion() {
    companion=$1
    for required in omnivox-piper-helper.exe piper.dll onnxruntime.dll \
        onnxruntime_providers_shared.dll SOURCE-PROVENANCE.json SHA256SUMS \
        espeak-ng-data/phontab; do
        if [ ! -f "$companion/$required" ]; then
            echo "Piper companion file is missing: $required" >&2
            return 1
        fi
    done
    if ! grep -Fq \
        '"artifact": "omnivox-piper-companion-windows-x64"' \
        "$companion/SOURCE-PROVENANCE.json" || \
       ! grep -Fq '"target": "x86_64-pc-windows-msvc"' \
        "$companion/SOURCE-PROVENANCE.json" || \
       ! grep -Fq "\"commit\": \"$omnivox_piper_commit\"" \
        "$companion/SOURCE-PROVENANCE.json"; then
        echo "Piper companion provenance does not match toolchain.lock" >&2
        return 1
    fi
    (cd "$companion" && sha256sum --check SHA256SUMS >/dev/null)
}

if [ ! -d "$destination/piper" ] || \
   ! validate_companion "$destination/piper"; then
    temporary_directory=$(mktemp -d "$cache_dir/.piper-extract.XXXXXX")
    trap 'rm -rf -- "$temporary_directory"' 0 1 2 15
    unzip -Z1 "$archive" | while IFS= read -r member; do
        case "$member" in
            piper | piper/ | piper/*) ;;
            *)
                echo "Unsafe Piper archive member: $member" >&2
                exit 1
                ;;
        esac
        case "/$member/" in
            *'/../'* | *'/./'* | *'\'* )
                echo "Unsafe Piper archive member: $member" >&2
                exit 1
                ;;
        esac
    done
    unzip -q "$archive" -d "$temporary_directory"
    validate_companion "$temporary_directory/piper"
    if [ -e "$destination" ]; then
        echo "Refusing to replace invalid Piper cache directory: $destination" >&2
        exit 1
    fi
    mv "$temporary_directory" "$destination"
    trap - 0 1 2 15
fi

printf '%s\n' "$destination/piper"
