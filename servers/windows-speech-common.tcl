# Copyright (C) 2026 Bart Bunting
# SPDX-License-Identifier: GPL-2.0-or-later
#
# This file is not part of GNU Emacs, but the same permissions apply.
# See the file COPYING in this distribution.

# Shared persistent line protocol for native Windows speech bridges.

proc windows_speech_source_tts_library {server_directory} {
    global env
    set candidates [list [file join $server_directory tts-lib.tcl]]
    if {[info exists env(EMACSVOX_DIR)] &&
        $env(EMACSVOX_DIR) ne ""} {
        lappend candidates \
            [file join $env(EMACSVOX_DIR) servers tts-lib.tcl]
    }
    foreach candidate $candidates {
        if {[file isfile $candidate]} {
            uplevel #0 [list source $candidate]
            return [file normalize $candidate]
        }
    }
    error "Emacsvox tts-lib.tcl not found; set EMACSVOX_DIR to the Emacsvox root"
}

proc windows_speech_export_to_windows {name} {
    global env
    set entries {}
    if {[info exists env(WSLENV)] && $env(WSLENV) ne ""} {
        foreach entry [split $env(WSLENV) :] {
            if {[lindex [split $entry /] 0] ne $name} {
                lappend entries $entry
            }
        }
    }
    lappend entries "$name/w"
    set env(WSLENV) [join $entries :]
}

proc windows_speech_pipe_command {program arguments {wsl_init auto}} {
    if {$wsl_init eq "auto"} {
        set wsl_init ""
        if {[file executable /init]} {
            set wsl_init /init
        }
    }
    set command [list |]
    if {$wsl_init ne ""} {
        # Match binfmt_misc's preserve-argv[0] invocation of WSL's /init.
        lappend command $wsl_init $program $program
    } else {
        lappend command $program
    }
    foreach argument $arguments {
        lappend command $argument
    }
    return $command
}

proc windows_speech_start {state_name description program arguments} {
    global env
    upvar #0 $state_name state
    foreach name {
        EMACSVOX_WINDOWS_SPEECH_PAN
        EMACSVOX_WINDOWS_SPEECH_RPC_TIMEOUT_MS
        EMACSVOX_WINDOWS_SPEECH_SYNC_TIMEOUT_MS
    } {
        if {[info exists env($name)] && $env($name) ne ""} {
            windows_speech_export_to_windows $name
        }
    }
    set command [windows_speech_pipe_command $program $arguments]
    set state(description) $description
    set state(channel) [open $command r+]
    fconfigure $state(channel) \
        -blocking 1 -buffering line -encoding ascii -translation crlf
}

proc windows_speech_decode_error {payload description} {
    if {$payload eq ""} {
        return "Unknown $description error"
    }
    return [encoding convertfrom utf-8 [binary decode base64 $payload]]
}

proc windows_speech_rpc {state_name request} {
    upvar #0 $state_name state
    set channel $state(channel)
    puts $channel $request
    flush $channel
    if {[gets $channel response] < 0} {
        puts stderr "$state(description) closed unexpectedly"
        flush stderr
        catch {close $channel}
        unset -nocomplain state(channel)
        exit 1
    }
    if {$response eq "OK"} {
        return ""
    }
    if {[string match "OK *" $response]} {
        return [string range $response 3 end]
    }
    if {[string match "ERR *" $response]} {
        error [windows_speech_decode_error \
                   [string range $response 4 end] $state(description)]
    }
    if {[string match "FATAL *" $response]} {
        set error [windows_speech_decode_error \
                       [string range $response 6 end] $state(description)]
        puts stderr $error
        flush stderr
        catch {close $channel}
        unset -nocomplain state(channel)
        exit 1
    }
    error "Invalid response from $state(description): $response"
}

proc windows_speech_text_rpc {state_name command text} {
    set bytes [encoding convertto utf-8 $text]
    set payload [binary encode base64 -maxlen 0 $bytes]
    return [windows_speech_rpc $state_name "$command $payload"]
}

proc windows_speech_input_channel {} {
    global tts
    if {[info exists tts(input)] && $tts(input) ne ""} {
        return $tts(input)
    }
    return stdin
}

proc windows_speech_input_pending {{channel stdin}} {
    if {[chan pending input $channel] > 0} {
        return 1
    }
    if {[llength [info commands select]] > 0} {
        return [expr {
            [lsearch [select [list $channel] {} {} 0] $channel] >= 0
        }]
    }
    return 0
}

proc windows_speech_transaction_fields {line} {
    if {[catch {set fields [lrange $line 0 end]}]} {
        return ""
    }
    if {[llength $fields] != 3 ||
        [lindex $fields 0] ne "emacsvox_tx" ||
        ![string is integer -strict [lindex $fields 1]]} {
        return ""
    }
    return [lrange $fields 1 2]
}

proc windows_speech_evaluate_transaction {generation payload} {
    global windows_speech_transaction
    set windows_speech_transaction(latest) $generation
    set script [encoding convertfrom utf-8 [binary decode base64 $payload]]
    foreach command [split $script "\n"] {
        if {$command ne ""} {
            uplevel #0 $command
        }
    }
    return ""
}

proc emacsvox_tx {generation payload} {
    global windows_speech_transaction
    if {![string is integer -strict $generation]} {
        error "invalid Emacsvox transaction generation: $generation"
    }
    if {[info exists windows_speech_transaction(latest)] &&
        $generation <= $windows_speech_transaction(latest)} {
        return ""
    }

    set selected_generation $generation
    set selected_payload $payload
    set input [windows_speech_input_channel]
    # Look ahead only through consecutive framed transactions.  Since gets
    # consumes the first ordinary line, deliver the selected packet and then
    # evaluate that ordering barrier here before returning to commandloop.
    while {[windows_speech_input_pending $input]} {
        if {[gets $input line] < 0} {
            break
        }
        set fields [windows_speech_transaction_fields $line]
        if {$fields eq ""} {
            windows_speech_evaluate_transaction \
                $selected_generation $selected_payload
            uplevel #0 $line
            return ""
        }
        lassign $fields next_generation next_payload
        if {$next_generation > $selected_generation} {
            set selected_generation $next_generation
            set selected_payload $next_payload
        }
    }
    windows_speech_evaluate_transaction \
        $selected_generation $selected_payload
    return ""
}

proc windows_speech_native_audio_player_p {program} {
    expr {[file tail $program] eq "windows-play"}
}

proc windows_speech_queue_sound {program sound} {
    if {[windows_speech_native_audio_player_p $program]} {
        # Wait until the persistent native player has accepted the cue.  This
        # preserves protocol order without waiting for playback to finish.
        exec $program $sound > /dev/null
    } else {
        exec $program $sound > /dev/null &
    }
}

proc windows_speech_cancel_sounds {program} {
    if {[windows_speech_native_audio_player_p $program]} {
        exec $program --cancel > /dev/null
    }
}
