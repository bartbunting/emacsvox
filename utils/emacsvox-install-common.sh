# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Shared per-user Emacs acquisition for the guided installers.
# Callers provide fail/note, the trusted manifest, checkout/cache/install paths,
# cleanup_build_directory and its trap, and optionally emacs_build_kind.
# shellcheck shell=sh disable=SC2034,SC2154

validate_hash()
{
    case $1 in
        ''|*[!0123456789abcdef]*)
            fail "release manifest contains an invalid SHA-256 value"
            ;;
    esac
    [ "${#1}" -eq 64 ] ||
        fail "release manifest contains an invalid SHA-256 length"
}

emacs_version()
{
    "$1" -Q --batch --eval '(princ emacs-version)' 2>/dev/null
}

resolve_emacs()
{
    emacs_candidate=
    emacs_selection=
    if [ "${EMACS+x}" = x ] && [ -n "$EMACS" ]; then
        emacs_candidate=$EMACS
        emacs_selection='EMACS environment variable'
    elif [ -r "$emacsvox_root/local.mk" ]; then
        emacs_candidate=$(
            sed -n \
                '/^[[:space:]]*EMACS[[:space:]]*=/ { s/^[[:space:]]*EMACS[[:space:]]*=[[:space:]]*//; s/[[:space:]]*$//; p; }' \
                "$emacsvox_root/local.mk" | sed -n '$p'
        )
        if [ -n "$emacs_candidate" ]; then
            emacs_selection=local.mk
        fi
    fi
    if [ -z "$emacs_candidate" ]; then
        emacs_candidate=$(command -v emacs 2>/dev/null || :)
        emacs_selection=PATH
    fi
    case $emacs_candidate in
        /*|'') ;;
        */*) emacs_candidate=$emacsvox_root/$emacs_candidate ;;
        *) emacs_candidate=$(command -v "$emacs_candidate" 2>/dev/null || :) ;;
    esac
    selected_emacs_version=
    if [ -n "$emacs_candidate" ] && [ -x "$emacs_candidate" ]; then
        selected_emacs_version=$(emacs_version "$emacs_candidate" || :)
    fi
    selected_emacs_major=${selected_emacs_version%%.*}
    case $selected_emacs_major in
        ''|*[!0-9]*) emacs_supported=false ;;
        *)
            if [ "$selected_emacs_major" -ge 31 ]; then
                emacs_supported=true
            else
                emacs_supported=false
            fi
            ;;
    esac
}

download_verified()
{
    url=$1
    destination=$2
    expected=$3
    mkdir -p -- "$(dirname -- "$destination")"
    if [ -f "$destination" ] &&
       printf '%s  %s\n' "$expected" "$destination" | sha256sum --check --status -;
    then
        printf 'Using verified cached download: %s\n' "$destination"
        return
    fi
    temporary=$destination.part.$$
    curl --fail --location --retry 3 --show-error --silent \
        --output "$temporary" "$url"
    if ! printf '%s  %s\n' "$expected" "$temporary" |
         sha256sum --check --status -; then
        rm -f -- "$temporary"
        fail "checksum verification failed for $(basename -- "$destination")"
    fi
    mv -f -- "$temporary" "$destination"
}

install_emacs()
{
    if [ -x "$emacs_install_directory/bin/emacs" ]; then
        installed_version=$(emacs_version "$emacs_install_directory/bin/emacs" || :)
        if [ "$installed_version" = "$EMACSVOX_WSL_EMACS_VERSION" ]; then
            emacs_candidate=$emacs_install_directory/bin/emacs
            selected_emacs_version=$installed_version
            emacs_supported=true
            printf 'Using existing GNU Emacs %s installation.\n' "$installed_version"
            return
        fi
        fail "existing Emacs installation is not the pinned version: $emacs_install_directory"
    elif [ -e "$emacs_install_directory" ]; then
        fail "existing Emacs installation is incomplete: $emacs_install_directory"
    fi

    archive=$download_directory/$EMACSVOX_WSL_EMACS_ARCHIVE
    download_verified "$EMACSVOX_WSL_EMACS_URL" "$archive" \
        "$EMACSVOX_WSL_EMACS_SHA256"
    cleanup_build_directory=$(mktemp -d \
        "${TMPDIR:-/tmp}/emacsvox-emacs-$EMACSVOX_WSL_EMACS_VERSION.XXXXXX")
    tar -xf "$archive" -C "$cleanup_build_directory"
    source_directory=$cleanup_build_directory/emacs-$EMACSVOX_WSL_EMACS_VERSION
    [ -x "$source_directory/configure" ] ||
        fail "the verified Emacs archive has an unexpected layout"
    staging_directory=$cleanup_build_directory/stage
    mkdir -p -- "$staging_directory" "$(dirname -- "$emacs_install_directory")"
    log_directory=$cache_home/emacsvox/logs
    build_log=$log_directory/emacs-$EMACSVOX_WSL_EMACS_VERSION-build.log
    mkdir -p -- "$log_directory"
    : >"$build_log"
    chmod 600 "$build_log"
    note "Building GNU Emacs $EMACSVOX_WSL_EMACS_VERSION"
    jobs=2
    if command -v nproc >/dev/null 2>&1; then
        jobs=$(nproc)
    fi
    if ! (
        cd "$source_directory" &&
        if [ "${emacs_build_kind:-desktop}" = terminal ]; then
            set -- --without-x --without-sound --without-dbus --without-gsettings \
                --with-gnutls --with-xml2 --with-sqlite3
        else
            set -- --with-x-toolkit=gtk3 --with-sound=alsa
        fi
        ./configure \
            --prefix="$emacs_install_directory" \
            --with-tree-sitter --without-native-compilation "$@" &&
        make -j"$jobs" &&
        make install DESTDIR="$staging_directory"
    ) >"$build_log" 2>&1; then
        tail -n 30 "$build_log" >&2
        fail "GNU Emacs build failed; complete output is in $build_log"
    fi
    staged_install=$staging_directory$emacs_install_directory
    [ -x "$staged_install/bin/emacs" ] ||
        fail "the staged Emacs installation is incomplete"
    mv -- "$staged_install" "$emacs_install_directory"
    emacs_candidate=$emacs_install_directory/bin/emacs
    selected_emacs_version=$(emacs_version "$emacs_candidate") ||
        fail "the installed Emacs executable did not start"
    [ "$selected_emacs_version" = "$EMACSVOX_WSL_EMACS_VERSION" ] ||
        fail "installed Emacs reports unexpected version $selected_emacs_version"
    emacs_supported=true
    printf 'Installed GNU Emacs %s.\n' "$selected_emacs_version"
}

configure_local_emacs()
{
    local_settings=$emacsvox_root/local.mk
    if [ ! -e "$local_settings" ]; then
        temporary=$local_settings.tmp.$$
        printf 'EMACS=%s\n' "$emacs_candidate" >"$temporary"
        chmod 600 "$temporary"
        mv -- "$temporary" "$local_settings"
        printf 'Selected Emacs in %s.\n' "$local_settings"
        return
    fi
    configured=$(
        sed -n \
            '/^[[:space:]]*EMACS[[:space:]]*=/ { s/^[[:space:]]*EMACS[[:space:]]*=[[:space:]]*//; s/[[:space:]]*$//; p; }' \
            "$local_settings" | sed -n '$p'
    )
    if [ -z "$configured" ]; then
        printf '\nEMACS=%s\n' "$emacs_candidate" >>"$local_settings"
        printf 'Added the Emacs selection to existing %s.\n' "$local_settings"
    fi
}
