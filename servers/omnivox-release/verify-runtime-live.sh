#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 OMNIVOX_RUNTIME_DIR OMNIVOX_RELEASE_DIR" >&2
    exit 2
fi

runtime_root=$1
release_root=$2
current=$(readlink -f -- "$runtime_root/current")
versions_root=$(readlink -f -- "$runtime_root/versions")
case "$current/" in
    "$versions_root"/*/) ;;
    *)
        echo "Omnivox current does not resolve below $versions_root" >&2
        exit 1
        ;;
esac

launcher=$release_root/../omnivox
if [ ! -x "$launcher" ]; then
    echo "Omnivox launcher is not executable: $launcher" >&2
    exit 1
fi

windows_runtime_path=$(sed -n '1p' "$current/windows-runtime.path")
windows_runtime=$(wslpath -u "$windows_runtime_path")
windows_program=$windows_runtime/omnivox.exe
if [ ! -x "$windows_program" ]; then
    echo "Windows-local Omnivox is not executable: $windows_program" >&2
    exit 1
fi
espeak_data_path=$(sed -n '1p' "$current/espeak-ng-data.path")
espeak_cache=$(wslpath -u "$espeak_data_path")/omnivox-espeak-voices-v1.json

windows_temp_path=$(
    powershell.exe -NoProfile -NonInteractive -Command \
        '[IO.Path]::GetTempPath()' | tr -d '\r'
)
windows_temp=$(wslpath -u "$windows_temp_path")
smoke_directory=$(mktemp -d "$windows_temp/emacsvox-omnivox-live.XXXXXX")
log_directory=$(mktemp -d)
cleanup()
{
    find "$smoke_directory" -mindepth 1 -maxdepth 1 -type f -delete
    rmdir "$smoke_directory"
    find "$log_directory" -mindepth 1 -maxdepth 1 -type f -delete
    rmdir "$log_directory"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

run_staged()
{
    env -u OMNIVOX_FLITE_HELPER -u OMNIVOX_FLITE_VOICES \
        -u OMNIVOX_RUTTS_HELPER \
        -u OMNIVOX_TGSPEECHBOX_HELPER -u OMNIVOX_TGSPEECHBOX_DATA \
        -u OMNIVOX_TGSPEECHBOX_SAMPLE_RATE \
        OMNIVOX_PROGRAM="$windows_program" \
        OMNIVOX_LOG_DIRECTORY="$log_directory" \
        ESPEAK_NG_DATA="$espeak_data_path" \
        "$launcher" "$@"
}

run_staged_tgspeechbox()
{
    sample_rate=$1
    shift
    env -u OMNIVOX_FLITE_HELPER -u OMNIVOX_FLITE_VOICES \
        -u OMNIVOX_RUTTS_HELPER \
        -u OMNIVOX_TGSPEECHBOX_HELPER -u OMNIVOX_TGSPEECHBOX_DATA \
        OMNIVOX_TGSPEECHBOX_SAMPLE_RATE="$sample_rate" \
        OMNIVOX_PROGRAM="$windows_program" \
        OMNIVOX_LOG_DIRECTORY="$log_directory" \
        ESPEAK_NG_DATA="$espeak_data_path" \
        "$launcher" "$@"
}

espeak_voices=$(run_staged --engine espeak --list-voices-alist)
if ! printf '%s\n' "$espeak_voices" |
    grep -Fq '("espeak:gmw\\en-US" "English (America)" "en-us" "Compact")'; then
    echo "Staged eSpeak did not report its default English voice" >&2
    exit 1
fi
if [ ! -f "$espeak_cache" ] || [ "$(wc -c < "$espeak_cache")" -gt 1048576 ]; then
    echo "Staged eSpeak did not create a bounded voice cache: $espeak_cache" >&2
    exit 1
fi

flite_voices=$(run_staged --engine flite --list-voices-alist)
if ! printf '%s\n' "$flite_voices" |
    grep -Fq '("cmu_us_slt" "cmu_us_slt" "en-US" "Compact")'; then
    echo "Staged Flite helper did not report cmu_us_slt" >&2
    exit 1
fi

rutts_voices=$(run_staged --engine rutts --list-voices-alist)
for voice in \
    '("male" "RuTTS Male" "ru-RU" "Compact")' \
    '("female" "RuTTS Female" "ru-RU" "Compact")'; do
    if ! printf '%s\n' "$rutts_voices" | grep -Fq "$voice"; then
        echo "Staged RuTTS helper did not report $voice" >&2
        exit 1
    fi
done

flite_wav=$smoke_directory/flite.wav
rutts_wav=$smoke_directory/rutts.wav
companion_wavs="$flite_wav $rutts_wav"
run_staged --engine flite --dump-wav cmu_us_slt \
    "$(wslpath -w "$flite_wav")" "Flite is ready." >/dev/null
run_staged --engine rutts --dump-wav male \
    "$(wslpath -w "$rutts_wav")" "Привет, мир!" >/dev/null

tgspeechbox_companion_state=$(
    sed -n 's/^tgspeechbox_companion=//p' "$current/PROVENANCE"
)
case "$tgspeechbox_companion_state" in
    local-omnivox-experimental-build)
        for sample_rate in 44100 22050; do
            tgspeechbox_voices=$(
                run_staged_tgspeechbox "$sample_rate" \
                    --engine tgspeechbox --list-voices-alist
            )
            for voice in \
                '("en-us/beth" "TGSpeechBox Beth (en-us)" "en-us" "Compact")' \
                '("en-us/bobby" "TGSpeechBox Bobby (en-us)" "en-us" "Compact")'; do
                if ! printf '%s\n' "$tgspeechbox_voices" | grep -Fq "$voice"; then
                    echo "Staged TGSpeechBox helper at $sample_rate Hz did not report $voice" >&2
                    exit 1
                fi
            done
            tgspeechbox_wav=$smoke_directory/tgspeechbox-$sample_rate.wav
            run_staged_tgspeechbox "$sample_rate" \
                --engine tgspeechbox --dump-wav en-us/beth \
                "$(wslpath -w "$tgspeechbox_wav")" \
                "TG Speech Box is ready." >/dev/null
            companion_wavs="$companion_wavs $tgspeechbox_wav"
        done
        live_tgspeechbox_voice=en-us/beth
        live_tgspeechbox_sample_rates=44100,22050
        ;;
    not-included)
        live_tgspeechbox_voice=not-included
        live_tgspeechbox_sample_rates=not-included
        ;;
    *)
        echo "Unknown TGSpeechBox companion state: $tgspeechbox_companion_state" >&2
        exit 1
        ;;
esac

for wav in $companion_wavs; do
    if [ ! -f "$wav" ] || [ "$(wc -c < "$wav")" -le 44 ] ||
       [ "$(dd if="$wav" bs=1 count=4 2>/dev/null)" != RIFF ]; then
        echo "Staged companion did not create valid WAV output: $wav" >&2
        exit 1
    fi
done

printf '%s\n' \
    "live_espeak_cache=$espeak_cache" \
    'live_flite_voice=cmu_us_slt' \
    'live_rutts_voices=male,female' \
    "live_tgspeechbox_voice=$live_tgspeechbox_voice" \
    "live_tgspeechbox_sample_rates=$live_tgspeechbox_sample_rates" \
    "live_runtime=$windows_runtime"
