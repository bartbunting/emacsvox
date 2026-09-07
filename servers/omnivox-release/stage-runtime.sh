#!/bin/sh
# Copyright (C) 1995 -- 2024, T. V. Raman
# Copyright (c) 1994, 1995 by Digital Equipment Corporation.
# All Rights Reserved.
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Host-side runtime staging, extracted from the Emacsvox Makefile.
# Internal entry point: use the guarded windows-omnivox Make targets.
# Make passes resolved paths, feature switches, and pinned provenance fields
# through the environment below. Optional user voice inputs retain their
# OMNIVOX_PIPER_MODEL, OMNIVOX_RHVOICE_*, and OMNIVOX_ECI_DLL environment names.
# See docs/developer/integration-maintenance.org for ownership and validation.

set -eu

: "${EMACSVOX_STAGE_ROOT?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_BUILD_KIND?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_CSC?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_DIR?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_HELPER_DIR?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_INCLUDE_PINNED_PIPER?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_INCLUDE_TGSPEECHBOX?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_PIPER_COMPANION_COMMIT?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_PIPER_COMPANION_STATE?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_PIPER_COMPANION_VERSION?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_PIPER_DIR?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_RECORD_RHVOICE?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_RELEASE_DIR?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_RELEASE_IMAGE?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_RELEASE_TARGET_DIR?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_RUNTIME_DIR?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_TARGET?Use a guarded windows-omnivox Make target}"
: "${OMNIVOX_TGSPEECHBOX_CXX?Use a guarded windows-omnivox Make target}"
: "${reference_assemblies_nupkg_sha256?Use a guarded windows-omnivox Make target}"
: "${roslyn_nupkg_sha256?Use a guarded windows-omnivox Make target}"

executable="${OMNIVOX_RELEASE_TARGET_DIR}/${OMNIVOX_TARGET}/release/omnivox.exe"
unstripped_executable="${OMNIVOX_RELEASE_TARGET_DIR}/${OMNIVOX_TARGET}/release/omnivox.unstripped.exe"
rhvoice_companion="${OMNIVOX_RELEASE_TARGET_DIR}/${OMNIVOX_TARGET}/release/rhvoice"
flite_companion="${OMNIVOX_RELEASE_TARGET_DIR}/${OMNIVOX_TARGET}/release/flite"
rutts_companion="${OMNIVOX_RELEASE_TARGET_DIR}/${OMNIVOX_TARGET}/release/rutts"
tgspeechbox_companion="${OMNIVOX_RELEASE_TARGET_DIR}/${OMNIVOX_TARGET}/release/tgspeechbox"
omnivox_license="${OMNIVOX_DIR}/LICENSE"
eloquence_helper="${OMNIVOX_HELPER_DIR}/bin/OmnivoxEloquenceHelper32.exe"
dectalk_helper="${OMNIVOX_HELPER_DIR}/bin/OmnivoxDectalkHelper32.exe"
helper_license="${OMNIVOX_HELPER_DIR}/COPYING"
dectalk_dll="${EMACSVOX_STAGE_ROOT}/servers/windows-dectalk/runtime/DECtalk.dll"
dectalk_dictionary="${EMACSVOX_STAGE_ROOT}/servers/windows-dectalk/runtime/dtalk_us.dic"
stdlib="${OMNIVOX_RELEASE_TARGET_DIR}/windows-runtime/libstdc++-6.dll"
gcc_runtime="${OMNIVOX_RELEASE_TARGET_DIR}/windows-runtime/libgcc_s_seh-1.dll"
for required in \
	"$rhvoice_companion/omnivox-rhvoice-helper.exe" \
	"$flite_companion/omnivox-flite-helper.exe" \
	"$flite_companion/SHA256SUMS" \
	"$flite_companion/SOURCE-PROVENANCE.json" \
	"$flite_companion/third-party-licenses/Flite-COPYING.txt" \
	"$rutts_companion/omnivox-rutts-helper.exe" \
	"$rutts_companion/SHA256SUMS" \
	"$rutts_companion/SOURCE-PROVENANCE.json" \
	"$rutts_companion/third-party-licenses/RuTTS-LICENSE.txt" \
	"$omnivox_license"; do
	if [ ! -f "$required" ]; then
		echo "Prepared companion file is missing: $required" >&2
		exit 1
	fi
done
rhvoice_companion_digest="$(cd "$rhvoice_companion" && \
	find . -type f -print0 | LC_ALL=C sort -z | \
	xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
