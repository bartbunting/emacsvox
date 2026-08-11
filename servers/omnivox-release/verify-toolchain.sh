#!/bin/sh
set -eu

release_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=toolchain.lock
. "$release_dir/toolchain.lock"

image=${OMNIVOX_RELEASE_IMAGE:-emacsvox-omnivox-windows-gnu:rust-1.97.1}

for command_name in docker powershell.exe sha256sum wslpath; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required Omnivox release tool is missing: $command_name" >&2
        exit 1
    fi
done

"$release_dir/prepare-dotnet-toolchain.sh" >/dev/null

docker build --platform linux/amd64 --provenance=false --tag "$image" \
    "$release_dir"

actual_rust=$(
    docker run --rm --platform linux/amd64 "$image" rustc --version |
        awk '{print $2}'
)
actual_gcc=$(
    docker run --rm --platform linux/amd64 "$image" \
        x86_64-w64-mingw32-gcc-win32 -dumpfullversion
)
actual_gcc_package=$(
    docker run --rm --platform linux/amd64 "$image" \
        dpkg-query -W -f='${Version}' gcc-mingw-w64-x86-64-win32
)
actual_binutils_package=$(
    docker run --rm --platform linux/amd64 "$image" \
        dpkg-query -W -f='${Version}' binutils-mingw-w64-x86-64
)
actual_libclang_package=$(
    docker run --rm --platform linux/amd64 "$image" \
        dpkg-query -W -f='${Version}' libclang-dev
)
if [ "$actual_rust" != "$rustc_release" ]; then
    echo "Pinned image has Rust $actual_rust; expected $rustc_release" >&2
    exit 1
fi
if [ "$actual_gcc" != "$mingw_gcc_release" ]; then
    echo "Pinned image has MinGW GCC $actual_gcc; expected $mingw_gcc_release" >&2
    exit 1
fi
if [ "$actual_gcc_package" != "$mingw_gcc_package" ]; then
    echo "Pinned image has MinGW package $actual_gcc_package; expected $mingw_gcc_package" >&2
    exit 1
fi
if [ "$actual_binutils_package" != "$mingw_binutils_package" ]; then
    echo "Pinned image has MinGW binutils $actual_binutils_package; expected $mingw_binutils_package" >&2
    exit 1
fi
if [ "$actual_libclang_package" != "$libclang_package" ]; then
    echo "Pinned image has libclang $actual_libclang_package; expected $libclang_package" >&2
    exit 1
fi

roslyn_compiler=$release_dir/cache/roslyn-$roslyn_version/tasks/net472/csc.exe
actual_csc_sha=$(sha256sum "$roslyn_compiler" | cut -d ' ' -f1)
if [ "$actual_csc_sha" != "$roslyn_csc_sha256" ]; then
    echo "Roslyn compiler hash does not match toolchain.lock" >&2
    exit 1
fi
windows_compiler=$(wslpath -m "$roslyn_compiler")
actual_csc_version=$(
    powershell.exe -NoProfile -NonInteractive -Command \
        "& '$windows_compiler' /version" |
        tr -d '\r'
)
case "$actual_csc_version" in
    "$roslyn_version"-*) ;;
    *)
        echo "Roslyn reports $actual_csc_version; expected $roslyn_version" >&2
        exit 1
        ;;
esac
framework_release=$(
    powershell.exe -NoProfile -NonInteractive -Command \
        '(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release' |
        tr -d '\r'
)
if [ "$framework_release" -lt 461808 ]; then
    echo ".NET Framework 4.7.2 or newer is required to run Roslyn" >&2
    exit 1
fi

image_id=$(docker image inspect --format '{{.Id}}' "$image")
printf '%s\n' \
    "release_contract=$release_contract_version" \
    "release_image=$image" \
    "release_image_id=$image_id" \
    "rustc=$actual_rust" \
    "mingw_gcc=$actual_gcc" \
    "mingw_gcc_package=$actual_gcc_package" \
    "mingw_binutils_package=$actual_binutils_package" \
    "libclang_package=$actual_libclang_package" \
    "roslyn_csc=$actual_csc_version" \
    "roslyn_csc_sha256=$actual_csc_sha" \
    "dotnet_framework_release=$framework_release"
