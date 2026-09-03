#!/bin/sh
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

if [ "$#" -ne 6 ]; then
    echo "usage: $0 EMACSVOX_DIR OMNIVOX_DIR RUNTIME_DIR RELEASE_DIR IMAGE TARGET" >&2
    exit 2
fi

emacsvox_dir=$1
omnivox_dir=$2
runtime_root=$3
release_root=$4
release_image=$5
target=$6

if [ "$target" != x86_64-pc-windows-gnu ]; then
    echo "Main-only staging currently supports x86_64-pc-windows-gnu" >&2
    exit 1
fi
if [ ! -L "$runtime_root/current" ]; then
    echo "No staged Omnivox development runtime is available to reuse" >&2
    echo "Run make windows-omnivox-dev once to create the complete base runtime" >&2
    exit 1
fi

base_runtime=$(readlink -f -- "$runtime_root/current")
versions_root=$(readlink -f -- "$runtime_root/versions")
case "$base_runtime/" in
    "$versions_root"/*/) ;;
    *)
        echo "Omnivox current does not resolve below $versions_root" >&2
        exit 1
        ;;
esac
for required in PROVENANCE SHA256SUMS omnivox.exe windows-runtime.path; do
    if [ ! -f "$base_runtime/$required" ]; then
        echo "Reusable Omnivox runtime is missing: $base_runtime/$required" >&2
        exit 1
    fi
done

provenance_value()
{
    field=$1
    sed -n "s/^$field=//p" "$base_runtime/PROVENANCE"
}

base_build_id=$(provenance_value build_id)
if [ -z "$base_build_id" ] || [ "$base_build_id" != "$(basename -- "$base_runtime")" ]; then
    echo "Reusable Omnivox runtime has inconsistent build identity" >&2
    exit 1
fi
if [ "$(provenance_value build_kind)" != local-dirty-worktree ]; then
    echo "Main-only staging requires a development runtime base" >&2
    echo "Run make windows-omnivox-dev to avoid deriving development state from a release" >&2
    exit 1
fi
if [ "$(provenance_value target)" != "$target" ] ||
   [ "$(provenance_value omnivox_features)" != none ] ||
   [ "$(provenance_value piper_companion)" != not-included ]; then
    echo "Reusable Omnivox runtime has incompatible target or feature settings" >&2
    echo "Run make windows-omnivox-dev to rebuild the complete development runtime" >&2
    exit 1
fi
reused_base_build_id=$(provenance_value incremental_base_build_id)
if [ -z "$reused_base_build_id" ]; then
    reused_base_build_id=$base_build_id
fi
reused_manifest_digest=$(provenance_value reused_payload_manifest_sha256)
if [ -z "$reused_manifest_digest" ]; then
    reused_manifest_digest=$(sha256sum "$base_runtime/SHA256SUMS" | cut -d ' ' -f1)
fi
complete_base_runtime=$versions_root/$reused_base_build_id
if [ ! -f "$complete_base_runtime/SHA256SUMS" ] ||
   [ "$(sha256sum "$complete_base_runtime/SHA256SUMS" | cut -d ' ' -f1)" != \
       "$reused_manifest_digest" ]; then
    echo "Original verified Omnivox development runtime is unavailable or changed" >&2
    echo "Run make windows-omnivox-dev to create a new complete base runtime" >&2
    exit 1
fi

base_omnivox_commit=$(provenance_value omnivox_commit)
if ! git -C "$omnivox_dir" cat-file -e "$base_omnivox_commit^{commit}" 2>/dev/null ||
   ! git -C "$omnivox_dir" merge-base --is-ancestor \
        "$base_omnivox_commit" HEAD; then
    echo "Reusable runtime is not an ancestor of the current Omnivox source" >&2
    echo "Run make windows-omnivox-dev to rebuild the complete development runtime" >&2
    exit 1
fi

temporary_root=$(mktemp -d "$versions_root/.main-dev.XXXXXX")
changed_paths=$temporary_root/changed-paths
stage_runtime=$temporary_root/runtime
windows_temporary_root=
cleanup()
{
    if [ -n "$windows_temporary_root" ]; then
        rm -rf -- "$windows_temporary_root"
    fi
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

{
    git -C "$omnivox_dir" diff --name-only "$base_omnivox_commit..HEAD"
    git -C "$omnivox_dir" diff --name-only HEAD
    git -C "$omnivox_dir" ls-files --others --exclude-standard
} | LC_ALL=C sort -u > "$changed_paths"

while IFS= read -r path; do
    case "$path" in
        '' | CHANGELOG.md | README.md | AGENTS.md | docs/* | omnivox-cli/* | \
            omnivox-audio/src/output.rs) ;;
        *)
            echo "Main-only staging cannot reuse companions after changing: $path" >&2
            echo "Run make windows-omnivox-dev for helper, protocol, dependency, or companion changes" >&2
            exit 1
            ;;
    esac
done < "$changed_paths"

current_cargo_lock=$(sha256sum "$omnivox_dir/Cargo.lock" | cut -d ' ' -f1)
current_toolchain_lock=$(sha256sum "$release_root/toolchain.lock" | cut -d ' ' -f1)
current_dockerfile=$(sha256sum "$release_root/Dockerfile" | cut -d ' ' -f1)
if [ "$current_cargo_lock" != "$(provenance_value cargo_lock_sha256)" ] ||
   [ "$current_toolchain_lock" != "$(provenance_value toolchain_lock_sha256)" ] ||
   [ "$current_dockerfile" != "$(provenance_value dockerfile_sha256)" ]; then
    echo "Locked build inputs differ from the reusable Omnivox runtime" >&2
    echo "Run make windows-omnivox-dev to rebuild every affected payload" >&2
    exit 1
fi

if ! release_image_id=$(docker image inspect --format '{{.Id}}' "$release_image" 2>/dev/null); then
    echo "Pinned Omnivox build image is unavailable: $release_image" >&2
    echo "Run make verify-windows-omnivox-toolchain first" >&2
    exit 1
fi
if [ "$release_image_id" != "$(provenance_value release_image_id)" ]; then
    echo "Pinned Omnivox build image differs from the reusable runtime" >&2
    echo "Run make windows-omnivox-dev to rebuild every payload" >&2
    exit 1
fi

build_target=$omnivox_dir/target/emacsvox-main-dev
if [ -L "$build_target" ]; then
    echo "Refusing symlinked main-only build target: $build_target" >&2
    exit 1
fi
mkdir -p "$build_target"
docker run --rm --platform linux/amd64 \
    --user "$(id -u):$(id -g)" \
    --env HOME=/workspace/omnivox/target/emacsvox-home \
    --env CARGO_HOME=/workspace/omnivox/target/emacsvox-cargo-home \
    --env CARGO_TARGET_DIR=/workspace/omnivox/target/emacsvox-main-dev \
    --volume "$omnivox_dir:/workspace/omnivox" \
    --workdir /workspace/omnivox \
    "$release_image" sh -eu -c '
        mkdir -p "$HOME" "$CARGO_HOME" "$CARGO_TARGET_DIR/stage";
        export CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc-win32;
        export CXX_x86_64_pc_windows_gnu=x86_64-w64-mingw32-g++-win32;
        export AR_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ar;
        export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc-win32;
        export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="-C link-arg=-Wl,--no-insert-timestamp";
        cargo build --locked --release -p omnivox-cli --target x86_64-pc-windows-gnu;
        cp "$CARGO_TARGET_DIR/x86_64-pc-windows-gnu/release/omnivox.exe" \
            "$CARGO_TARGET_DIR/stage/omnivox.unstripped.exe";
        cp "$CARGO_TARGET_DIR/stage/omnivox.unstripped.exe" \
            "$CARGO_TARGET_DIR/stage/omnivox.exe";
        SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all \
            "$CARGO_TARGET_DIR/stage/omnivox.exe"
    '

executable=$build_target/stage/omnivox.exe
unstripped_executable=$build_target/stage/omnivox.unstripped.exe
executable_digest=$(sha256sum "$executable" | cut -d ' ' -f1)
unstripped_digest=$(sha256sum "$unstripped_executable" | cut -d ' ' -f1)
emacsvox_commit=$(git -C "$emacsvox_dir" rev-parse HEAD)
omnivox_commit=$(git -C "$omnivox_dir" rev-parse HEAD)
emacsvox_worktree_digest=$(
    git -C "$emacsvox_dir" diff --binary HEAD -- | sha256sum | cut -d ' ' -f1
)
omnivox_worktree_digest=$(
    git -C "$omnivox_dir" diff --binary HEAD -- | sha256sum | cut -d ' ' -f1
)
build_method=incremental-main-executable-reuse
build_id=$(
    printf '%s\n' \
        "$build_method" "$reused_base_build_id" "$reused_manifest_digest" \
        "$executable_digest" "$unstripped_digest" \
        "$emacsvox_commit" "$omnivox_commit" \
        "$emacsvox_worktree_digest" "$omnivox_worktree_digest" \
        "$current_cargo_lock" "$current_toolchain_lock" \
        "$current_dockerfile" "$release_image_id" |
        sha256sum | cut -c1-16
)
version_runtime=$versions_root/$build_id
diagnostics=$release_root/cache/diagnostics/$build_id

mkdir "$stage_runtime"
cp -al "$base_runtime/." "$stage_runtime/"
cp "$executable" "$stage_runtime/omnivox.exe.new"
chmod +x "$stage_runtime/omnivox.exe.new"
mv -f "$stage_runtime/omnivox.exe.new" "$stage_runtime/omnivox.exe"
awk \
    -v build_id="$build_id" \
    -v emacsvox_commit="$emacsvox_commit" \
    -v omnivox_commit="$omnivox_commit" \
    -v emacsvox_worktree="$emacsvox_worktree_digest" \
    -v omnivox_worktree="$omnivox_worktree_digest" \
    -v cargo_lock="$current_cargo_lock" \
    -v executable="$executable_digest" \
    -v method="$build_method" \
    -v base="$reused_base_build_id" \
    -v base_manifest="$reused_manifest_digest" '
        /^build_method=/ || /^incremental_base_build_id=/ ||
            /^reused_payload_manifest_sha256=/ { next }
        /^build_id=/ { print "build_id=" build_id; next }
        /^emacsvox_commit=/ { print "emacsvox_commit=" emacsvox_commit; next }
        /^omnivox_commit=/ { print "omnivox_commit=" omnivox_commit; next }
        /^emacsvox_worktree_sha256=/ {
            print "emacsvox_worktree_sha256=" emacsvox_worktree; next
        }
        /^omnivox_worktree_sha256=/ {
            print "omnivox_worktree_sha256=" omnivox_worktree; next
        }
        /^cargo_lock_sha256=/ { print "cargo_lock_sha256=" cargo_lock; next }
        /^omnivox_executable_sha256=/ {
            print "omnivox_executable_sha256=" executable; next
        }
        { print }
        END {
            print "build_method=" method
            print "incremental_base_build_id=" base
            print "reused_payload_manifest_sha256=" base_manifest
        }
    ' "$base_runtime/PROVENANCE" > "$stage_runtime/PROVENANCE.new"
mv -f "$stage_runtime/PROVENANCE.new" "$stage_runtime/PROVENANCE"

provenance_digest=$(sha256sum "$stage_runtime/PROVENANCE" | cut -d ' ' -f1)
awk \
    -v executable="$executable_digest" \
    -v provenance="$provenance_digest" '
        $2 == "omnivox.exe" { print executable "  " $2; next }
        $2 == "PROVENANCE" { print provenance "  " $2; next }
        { print }
    ' "$base_runtime/SHA256SUMS" > "$stage_runtime/SHA256SUMS.new"
mv "$stage_runtime/SHA256SUMS.new" "$stage_runtime/SHA256SUMS"
(
    cd "$stage_runtime"
    printf '%s  %s\n' \
        "$executable_digest" omnivox.exe \
        "$provenance_digest" PROVENANCE | sha256sum --check --status
)

if [ -e "$version_runtime" ]; then
    if ! cmp -s "$stage_runtime/SHA256SUMS" "$version_runtime/SHA256SUMS"; then
        echo "Existing content-addressed main-only runtime differs: $version_runtime" >&2
        exit 1
    fi
else
    mv "$stage_runtime" "$version_runtime"
fi

base_reused_manifest=$temporary_root/base-reused-SHA256SUMS
version_reused_manifest=$temporary_root/version-reused-SHA256SUMS
awk 'substr($0, 67) != "omnivox.exe" && substr($0, 67) != "PROVENANCE"' \
    "$base_runtime/SHA256SUMS" > "$base_reused_manifest"
awk 'substr($0, 67) != "omnivox.exe" && substr($0, 67) != "PROVENANCE"' \
    "$version_runtime/SHA256SUMS" > "$version_reused_manifest"
if ! cmp -s "$base_reused_manifest" "$version_reused_manifest"; then
    echo "Main-only reused payload manifest differs from its verified base" >&2
    exit 1
fi
(
    cd "$version_runtime"
    printf '%s  %s\n' \
        "$executable_digest" omnivox.exe \
        "$provenance_digest" PROVENANCE | sha256sum --check --status
)

mkdir -p "$diagnostics"
cp "$unstripped_executable" "$diagnostics/omnivox.unstripped.exe.new"
mv -f "$diagnostics/omnivox.unstripped.exe.new" \
    "$diagnostics/omnivox.unstripped.exe"
{
    printf '%s\n' \
        'format=emacsvox-omnivox-local-diagnostics-v1' \
        "build_id=$build_id" \
        "emacsvox_commit=$emacsvox_commit" \
        "omnivox_commit=$omnivox_commit" \
        'build_kind=local-dirty-worktree' \
        "build_method=$build_method" \
        "incremental_base_build_id=$reused_base_build_id" \
        "emacsvox_worktree_sha256=$emacsvox_worktree_digest" \
        "omnivox_worktree_sha256=$omnivox_worktree_digest" \
        "deployed_omnivox_sha256=$executable_digest" \
        "unstripped_omnivox_sha256=$unstripped_digest"
} > "$diagnostics/MANIFEST.new"
mv -f "$diagnostics/MANIFEST.new" "$diagnostics/MANIFEST"

base_windows_runtime=$(wslpath -u "$(sed -n '1p' "$base_runtime/windows-runtime.path")")
windows_runtime_parent=${base_windows_runtime%/*}
if [ "$(basename -- "$base_windows_runtime")" != "$base_build_id" ]; then
    echo "Reusable Windows runtime path does not match its build identity" >&2
    exit 1
fi
windows_runtime=$windows_runtime_parent/$build_id
windows_complete=$windows_runtime/.main-dev-complete
if [ ! -e "$windows_runtime" ]; then
    windows_temporary_root=$(mktemp -d \
        "$windows_runtime_parent/.main-dev.$build_id.XXXXXX")
    cp -al "$base_windows_runtime/." "$windows_temporary_root/"
    for payload in omnivox.exe PROVENANCE; do
        cp "$version_runtime/$payload" \
            "$windows_temporary_root/$payload.new.$$"
        mv -f "$windows_temporary_root/$payload.new.$$" \
            "$windows_temporary_root/$payload"
    done
    printf '%s\n' "$build_id" > \
        "$windows_temporary_root/.main-dev-complete.new.$$"
    mv -f "$windows_temporary_root/.main-dev-complete.new.$$" \
        "$windows_temporary_root/.main-dev-complete"
    mv "$windows_temporary_root" "$windows_runtime"
    windows_temporary_root=
fi
if [ ! -f "$windows_complete" ] ||
   [ "$(sed -n '1p' "$windows_complete")" != "$build_id" ]; then
    echo "Windows-local main-only runtime is incomplete: $windows_runtime" >&2
    exit 1
fi
for payload in omnivox.exe PROVENANCE; do
    if ! cmp -s "$version_runtime/$payload" "$windows_runtime/$payload"; then
        echo "Windows-local main payload differs: $payload" >&2
        exit 1
    fi
done
windows_runtime_path=$(wslpath -w "$windows_runtime")
printf '%s\n' "$windows_runtime_path" > "$version_runtime/windows-runtime.path.new"
mv -f "$version_runtime/windows-runtime.path.new" \
    "$version_runtime/windows-runtime.path"

ln -sfn "versions/$build_id" "$runtime_root/current.new"
mv -Tf "$runtime_root/current.new" "$runtime_root/current"
echo "Staged main-only Omnivox runtime $build_id (reused $reused_base_build_id)"