flite_companion_digest="$(cd "$flite_companion" && \
	find . -type f -print0 | LC_ALL=C sort -z | \
	xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
rutts_companion_digest="$(cd "$rutts_companion" && \
	find . -type f -print0 | LC_ALL=C sort -z | \
	xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
tgspeechbox_companion_digest=not-included
tgspeechbox_build_environment=not-included
tgspeechbox_cxx=not-included
tgspeechbox_cxx_digest=not-included
if [ "${OMNIVOX_INCLUDE_TGSPEECHBOX}" = 1 ]; then
	for required in \
		"$tgspeechbox_companion/omnivox-tgspeechbox-helper.exe" \
		"$tgspeechbox_companion/VOICE-INVENTORY.json" \
		"$tgspeechbox_companion/VOICE-INVENTORY-22050.json" \
		"$tgspeechbox_companion/VOICE-INVENTORY-44100.json" \
		"$tgspeechbox_companion/SHA256SUMS" \
		"$tgspeechbox_companion/SOURCE-PROVENANCE.json" \
		"$tgspeechbox_companion/espeak-ng-data/phontab" \
		"$tgspeechbox_companion/packs/lang/en-us.yaml" \
		"$tgspeechbox_companion/third-party-licenses/TGSpeechBox-LICENSE.txt" \
		"$tgspeechbox_companion/third-party-licenses/eSpeak-NG-GPL-3.0.txt"; do
		if [ ! -f "$required" ]; then
			echo "Prepared TGSpeechBox companion file is missing: $required" >&2
			exit 1
		fi
	done
	if x86_64-w64-mingw32-objdump -p \
		"$tgspeechbox_companion/omnivox-tgspeechbox-helper.exe" | \
		grep -Eiq 'DLL Name: (libstdc\+\+|libgcc|libwinpthread)'; then
		echo "TGSpeechBox helper imports an unbundled MinGW runtime DLL" >&2
		exit 1
	fi
	tgspeechbox_companion_digest="$(cd "$tgspeechbox_companion" && \
		find . -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
	tgspeechbox_build_environment=wsl-host-development-only
	tgspeechbox_cxx="$("${OMNIVOX_TGSPEECHBOX_CXX}" --version | sed -n '1p')"
	tgspeechbox_cxx_path="$(command -v "${OMNIVOX_TGSPEECHBOX_CXX}")"
	tgspeechbox_cxx_digest="$(sha256sum \
		"$(readlink -f "$tgspeechbox_cxx_path")" | cut -d ' ' -f1)"
fi
piper_companion=
piper_companion_digest=not-included
if [ "${OMNIVOX_INCLUDE_PINNED_PIPER}" = 1 ]; then
	piper_companion="${OMNIVOX_PIPER_DIR}"
	if [ ! -f "$piper_companion/omnivox-piper-helper.exe" ] || \
		[ ! -f "$piper_companion/espeak-ng-data/phontab" ]; then
		echo "Prepared Piper companion is incomplete: $piper_companion" >&2
		exit 1
	fi
	piper_companion_digest="$(cd "$piper_companion" && \
		find . -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
fi
espeak_phontab="$(find \
	"${OMNIVOX_RELEASE_TARGET_DIR}/release/build" \
	-path '*/espeak-rs-sys-*/out/share/espeak-ng-data/phontab' \
	-print -quit)"
if [ -z "$espeak_phontab" ]; then
	echo "Could not locate native espeak-ng-data build output" >&2
	exit 1
fi
espeak_data="${espeak_phontab%/phontab}"
data_digest="$(cd "$espeak_data" && \
	find . -type f -print0 | LC_ALL=C sort -z | \
	xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
windows_local_app_data="$(powershell.exe -NoProfile -NonInteractive \
	-Command '[Environment]::GetFolderPath("LocalApplicationData")' | \
	tr -d '\r')"
if [ -z "$windows_local_app_data" ]; then
	echo "Could not locate Windows LocalAppData" >&2
	exit 1
