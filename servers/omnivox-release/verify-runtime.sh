#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 OMNIVOX_RUNTIME_DIR OMNIVOX_RELEASE_DIR" >&2
    exit 2
fi

runtime_root=$1
release_root=$2
# shellcheck source=toolchain.lock
. "$release_root/toolchain.lock"
current=$(readlink -f -- "$runtime_root/current")
versions_root=$(readlink -f -- "$runtime_root/versions")
case "$current/" in
    "$versions_root"/*/) ;;
    *)
        echo "Omnivox current does not resolve below $versions_root" >&2
        exit 1
        ;;
esac

for required in PROVENANCE SHA256SUMS espeak-ng-data.path \
    windows-runtime.path omnivox.exe piper/omnivox-piper-helper.exe \
    WINDOWS-HELPERS-COPYING \
    piper/piper.dll piper/onnxruntime.dll \
    piper/onnxruntime_providers_shared.dll piper/SOURCE-PROVENANCE.json \
    piper/espeak-ng-data/phontab; do
    if [ ! -f "$current/$required" ]; then
        echo "Staged Omnivox file is missing: $current/$required" >&2
        exit 1
    fi
done

for expected in \
    "omnivox_commit=$omnivox_piper_commit" \
    'omnivox_features=piper' \
    "piper_companion_version=$omnivox_piper_version" \
    "piper_companion_commit=$omnivox_piper_commit" \
    "piper_companion_archive_sha256=$omnivox_piper_archive_sha256"; do
    if ! grep -Fxq "$expected" "$current/PROVENANCE"; then
        echo "Staged Omnivox provenance is missing: $expected" >&2
        exit 1
    fi
done

expected_piper_digest=$(
    sed -n 's/^piper_companion_tree_sha256=//p' "$current/PROVENANCE"
)
actual_piper_digest=$(
    cd "$current/piper"
    find . -type f -print0 | LC_ALL=C sort -z |
        xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
)
if [ "$actual_piper_digest" != "$expected_piper_digest" ]; then
    echo "Staged Piper companion does not match provenance" >&2
    exit 1
fi

(cd "$current" && sha256sum --check SHA256SUMS)

build_id=$(sed -n 's/^build_id=//p' "$current/PROVENANCE")
if [ "$build_id" != "$(basename -- "$current")" ]; then
    echo "Provenance build ID does not match the selected version directory" >&2
    exit 1
fi

diagnostics=$release_root/cache/diagnostics/$build_id
for required in MANIFEST omnivox.unstripped.exe; do
    if [ ! -f "$diagnostics/$required" ]; then
        echo "Local Omnivox diagnostics are missing: $diagnostics/$required" >&2
        exit 1
    fi
done
diagnostics_build_id=$(sed -n 's/^build_id=//p' "$diagnostics/MANIFEST")
if [ "$diagnostics_build_id" != "$build_id" ]; then
    echo "Local diagnostics build ID does not match the staged runtime" >&2
    exit 1
fi
for field in build_kind emacsvox_worktree_sha256 omnivox_worktree_sha256; do
    provenance_value=$(sed -n "s/^$field=//p" "$current/PROVENANCE")
    diagnostics_value=$(sed -n "s/^$field=//p" "$diagnostics/MANIFEST")
    if [ -z "$provenance_value" ] ||
       [ "$provenance_value" != "$diagnostics_value" ]; then
        echo "Omnivox provenance and diagnostics disagree on $field" >&2
        exit 1
    fi
done
build_kind=$(sed -n 's/^build_kind=//p' "$current/PROVENANCE")
case "$build_kind" in
    release-clean-worktree | local-dirty-worktree) ;;
    *)
        echo "Unknown Omnivox build kind: $build_kind" >&2
        exit 1
        ;;
esac
for field in emacsvox_worktree_sha256 omnivox_worktree_sha256; do
    digest=$(sed -n "s/^$field=//p" "$current/PROVENANCE")
    case "$digest" in
        *[!0-9a-f]* | '')
            echo "Invalid Omnivox provenance digest: $field" >&2
            exit 1
            ;;
    esac
    if [ "${#digest}" -ne 64 ]; then
        echo "Invalid Omnivox provenance digest length: $field" >&2
        exit 1
    fi
done
expected_unstripped_digest=$(
    sed -n 's/^unstripped_omnivox_sha256=//p' "$diagnostics/MANIFEST"
)
actual_unstripped_digest=$(
    sha256sum "$diagnostics/omnivox.unstripped.exe" | cut -d ' ' -f1
)
if [ "$actual_unstripped_digest" != "$expected_unstripped_digest" ]; then
    echo "Local unstripped Omnivox executable does not match its manifest" >&2
    exit 1
fi
expected_deployed_digest=$(
    sed -n 's/^deployed_omnivox_sha256=//p' "$diagnostics/MANIFEST"
)
actual_deployed_digest=$(sha256sum "$current/omnivox.exe" | cut -d ' ' -f1)
if [ "$actual_deployed_digest" != "$expected_deployed_digest" ]; then
    echo "Local diagnostics do not identify the staged Omnivox executable" >&2
    exit 1
fi
provenance_deployed_digest=$(
    sed -n 's/^omnivox_executable_sha256=//p' "$current/PROVENANCE"
)
if [ "$actual_deployed_digest" != "$provenance_deployed_digest" ]; then
    echo "Staged Omnivox executable does not match its provenance" >&2
    exit 1
fi

windows_runtime_path=$(sed -n '1p' "$current/windows-runtime.path")
windows_runtime=$(wslpath -u "$windows_runtime_path")
while read -r _checksum payload; do
    if [ ! -f "$windows_runtime/$payload" ] ||
       ! cmp -s "$current/$payload" "$windows_runtime/$payload"; then
        echo "Windows-local Omnivox payload differs: $payload" >&2
        exit 1
    fi
done < "$current/SHA256SUMS"

espeak_cache_path=$(sed -n '1p' "$current/espeak-ng-data.path")
espeak_cache=$(wslpath -u "$espeak_cache_path")/espeak-ng-data
if [ ! -f "$espeak_cache/phontab" ]; then
    echo "Windows-local eSpeak data is incomplete: $espeak_cache" >&2
    exit 1
fi
expected_espeak_digest=$(
    sed -n 's/^espeak_data_sha256=//p' "$current/PROVENANCE"
)
actual_espeak_digest=$(
    cd "$espeak_cache"
    find . -type f -print0 | LC_ALL=C sort -z |
        xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
)
if [ "$actual_espeak_digest" != "$expected_espeak_digest" ]; then
    echo "Windows-local eSpeak data does not match provenance" >&2
    exit 1
fi

if find "$current" -type f \( -name '*.onnx' -o -name '*.onnx.json' \) |
    grep -q .; then
    echo "A Piper voice model was bundled inside the Omnivox runtime" >&2
    exit 1
fi
piper_model_state=$(sed -n 's/^piper_model=//p' "$current/PROVENANCE")
case "$piper_model_state" in
    external-user-supplied-not-configured) ;;
    external-user-supplied-windows-cache)
        for path_file in piper-model.path piper-model-config.path; do
            if [ ! -s "$current/$path_file" ]; then
                echo "Configured Piper model path is missing: $current/$path_file" >&2
                exit 1
            fi
        done
        piper_model=$(wslpath -u "$(sed -n '1p' "$current/piper-model.path")")
        piper_model_config=$(
            wslpath -u "$(sed -n '1p' "$current/piper-model-config.path")"
        )
        if [ ! -f "$piper_model" ] || [ ! -f "$piper_model_config" ]; then
            echo "Windows-local Piper model or configuration is missing" >&2
            exit 1
        fi
        case "$piper_model_config" in
            "$piper_model.json" | "${piper_model%.onnx}.json") ;;
            *)
                echo "Windows-local Piper configuration is not adjacent to its model" >&2
                exit 1
                ;;
        esac
        expected_model_sha256=$(
            sed -n 's/^piper_model_sha256=//p' "$current/PROVENANCE"
        )
        expected_model_config_sha256=$(
            sed -n 's/^piper_model_config_sha256=//p' "$current/PROVENANCE"
        )
        actual_model_sha256=$(sha256sum "$piper_model" | cut -d ' ' -f1)
        actual_model_config_sha256=$(
            sha256sum "$piper_model_config" | cut -d ' ' -f1
        )
        if [ "$actual_model_sha256" != "$expected_model_sha256" ] ||
           [ "$actual_model_config_sha256" != \
             "$expected_model_config_sha256" ]; then
            echo "Windows-local Piper model does not match provenance" >&2
            exit 1
        fi
        ;;
    *)
        echo "Unknown Piper model provenance state: $piper_model_state" >&2
        exit 1
        ;;
esac

printf '%s\n' \
    "verified_build_id=$build_id" \
    "repository_runtime=$current" \
    "launcher_runtime=$windows_runtime" \
    "local_diagnostics=$diagnostics"
