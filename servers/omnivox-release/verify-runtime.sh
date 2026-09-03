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
    windows-runtime.path omnivox.exe \
    rhvoice/omnivox-rhvoice-helper.exe \
    flite/omnivox-flite-helper.exe flite/SHA256SUMS \
    flite/SOURCE-PROVENANCE.json \
    flite/third-party-licenses/Flite-COPYING.txt \
    rutts/omnivox-rutts-helper.exe rutts/SHA256SUMS \
    rutts/SOURCE-PROVENANCE.json \
    rutts/third-party-licenses/RuTTS-LICENSE.txt \
    WINDOWS-HELPERS-COPYING OMNIVOX-LICENSE; do
    if [ ! -f "$current/$required" ]; then
        echo "Staged Omnivox file is missing: $current/$required" >&2
        exit 1
    fi
done

for expected in \
    'rhvoice_companion=local-omnivox-build' \
    'rhvoice_runtime=external-user-supplied-not-bundled' \
    'flite_companion=local-omnivox-build' \
    'flite_target=x86_64-pc-windows-gnu' \
    'flite_compiled_voice=cmu_us_slt' \
    'rutts_companion=local-omnivox-build' \
    'rutts_target=x86_64-pc-windows-gnu' \
    'rutts_version=6.3.3' \
    'rutts_built_in_voices=male,female' \
    'rutts_rulex=not-included'; do
    if ! grep -Fxq "$expected" "$current/PROVENANCE"; then
        echo "Staged Omnivox provenance is missing: $expected" >&2
        exit 1
    fi
done

for companion in rhvoice flite rutts; do
    expected_companion_digest=$(
        sed -n "s/^${companion}_companion_tree_sha256=//p" \
            "$current/PROVENANCE"
    )
    actual_companion_digest=$(
        cd "$current/$companion"
        find . -type f -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
    )
    if [ "$actual_companion_digest" != "$expected_companion_digest" ]; then
        echo "Staged $companion companion does not match provenance" >&2
        exit 1
    fi
done

(cd "$current/flite" && sha256sum --check SHA256SUMS >/dev/null)
if ! grep -Fq '"target": "x86_64-pc-windows-gnu"' \
    "$current/flite/SOURCE-PROVENANCE.json" ||
   ! grep -Fq '"compiled_voice": "cmu_us_slt"' \
    "$current/flite/SOURCE-PROVENANCE.json"; then
    echo "Staged Flite companion provenance is wrong" >&2
    exit 1
fi

(cd "$current/rutts" && sha256sum --check SHA256SUMS >/dev/null)
if ! grep -Fq '"target": "x86_64-pc-windows-gnu"' \
    "$current/rutts/SOURCE-PROVENANCE.json" ||
   ! grep -Fq '"version": "6.3.3"' \
    "$current/rutts/SOURCE-PROVENANCE.json" ||
   ! grep -Fq '"rulex_included": false' \
    "$current/rutts/SOURCE-PROVENANCE.json" ||
   ! grep -Fq '"male"' "$current/rutts/SOURCE-PROVENANCE.json" ||
   ! grep -Fq '"female"' "$current/rutts/SOURCE-PROVENANCE.json"; then
    echo "Staged RuTTS companion provenance is wrong" >&2
    exit 1
fi