fi
rhvoice_configuration_state=not-recorded
rhvoice_library_digest=not-observed
rhvoice_data_digest=not-observed
rhvoice_config_digest=not-configured
rhvoice_library_windows_path=
rhvoice_data_windows_path=
rhvoice_config_windows_path=
if [ "${OMNIVOX_RECORD_RHVOICE}" = 1 ] && \
	{ [ -n "${OMNIVOX_RHVOICE_LIBRARY:-}" ] || \
	  [ -n "${OMNIVOX_RHVOICE_DATA:-}" ] || \
	  [ -n "${OMNIVOX_RHVOICE_CONFIG:-}" ]; }; then
	if [ -z "${OMNIVOX_RHVOICE_LIBRARY:-}" ] || \
		[ -z "${OMNIVOX_RHVOICE_DATA:-}" ]; then
		echo "Recording RHVoice requires OMNIVOX_RHVOICE_LIBRARY and OMNIVOX_RHVOICE_DATA" >&2
		exit 1
	fi
	rhvoice_library_source="$OMNIVOX_RHVOICE_LIBRARY"
	if [ ! -f "$rhvoice_library_source" ]; then
		rhvoice_library_source="$(wslpath -u \
			"$OMNIVOX_RHVOICE_LIBRARY" 2>/dev/null || :)"
	fi
	case "$rhvoice_library_source" in
		*.[dD][lL][lL]) ;;
		*) \
			echo "OMNIVOX_RHVOICE_LIBRARY must identify a readable RHVoice.dll" >&2
			exit 1 ;;
	esac
	if [ ! -f "$rhvoice_library_source" ]; then
		echo "OMNIVOX_RHVOICE_LIBRARY does not identify a readable file" >&2
		exit 1
	fi
	rhvoice_data_source="$OMNIVOX_RHVOICE_DATA"
	if [ ! -d "$rhvoice_data_source" ]; then
		rhvoice_data_source="$(wslpath -u \
			"$OMNIVOX_RHVOICE_DATA" 2>/dev/null || :)"
	fi
	if [ ! -d "$rhvoice_data_source/languages" ] || \
		[ ! -d "$rhvoice_data_source/voices" ]; then
		echo "OMNIVOX_RHVOICE_DATA must contain languages and voices directories" >&2
		exit 1
	fi
	rhvoice_library_digest="$(sha256sum \
		"$rhvoice_library_source" | cut -d ' ' -f1)"
	rhvoice_data_digest="$(cd "$rhvoice_data_source" && \
		find . -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
	rhvoice_library_windows_path="$(wslpath -w \
		"$rhvoice_library_source")"
	rhvoice_data_windows_path="$(wslpath -w \
		"$rhvoice_data_source")"
	if [ -n "${OMNIVOX_RHVOICE_CONFIG:-}" ]; then
		rhvoice_config_source="$OMNIVOX_RHVOICE_CONFIG"
		if [ ! -d "$rhvoice_config_source" ]; then
			rhvoice_config_source="$(wslpath -u \
				"$OMNIVOX_RHVOICE_CONFIG" 2>/dev/null || :)"
		fi
		if [ ! -d "$rhvoice_config_source" ]; then
			echo "OMNIVOX_RHVOICE_CONFIG does not identify a readable directory" >&2
			exit 1
		fi
		rhvoice_config_digest="$(cd "$rhvoice_config_source" && \
			find . -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
		rhvoice_config_windows_path="$(wslpath -w \
			"$rhvoice_config_source")"
	fi
	rhvoice_configuration_state=recorded-windows-paths
fi
piper_model_state=not-included
piper_model_digest=not-configured
piper_model_sha256=not-observed
piper_model_config_sha256=not-observed
piper_model_windows_path=
piper_model_config_windows_path=
if [ "${OMNIVOX_INCLUDE_PINNED_PIPER}" = 1 ]; then
	piper_model_state=external-user-supplied-not-configured
elif [ -n "${OMNIVOX_PIPER_MODEL:-}" ]; then
	echo "OMNIVOX_PIPER_MODEL cannot be used when the development runtime omits Piper" >&2
	exit 1
