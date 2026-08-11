#!/bin/sh
set -eu

release_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=toolchain.lock
. "$release_dir/toolchain.lock"

cache_dir=$release_dir/cache
roslyn_archive=$cache_dir/microsoft.net.compilers.toolset.framework.$roslyn_version.nupkg
references_archive=$cache_dir/microsoft.netframework.referenceassemblies.net40.$reference_assemblies_version.nupkg
roslyn_dir=$cache_dir/roslyn-$roslyn_version
references_dir=$cache_dir/net40-reference-assemblies-$reference_assemblies_version

for command_name in curl sha256sum unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required .NET toolchain preparation tool is missing: $command_name" >&2
        exit 1
    fi
done

mkdir -p "$cache_dir"

fetch_package()
{
    package_url=$1
    expected_sha=$2
    archive=$3

    if [ -f "$archive" ]; then
        actual_sha=$(sha256sum "$archive" | cut -d ' ' -f1)
        if [ "$actual_sha" != "$expected_sha" ]; then
            echo "Cached package has the wrong checksum: $archive" >&2
            echo "Remove that cache file before retrying." >&2
            exit 1
        fi
        return
    fi

    temporary=$archive.new.$$
    trap 'rm -f -- "$temporary"' EXIT HUP INT TERM
    curl -L --fail --silent --show-error --output "$temporary" "$package_url"
    echo "$expected_sha  $temporary" | sha256sum --check -
    mv "$temporary" "$archive"
    trap - EXIT HUP INT TERM
}

extract_package()
{
    archive=$1
    destination=$2
    sentinel=$3

    if [ -f "$destination/$sentinel" ]; then
        return
    fi

    temporary=$(mktemp -d "$cache_dir/.extract.XXXXXX")
    trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
    unzip -q "$archive" -d "$temporary"
    if [ ! -f "$temporary/$sentinel" ]; then
        echo "Package did not contain its required file: $sentinel" >&2
        exit 1
    fi
    if [ -e "$destination" ]; then
        previous=$destination.incomplete.$$
        mv "$destination" "$previous"
        echo "Moved incomplete package cache to $previous" >&2
    fi
    mv "$temporary" "$destination"
    trap - EXIT HUP INT TERM
}

fetch_package "$roslyn_package_url" "$roslyn_nupkg_sha256" "$roslyn_archive"
fetch_package "$reference_assemblies_url" \
    "$reference_assemblies_nupkg_sha256" "$references_archive"
extract_package "$roslyn_archive" "$roslyn_dir" tasks/net472/csc.exe
extract_package "$references_archive" "$references_dir" \
    build/.NETFramework/v4.0/mscorlib.dll

directory_digest()
{
    directory=$1
    (
        cd "$directory"
        find . -type f -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
    )
}

actual_roslyn_directory_sha=$(directory_digest "$roslyn_dir")
if [ "$actual_roslyn_directory_sha" != "$roslyn_directory_sha256" ]; then
    echo "Extracted Roslyn package does not match toolchain.lock" >&2
    exit 1
fi
actual_references_directory_sha=$(directory_digest "$references_dir")
if [ "$actual_references_directory_sha" != \
     "$reference_assemblies_directory_sha256" ]; then
    echo "Extracted .NET reference package does not match toolchain.lock" >&2
    exit 1
fi

actual_csc_sha=$(sha256sum "$roslyn_dir/tasks/net472/csc.exe" | cut -d ' ' -f1)
if [ "$actual_csc_sha" != "$roslyn_csc_sha256" ]; then
    echo "Extracted Roslyn compiler does not match toolchain.lock" >&2
    exit 1
fi

for reference in mscorlib.dll System.dll System.Core.dll \
    System.Web.Extensions.dll; do
    if [ ! -f "$references_dir/build/.NETFramework/v4.0/$reference" ]; then
        echo "Pinned .NET reference assembly is missing: $reference" >&2
        exit 1
    fi
done

printf '%s\n' \
    "roslyn_compiler=$roslyn_dir/tasks/net472/csc.exe" \
    "reference_assemblies=$references_dir/build/.NETFramework/v4.0"