tgspeechbox_companion_state=$(
    sed -n 's/^tgspeechbox_companion=//p' "$current/PROVENANCE"
)
case "$tgspeechbox_companion_state" in
    local-omnivox-experimental-build)
        for required in tgspeechbox/omnivox-tgspeechbox-helper.exe \
            tgspeechbox/VOICE-INVENTORY.json \
            tgspeechbox/VOICE-INVENTORY-22050.json \
            tgspeechbox/VOICE-INVENTORY-44100.json \
            tgspeechbox/SHA256SUMS tgspeechbox/SOURCE-PROVENANCE.json \
            tgspeechbox/espeak-ng-data/phontab \
            tgspeechbox/packs/lang/en-us.yaml \
            tgspeechbox/third-party-licenses/TGSpeechBox-LICENSE.txt \
            tgspeechbox/third-party-licenses/eSpeak-NG-GPL-3.0.txt; do
            if [ ! -f "$current/$required" ]; then
                echo "Staged TGSpeechBox file is missing: $current/$required" >&2
                exit 1
            fi
        done
        for expected in \
            'build_kind=local-dirty-worktree' \
            'tgspeechbox_target=x86_64-pc-windows-gnu' \
            'tgspeechbox_markers=exact_requested_anchors' \
            'tgspeechbox_rate_mapping=calibrated_eloquence_v1' \
            'tgspeechbox_build_environment=wsl-host-development-only'; do
            if ! grep -Fxq "$expected" "$current/PROVENANCE"; then
                echo "Staged Omnivox provenance is missing: $expected" >&2
                exit 1
            fi
        done
        expected_tgspeechbox_digest=$(
            sed -n 's/^tgspeechbox_companion_tree_sha256=//p' \
                "$current/PROVENANCE"
        )
        actual_tgspeechbox_digest=$(
            cd "$current/tgspeechbox"
            find . -type f -print0 | LC_ALL=C sort -z |
                xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
        )
        if [ "$actual_tgspeechbox_digest" != \
             "$expected_tgspeechbox_digest" ]; then
            echo "Staged TGSpeechBox companion does not match provenance" >&2
            exit 1
        fi
        tgspeechbox_cxx=$(sed -n 's/^tgspeechbox_cxx=//p' \
            "$current/PROVENANCE")
        tgspeechbox_cxx_digest=$(sed -n 's/^tgspeechbox_cxx_sha256=//p' \
            "$current/PROVENANCE")
        if [ -z "$tgspeechbox_cxx" ] || \
           [ "$tgspeechbox_cxx" = not-included ]; then
            echo "Staged TGSpeechBox provenance does not identify its C++ compiler" >&2
            exit 1
        fi
        case "$tgspeechbox_cxx_digest" in
            *[!0-9a-f]* | '')
                echo "Invalid TGSpeechBox C++ compiler digest" >&2
                exit 1
                ;;
        esac
        if [ "${#tgspeechbox_cxx_digest}" -ne 64 ]; then
            echo "Invalid TGSpeechBox C++ compiler digest length" >&2
            exit 1
        fi
        (cd "$current/tgspeechbox" && \
            sha256sum --check SHA256SUMS >/dev/null)
        if ! cmp -s "$current/tgspeechbox/VOICE-INVENTORY.json" \
            "$current/tgspeechbox/VOICE-INVENTORY-44100.json"; then
            echo "Default TGSpeechBox inventory is not the 44.1 kHz inventory" >&2
            exit 1
        fi
        for sample_rate in 22050 44100; do
            inventory="$current/tgspeechbox/VOICE-INVENTORY-$sample_rate.json"
            if ! grep -Fq "native $sample_rate Hz" "$inventory"; then
                echo "TGSpeechBox inventory has the wrong native rate: $inventory" >&2
                exit 1
            fi
        done
        for expected in \
            '"artifact": "omnivox-tgspeechbox-companion-windows-x64-gnu"' \
            '"default_native_sample_rate_hz": 44100' \
            '"markers_advertised": true' \
            '"marker_support": "exact_requested_anchors"' \
            '"rate_mapping": "calibrated_eloquence_v1"' \
            '"VOICE-INVENTORY-22050.json"' \
            '"VOICE-INVENTORY-44100.json"' \
            '"generated_by_packaged_helper": true' \
            '"voices": 154' \
            '"target": "x86_64-pc-windows-gnu"' \
            '"commit": "f5ec247bca50507ab1e2ed661136395538dc3e97"' \
            '"release": "v-310@f5ec247"'; do
            if ! grep -Fq "$expected" \
                "$current/tgspeechbox/SOURCE-PROVENANCE.json"; then
                echo "Staged TGSpeechBox companion provenance is wrong: $expected" >&2
                exit 1
            fi
        done
        ;;
    not-included)
        for expected in \
            'tgspeechbox_companion_tree_sha256=not-included' \
            'tgspeechbox_target=not-included' \
            'tgspeechbox_markers=not-included' \
            'tgspeechbox_rate_mapping=not-included' \
            'tgspeechbox_build_environment=not-included' \
            'tgspeechbox_cxx=not-included' \
            'tgspeechbox_cxx_sha256=not-included'; do
            if ! grep -Fxq "$expected" "$current/PROVENANCE"; then
                echo "TGSpeechBox exclusion is missing provenance: $expected" >&2
                exit 1
            fi
        done
        if [ -e "$current/tgspeechbox" ]; then
            echo "TGSpeechBox exclusion is inconsistent with the staged runtime" >&2
            exit 1
        fi
        ;;
    *)
        echo "Unknown TGSpeechBox companion state: $tgspeechbox_companion_state" >&2
        exit 1
        ;;