fi
if [ "${OMNIVOX_INCLUDE_PINNED_PIPER}" = 1 ] && \
	[ -n "${OMNIVOX_PIPER_MODEL:-}" ]; then
	piper_model_source="$OMNIVOX_PIPER_MODEL"
	if [ ! -f "$piper_model_source" ]; then
		piper_model_source="$(wslpath -u "$OMNIVOX_PIPER_MODEL" 2>/dev/null || :)"
	fi
	case "$piper_model_source" in
		*.onnx) ;;
		*) \
			echo "OMNIVOX_PIPER_MODEL must identify a readable .onnx file" >&2
			exit 1 ;;
	esac
	if [ ! -f "$piper_model_source" ]; then
		echo "OMNIVOX_PIPER_MODEL does not identify a readable file" >&2
		exit 1
	fi
	if [ -f "$piper_model_source.json" ]; then
		piper_model_config_source="$piper_model_source.json"
	elif [ -f "${piper_model_source%.onnx}.json" ]; then
		piper_model_config_source="${piper_model_source%.onnx}.json"
	else
		echo "Piper model configuration is not adjacent to $piper_model_source" >&2
		exit 1
	fi
	piper_model_sha256="$(sha256sum "$piper_model_source" | cut -d ' ' -f1)"
	piper_model_config_sha256="$(sha256sum \
		"$piper_model_config_source" | cut -d ' ' -f1)"
	piper_model_digest="$(printf '%s\n%s\n' \
		"$piper_model_sha256" "$piper_model_config_sha256" | \
		sha256sum | cut -d ' ' -f1)"
	piper_model_cache="$(wslpath -u "$windows_local_app_data")/Emacsvox/Omnivox/piper-models/$piper_model_digest"
	mkdir -p "$piper_model_cache"
	install_model_input() {
		model_source=$1
		model_destination="$piper_model_cache/${model_source##*/}"
		if [ ! -f "$model_destination" ]; then
			cp "$model_source" "$model_destination.new.$$"
			mv "$model_destination.new.$$" "$model_destination"
		fi
		if ! cmp -s "$model_source" "$model_destination"; then
			echo "Existing content-addressed Piper model differs: $model_destination" >&2
			exit 1
		fi
	}
	install_model_input "$piper_model_source"
	install_model_input "$piper_model_config_source"
	piper_model_windows_path="$(wslpath -w \
		"$piper_model_cache/${piper_model_source##*/}")"
	piper_model_config_windows_path="$(wslpath -w \
		"$piper_model_cache/${piper_model_config_source##*/}")"
	piper_model_state=external-user-supplied-windows-cache
fi
windows_cache_parent="$(wslpath -u "$windows_local_app_data")/Emacsvox/Omnivox/espeak-data/$data_digest"
mkdir -p "$windows_cache_parent"
if [ ! -f "$windows_cache_parent/espeak-ng-data/phontab" ]; then
	cache_stage="$windows_cache_parent/espeak-ng-data.new.$$"
	cp -a "$espeak_data" "$cache_stage"
	mv "$cache_stage" "$windows_cache_parent/espeak-ng-data"
fi
espeak_identity="$windows_cache_parent/omnivox-espeak-data.sha256"
if [ ! -f "$espeak_identity" ]; then
	printf '%s\n' "$data_digest" > "$espeak_identity.new.$$"
	mv "$espeak_identity.new.$$" "$espeak_identity"
fi
if [ "$(wc -l < "$espeak_identity")" -ne 1 ] || \
	[ "$(sed -n '1p' "$espeak_identity")" != "$data_digest" ]; then
	echo "Existing eSpeak cache identity differs: $espeak_identity" >&2
	exit 1
fi
windows_cache_path="$(wslpath -w "$windows_cache_parent")"
emacsvox_commit="$(git -C "${EMACSVOX_STAGE_ROOT}" rev-parse HEAD)"
omnivox_commit="$(git -C "${OMNIVOX_DIR}" rev-parse HEAD)"
build_kind="${OMNIVOX_BUILD_KIND}"
emacsvox_worktree_digest="$(git -C "${EMACSVOX_STAGE_ROOT}" diff --binary HEAD -- | \
	sha256sum | cut -d ' ' -f1)"
omnivox_worktree_digest="$(git -C "${OMNIVOX_DIR}" diff --binary HEAD -- | \
	sha256sum | cut -d ' ' -f1)"
cargo_lock_digest="$(sha256sum "${OMNIVOX_DIR}/Cargo.lock" | cut -d ' ' -f1)"
toolchain_lock_digest="$(sha256sum "${OMNIVOX_RELEASE_DIR}/toolchain.lock" | cut -d ' ' -f1)"
dockerfile_digest="$(sha256sum "${OMNIVOX_RELEASE_DIR}/Dockerfile" | cut -d ' ' -f1)"
release_image_id="$(docker image inspect --format '{{.Id}}' "${OMNIVOX_RELEASE_IMAGE}")"
rustc_version="$(docker run --rm --platform linux/amd64 \
	"${OMNIVOX_RELEASE_IMAGE}" rustc --version)"
mingw_version="$(docker run --rm --platform linux/amd64 \
	"${OMNIVOX_RELEASE_IMAGE}" \
	x86_64-w64-mingw32-gcc-win32 --version | sed -n '1p')"
csc_digest="$(sha256sum "${OMNIVOX_CSC}" | cut -d ' ' -f1)"
windows_csc="$(wslpath -m "${OMNIVOX_CSC}")"
csc_version="$(powershell.exe -NoProfile -NonInteractive -Command \
	"& '$windows_csc' /version" | tr -d '\r')"
executable_digest="$(sha256sum "$executable" | cut -d ' ' -f1)"
unstripped_digest="$(sha256sum "$unstripped_executable" | cut -d ' ' -f1)"
eloquence_runtime_digest=external-not-observed
if [ -n "${OMNIVOX_ECI_DLL:-}" ]; then
	eci_file="$OMNIVOX_ECI_DLL"
	if [ ! -f "$eci_file" ]; then
		eci_file="$(wslpath -u "$OMNIVOX_ECI_DLL")"
	fi
	if [ ! -f "$eci_file" ]; then
		echo "OMNIVOX_ECI_DLL does not identify a readable file" >&2
		exit 1
	fi
	eloquence_runtime_digest="$(sha256sum "$eci_file" | cut -d ' ' -f1)"
fi
build_id="$( {
	sha256sum "$executable" "$eloquence_helper" "$dectalk_helper" \
		"$helper_license" "$omnivox_license" \
		"$stdlib" "$gcc_runtime" | cut -d ' ' -f1
	printf '%s\n' "$rhvoice_companion_digest" \
		"$flite_companion_digest" \
		"$rutts_companion_digest" \
		"$tgspeechbox_companion_digest" \
		"$tgspeechbox_cxx" \
		"$tgspeechbox_cxx_digest"
	if [ -f "$dectalk_dll" ] && [ -f "$dectalk_dictionary" ]; then
		sha256sum "$dectalk_dll" "$dectalk_dictionary" | cut -d ' ' -f1
	else
		printf '%s\n' no-dectalk-runtime
	fi
	printf '%s\n' "$data_digest" "$emacsvox_commit" \
		"$omnivox_commit" "$build_kind" \
		"$emacsvox_worktree_digest" "$omnivox_worktree_digest" \
		"$cargo_lock_digest" \
		"$toolchain_lock_digest" "$dockerfile_digest" \
		"$release_image_id" "$csc_digest" \
		"${roslyn_nupkg_sha256}" \
		"${reference_assemblies_nupkg_sha256}" \
		"$eloquence_runtime_digest" \
		"${OMNIVOX_INCLUDE_PINNED_PIPER}" \
		"${OMNIVOX_INCLUDE_TGSPEECHBOX}" \
		"${OMNIVOX_PIPER_COMPANION_STATE}" \
		"${OMNIVOX_PIPER_COMPANION_VERSION}" \
		"${OMNIVOX_PIPER_COMPANION_COMMIT}" \
		"${OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256}" \
		"$piper_companion_digest" \
		"$piper_model_digest" \
		"$rhvoice_configuration_state" \
		"$rhvoice_library_digest" "$rhvoice_data_digest" \
		"$rhvoice_config_digest" \
		"$rhvoice_library_windows_path" \
		"$rhvoice_data_windows_path" \
		"$rhvoice_config_windows_path"
} | sha256sum | cut -c1-16)"
version_dir="${OMNIVOX_RUNTIME_DIR}/versions/$build_id"
diagnostics_dir="${OMNIVOX_RELEASE_DIR}/cache/diagnostics/$build_id"
windows_runtime_dir="$(wslpath -u "$windows_local_app_data")/Emacsvox/Omnivox/runtime/$build_id"
mkdir -p "$diagnostics_dir"
cp "$unstripped_executable" \
	"$diagnostics_dir/omnivox.unstripped.exe.new"
mv -f "$diagnostics_dir/omnivox.unstripped.exe.new" \
	"$diagnostics_dir/omnivox.unstripped.exe"
{
	printf '%s\n' \
		'format=emacsvox-omnivox-local-diagnostics-v1' \
		"build_id=$build_id" \
		"emacsvox_commit=$emacsvox_commit" \
		"omnivox_commit=$omnivox_commit" \
		"build_kind=$build_kind" \
		"emacsvox_worktree_sha256=$emacsvox_worktree_digest" \
		"omnivox_worktree_sha256=$omnivox_worktree_digest" \
		"deployed_omnivox_sha256=$executable_digest" \
		"unstripped_omnivox_sha256=$unstripped_digest"
} > "$diagnostics_dir/MANIFEST.new"
mv -f "$diagnostics_dir/MANIFEST.new" \
	"$diagnostics_dir/MANIFEST"
mkdir -p "$version_dir"
install_payload() {
	payload_source=$1
	payload_destination=$2
	payload_mode=$3
	if [ ! -f "$payload_destination" ]; then
		cp "$payload_source" "$payload_destination.new"
		mv -f "$payload_destination.new" "$payload_destination"
	fi
	if ! cmp -s "$payload_source" "$payload_destination"; then
		echo "Existing content-addressed payload differs: $payload_destination" >&2
		exit 1
	fi
	if [ "$payload_mode" = executable ]; then
		chmod +x "$payload_destination"
	fi
}
install_payload "$executable" "$version_dir/omnivox.exe" executable
install_payload "$stdlib" "$version_dir/libstdc++-6.dll" regular
install_payload "$gcc_runtime" \
	"$version_dir/libgcc_s_seh-1.dll" regular