esac

piper_companion_state=$(
    sed -n 's/^piper_companion=//p' "$current/PROVENANCE"
)
case "$piper_companion_state" in
    official-omnivox-release)
        for required in piper/omnivox-piper-helper.exe piper/piper.dll \
            piper/onnxruntime.dll piper/onnxruntime_providers_shared.dll \
            piper/SOURCE-PROVENANCE.json piper/espeak-ng-data/phontab; do
            if [ ! -f "$current/$required" ]; then
                echo "Staged Piper file is missing: $current/$required" >&2
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
        verify_piper_payload=true
        ;;
    github-actions-native-development-build)
        for required in piper/omnivox-piper-helper.exe piper/piper.dll \
            piper/onnxruntime.dll piper/onnxruntime_providers_shared.dll \
            piper/SOURCE-PROVENANCE.json piper/SHA256SUMS \
            piper/espeak-ng-data/phontab; do
            if [ ! -f "$current/$required" ]; then
                echo "Staged Piper development file is missing: $current/$required" >&2
                exit 1
            fi
        done
        omnivox_commit=$(sed -n 's/^omnivox_commit=//p' "$current/PROVENANCE")
        for expected in \
            'build_kind=local-dirty-worktree' \
            'omnivox_features=piper' \
            'piper_companion_version=development-ci' \
            "piper_companion_commit=$omnivox_commit"; do
            if ! grep -Fxq "$expected" "$current/PROVENANCE"; then
                echo "Staged Piper development provenance is missing: $expected" >&2
                exit 1
            fi
        done
        piper_archive_digest=$(sed -n \
            's/^piper_companion_archive_sha256=//p' "$current/PROVENANCE")
        case "$piper_archive_digest" in
            *[!0-9a-f]* | '')
                echo "Invalid Piper development archive digest" >&2
                exit 1
                ;;
        esac
        if [ "${#piper_archive_digest}" -ne 64 ]; then
            echo "Invalid Piper development archive digest length" >&2
            exit 1
        fi
        for expected in \
            '"artifact": "omnivox-piper-companion-windows-x64"' \
            '"target": "x86_64-pc-windows-msvc"' \
            '"tracked_worktree_dirty": false' \
            "\"commit\": \"$omnivox_commit\""; do
            if ! grep -Fq "$expected" "$current/piper/SOURCE-PROVENANCE.json"; then
                echo "Staged Piper development source provenance is wrong: $expected" >&2
                exit 1
            fi
        done
        verify_piper_payload=true
        ;;
    not-included)
        if [ -e "$current/piper" ] ||
           ! grep -Fxq 'omnivox_features=none' "$current/PROVENANCE"; then
            echo "Piper exclusion is inconsistent with the staged runtime" >&2
            exit 1
        fi
        ;;
    *)
        echo "Unknown Piper companion state: $piper_companion_state" >&2
        exit 1
        ;;
esac

if [ "${verify_piper_payload:-false}" = true ]; then
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
    (cd "$current/piper" && sha256sum --check SHA256SUMS >/dev/null)
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
espeak_cache_parent=$(wslpath -u "$espeak_cache_path")
espeak_cache=$espeak_cache_parent/espeak-ng-data
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
espeak_identity=$espeak_cache_parent/omnivox-espeak-data.sha256
if [ ! -f "$espeak_identity" ] ||
   [ "$(wc -l < "$espeak_identity")" -ne 1 ] ||
   [ "$(sed -n '1p' "$espeak_identity")" != "$expected_espeak_digest" ]; then
    echo "Windows-local eSpeak cache identity does not match provenance" >&2
    exit 1
fi