install_payload "$eloquence_helper" \
	"$version_dir/OmnivoxEloquenceHelper32.exe" executable
install_payload "$dectalk_helper" \
	"$version_dir/OmnivoxDectalkHelper32.exe" executable
install_payload "$helper_license" \
	"$version_dir/WINDOWS-HELPERS-COPYING" regular
install_payload "$omnivox_license" \
	"$version_dir/OMNIVOX-LICENSE" regular
if [ -f "$dectalk_dll" ] && [ -f "$dectalk_dictionary" ]; then
	install_payload "$dectalk_dll" \
		"$version_dir/DECtalk.dll" regular
	install_payload "$dectalk_dictionary" \
		"$version_dir/dtalk_us.dic" regular
fi
stage_companion() {
	companion_name=$1
	companion_source=$2
	expected_companion_digest=$3
	if [ ! -d "$version_dir/$companion_name" ]; then
		companion_stage="$version_dir/$companion_name.new.$$"
		cp -a "$companion_source" "$companion_stage"
		mv "$companion_stage" "$version_dir/$companion_name"
	fi
	version_companion_digest="$(cd "$version_dir/$companion_name" && \
		find . -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
	if [ "$version_companion_digest" != "$expected_companion_digest" ]; then
		echo "Staged $companion_name companion does not match its build output" >&2
		exit 1
	fi
}
stage_companion rhvoice "$rhvoice_companion" \
	"$rhvoice_companion_digest"
stage_companion flite "$flite_companion" \
	"$flite_companion_digest"
stage_companion rutts "$rutts_companion" \
	"$rutts_companion_digest"
if [ "${OMNIVOX_INCLUDE_TGSPEECHBOX}" = 1 ]; then
	stage_companion tgspeechbox "$tgspeechbox_companion" \
		"$tgspeechbox_companion_digest"
fi
if [ "${OMNIVOX_INCLUDE_PINNED_PIPER}" = 1 ]; then
	if [ ! -d "$version_dir/piper" ]; then
		piper_stage="$version_dir/piper.new.$$"
		cp -a "$piper_companion" "$piper_stage"
		mv "$piper_stage" "$version_dir/piper"
	fi
	version_piper_digest="$(cd "$version_dir/piper" && \
		find . -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
	if [ "$version_piper_digest" != "$piper_companion_digest" ]; then
		echo "Staged Piper companion does not match its pinned input" >&2
		exit 1
	fi
fi
if [ ! -f "$version_dir/espeak-ng-data/phontab" ]; then
	rm -rf "$version_dir/espeak-ng-data.new"
	cp -a "$espeak_data" "$version_dir/espeak-ng-data.new"
	mv "$version_dir/espeak-ng-data.new" \
		"$version_dir/espeak-ng-data"
fi
version_data_digest="$(cd "$version_dir/espeak-ng-data" && \
	find . -type f -print0 | LC_ALL=C sort -z | \
	xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"
if [ "$version_data_digest" != "$data_digest" ]; then
	echo "Staged eSpeak data does not match its build input" >&2
	exit 1
fi
printf '%s\n' "$windows_cache_path" \
	> "$version_dir/espeak-ng-data.path.new"
mv -f "$version_dir/espeak-ng-data.path.new" \
	"$version_dir/espeak-ng-data.path"
if [ -n "$rhvoice_library_windows_path" ]; then
	printf '%s\n' "$rhvoice_library_windows_path" \
		> "$version_dir/rhvoice-library.path.new"
	mv -f "$version_dir/rhvoice-library.path.new" \
		"$version_dir/rhvoice-library.path"
	printf '%s\n' "$rhvoice_data_windows_path" \
		> "$version_dir/rhvoice-data.path.new"
	mv -f "$version_dir/rhvoice-data.path.new" \
		"$version_dir/rhvoice-data.path"
	if [ -n "$rhvoice_config_windows_path" ]; then
		printf '%s\n' "$rhvoice_config_windows_path" \
			> "$version_dir/rhvoice-config.path.new"
		mv -f "$version_dir/rhvoice-config.path.new" \
			"$version_dir/rhvoice-config.path"
	fi