rhvoice_configuration=$(
    sed -n 's/^rhvoice_configuration=//p' "$current/PROVENANCE"
)
case "$rhvoice_configuration" in
    not-recorded)
        for path_file in rhvoice-library.path rhvoice-data.path \
            rhvoice-config.path; do
            if [ -e "$current/$path_file" ]; then
                echo "Unrecorded RHVoice configuration has a path pointer: $path_file" >&2
                exit 1
            fi
        done
        ;;
    recorded-windows-paths)
        for path_file in rhvoice-library.path rhvoice-data.path; do
            if [ ! -s "$current/$path_file" ]; then
                echo "Configured RHVoice path is missing: $current/$path_file" >&2
                exit 1
            fi
        done
        rhvoice_library=$(
            wslpath -u "$(sed -n '1p' "$current/rhvoice-library.path")"
        )
        rhvoice_data=$(
            wslpath -u "$(sed -n '1p' "$current/rhvoice-data.path")"
        )
        if [ ! -f "$rhvoice_library" ] ||
           [ ! -d "$rhvoice_data/languages" ] ||
           [ ! -d "$rhvoice_data/voices" ]; then
            echo "Recorded RHVoice library or data is unavailable" >&2
            exit 1
        fi
        expected_rhvoice_library_digest=$(
            sed -n 's/^rhvoice_library_sha256=//p' "$current/PROVENANCE"
        )
        expected_rhvoice_data_digest=$(
            sed -n 's/^rhvoice_data_tree_sha256=//p' "$current/PROVENANCE"
        )
        actual_rhvoice_library_digest=$(
            sha256sum "$rhvoice_library" | cut -d ' ' -f1
        )
        actual_rhvoice_data_digest=$(
            cd "$rhvoice_data"
            find . -type f -print0 | LC_ALL=C sort -z |
                xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
        )
        if [ "$actual_rhvoice_library_digest" != \
             "$expected_rhvoice_library_digest" ] ||
           [ "$actual_rhvoice_data_digest" != \
             "$expected_rhvoice_data_digest" ]; then
            echo "Recorded RHVoice runtime does not match provenance" >&2
            exit 1
        fi
        expected_rhvoice_config_digest=$(
            sed -n 's/^rhvoice_config_tree_sha256=//p' "$current/PROVENANCE"
        )
        if [ "$expected_rhvoice_config_digest" = not-configured ]; then
            if [ -e "$current/rhvoice-config.path" ]; then
                echo "RHVoice configuration path exists without provenance" >&2
                exit 1
            fi
        else
            if [ ! -s "$current/rhvoice-config.path" ]; then
                echo "Configured RHVoice path is missing: $current/rhvoice-config.path" >&2
                exit 1
            fi
            rhvoice_config=$(
                wslpath -u "$(sed -n '1p' "$current/rhvoice-config.path")"
            )
            if [ ! -d "$rhvoice_config" ]; then
                echo "Recorded RHVoice configuration is unavailable" >&2
                exit 1
            fi
            actual_rhvoice_config_digest=$(
                cd "$rhvoice_config"
                find . -type f -print0 | LC_ALL=C sort -z |
                    xargs -0 sha256sum | sha256sum | cut -d ' ' -f1
            )
            if [ "$actual_rhvoice_config_digest" != \
                 "$expected_rhvoice_config_digest" ]; then
                echo "Recorded RHVoice configuration does not match provenance" >&2
                exit 1
            fi
        fi
        ;;
    *)
        echo "Unknown RHVoice configuration state: $rhvoice_configuration" >&2
        exit 1
        ;;
esac

if find "$current" -type f \( -name '*.onnx' -o -name '*.onnx.json' \) |
    grep -q .; then
    echo "A Piper voice model was bundled inside the Omnivox runtime" >&2
    exit 1
fi
piper_model_state=$(sed -n 's/^piper_model=//p' "$current/PROVENANCE")
case "$piper_model_state" in
    not-included)
        if [ "$piper_companion_state" != not-included ] ||
           [ -e "$current/piper-model.path" ] ||
           [ -e "$current/piper-model-config.path" ]; then
            echo "Piper model exclusion is inconsistent with the staged runtime" >&2
            exit 1
        fi
        ;;
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