fi
if [ -n "$piper_model_windows_path" ]; then
	printf '%s\n' "$piper_model_windows_path" \
		> "$version_dir/piper-model.path.new"
	mv -f "$version_dir/piper-model.path.new" \
		"$version_dir/piper-model.path"
	printf '%s\n' "$piper_model_config_windows_path" \
		> "$version_dir/piper-model-config.path.new"
	mv -f "$version_dir/piper-model-config.path.new" \
		"$version_dir/piper-model-config.path"
fi
dectalk_runtime=not-bundled
if [ -f "$version_dir/DECtalk.dll" ] && \
	[ -f "$version_dir/dtalk_us.dic" ]; then
	dectalk_runtime=bundled-pinned-archive
fi
omnivox_features=none
piper_companion_state=not-included
piper_version=not-included
piper_commit=not-included
piper_archive_digest=not-included
if [ "${OMNIVOX_INCLUDE_PINNED_PIPER}" = 1 ]; then
	omnivox_features=piper
	piper_companion_state=${OMNIVOX_PIPER_COMPANION_STATE}
	piper_version=${OMNIVOX_PIPER_COMPANION_VERSION}
	piper_commit=${OMNIVOX_PIPER_COMPANION_COMMIT}
	piper_archive_digest=${OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256}
fi
tgspeechbox_companion_state=not-included
tgspeechbox_target=not-included
tgspeechbox_markers=not-included
tgspeechbox_rate_mapping=not-included
if [ "${OMNIVOX_INCLUDE_TGSPEECHBOX}" = 1 ]; then
	tgspeechbox_companion_state=local-omnivox-experimental-build
	tgspeechbox_target=${OMNIVOX_TARGET}
	tgspeechbox_markers=exact_requested_anchors
	tgspeechbox_rate_mapping=calibrated_eloquence_v1
fi
{
	printf '%s\n' \
		'format=emacsvox-omnivox-provenance-v1' \
		"build_id=$build_id" \
		"emacsvox_commit=$emacsvox_commit" \
		"omnivox_commit=$omnivox_commit" \
		"build_kind=$build_kind" \
		"emacsvox_worktree_sha256=$emacsvox_worktree_digest" \
		"omnivox_worktree_sha256=$omnivox_worktree_digest" \
		"cargo_lock_sha256=$cargo_lock_digest" \
		"toolchain_lock_sha256=$toolchain_lock_digest" \
		"dockerfile_sha256=$dockerfile_digest" \
		"release_image_id=$release_image_id" \
		"rustc=$rustc_version" \
		"mingw_gcc=$mingw_version" \
		"roslyn_csc=$csc_version" \
		"roslyn_csc_sha256=$csc_digest" \
		"roslyn_nupkg_sha256=${roslyn_nupkg_sha256}" \
		"net40_reference_assemblies_nupkg_sha256=${reference_assemblies_nupkg_sha256}" \
		"target=${OMNIVOX_TARGET}" \
		"omnivox_features=$omnivox_features" \
		"windows_rustflags=-C link-arg=-Wl,--no-insert-timestamp" \
		"windows_strip=SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all" \
		"omnivox_executable_sha256=$executable_digest" \
		"unstripped_diagnostics=retained-local-not-staged" \
		"espeak_data_sha256=$data_digest" \
		'rhvoice_companion=local-omnivox-build' \
		"rhvoice_companion_tree_sha256=$rhvoice_companion_digest" \
		'rhvoice_runtime=external-user-supplied-not-bundled' \
		"rhvoice_configuration=$rhvoice_configuration_state" \
		"rhvoice_library_sha256=$rhvoice_library_digest" \
		"rhvoice_data_tree_sha256=$rhvoice_data_digest" \
		"rhvoice_config_tree_sha256=$rhvoice_config_digest" \
		'flite_companion=local-omnivox-build' \
		"flite_companion_tree_sha256=$flite_companion_digest" \
		'flite_target=x86_64-pc-windows-gnu' \
		'flite_compiled_voice=cmu_us_slt' \
		'rutts_companion=local-omnivox-build' \
		"rutts_companion_tree_sha256=$rutts_companion_digest" \
		'rutts_target=x86_64-pc-windows-gnu' \
		'rutts_version=6.3.3' \
		'rutts_built_in_voices=male,female' \
		'rutts_rulex=not-included' \
		"tgspeechbox_companion=$tgspeechbox_companion_state" \
		"tgspeechbox_companion_tree_sha256=$tgspeechbox_companion_digest" \
		"tgspeechbox_target=$tgspeechbox_target" \
		"tgspeechbox_markers=$tgspeechbox_markers" \
		"tgspeechbox_rate_mapping=$tgspeechbox_rate_mapping" \
		"tgspeechbox_build_environment=$tgspeechbox_build_environment" \
		"tgspeechbox_cxx=$tgspeechbox_cxx" \
		"tgspeechbox_cxx_sha256=$tgspeechbox_cxx_digest" \
		"piper_companion=$piper_companion_state" \
		"piper_companion_version=$piper_version" \
		"piper_companion_commit=$piper_commit" \
		"piper_companion_archive_sha256=$piper_archive_digest" \
		"piper_companion_tree_sha256=$piper_companion_digest" \
		"piper_model=$piper_model_state" \
		"piper_model_sha256=$piper_model_sha256" \
		"piper_model_config_sha256=$piper_model_config_sha256" \
		"eloquence_runtime=external-user-supplied-not-bundled" \
		"eloquence_runtime_sha256=$eloquence_runtime_digest" \
		"dectalk_runtime=$dectalk_runtime" \
		'windows_helpers_source=omnivox' \
		'windows_helpers_license=GPL-2.0-or-later'
} > "$version_dir/PROVENANCE.new"
mv -f "$version_dir/PROVENANCE.new" "$version_dir/PROVENANCE"
payload_files='omnivox.exe libstdc++-6.dll libgcc_s_seh-1.dll OmnivoxEloquenceHelper32.exe OmnivoxDectalkHelper32.exe WINDOWS-HELPERS-COPYING OMNIVOX-LICENSE PROVENANCE'
if [ "$dectalk_runtime" = bundled-pinned-archive ]; then
	payload_files="$payload_files DECtalk.dll dtalk_us.dic"
fi
(
	cd "$version_dir"
	sha256sum $payload_files
	find rhvoice flite rutts -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum
	if [ "${OMNIVOX_INCLUDE_TGSPEECHBOX}" = 1 ]; then
		find tgspeechbox -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum
	fi
	if [ "${OMNIVOX_INCLUDE_PINNED_PIPER}" = 1 ]; then
		find piper -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum
	fi
) > "$version_dir/SHA256SUMS.new"
mv -f "$version_dir/SHA256SUMS.new" "$version_dir/SHA256SUMS"
(cd "$version_dir" && sha256sum --check SHA256SUMS)
mkdir -p "$windows_runtime_dir"
if [ ! -f "$windows_runtime_dir/SHA256SUMS" ]; then
	cp "$version_dir/SHA256SUMS" \
		"$windows_runtime_dir/SHA256SUMS.new.$$"
	mv "$windows_runtime_dir/SHA256SUMS.new.$$" \
		"$windows_runtime_dir/SHA256SUMS"
fi
if ! cmp -s "$version_dir/SHA256SUMS" \
	"$windows_runtime_dir/SHA256SUMS"; then
	echo "Existing Windows-local SHA256SUMS differs" >&2
	exit 1
fi
while read -r _checksum runtime_file; do
	runtime_destination="$windows_runtime_dir/$runtime_file"
	mkdir -p "${runtime_destination%/*}"
	if [ ! -f "$runtime_destination" ]; then
		cp "$version_dir/$runtime_file" \
			"$runtime_destination.new.$$"
		mv "$runtime_destination.new.$$" \
			"$runtime_destination"
	fi
	if ! cmp -s "$version_dir/$runtime_file" \
		"$runtime_destination"; then
		echo "Existing Windows-local payload differs: $runtime_destination" >&2
		exit 1
	fi
done < "$version_dir/SHA256SUMS"
windows_runtime_path="$(wslpath -w "$windows_runtime_dir")"
printf '%s\n' "$windows_runtime_path" \
	> "$version_dir/windows-runtime.path.new"
mv -f "$version_dir/windows-runtime.path.new" \
	"$version_dir/windows-runtime.path"
ln -sfn "versions/$build_id" "${OMNIVOX_RUNTIME_DIR}/current.new"
mv -Tf "${OMNIVOX_RUNTIME_DIR}/current.new" \
	"${OMNIVOX_RUNTIME_DIR}/current"
chmod +x "${EMACSVOX_STAGE_ROOT}/servers/omnivox"
echo "Staged Omnivox runtime $build_id"
