;;; emacsvox-windows-speech-tests.el --- Windows speech tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for native Windows speech server discovery and selection.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-windows-speech)

(defun emacsvox-windows-speech-tests--run-server-library (server script)
  "Source Windows speech SERVER and evaluate Tcl SCRIPT.
Return the server's standard output."
  (let ((path (expand-file-name server emacsvox-servers-directory)))
    (with-temp-buffer
      (insert
       (format
        (concat
         "set argv0 {%s}\n"
         "set emacsvox_windows_speech_library_mode 1\n"
         "source $argv0\n"
         "%s")
        path script))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (buffer-string))))

(ert-deftest emacsvox-windows-speech-resolves-friendly-server-name ()
  "Friendly server names resolve to launchers outside Emacsvox."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_file) t)))
      (should
       (equal
        (emacsvox-windows-speech--resolve-server-arguments
         '("windows-outloud"))
        '("/support/servers/windows-outloud"))))))

(ert-deftest emacsvox-windows-speech-leaves-other-server-names-alone ()
  "Bundled server names pass through without translation."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/"))
    (should
     (equal
      (emacsvox-windows-speech--resolve-server-arguments '("dtk-soft"))
      '("dtk-soft")))))

(ert-deftest emacsvox-windows-speech-rejects-unavailable-server ()
  "Selecting a configured but unavailable Windows server is explicit."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_file) nil)))
      (should-error
       (emacsvox-windows-speech--resolve-server-arguments
        '("windows-dtk"))
       :type 'user-error))))

(ert-deftest emacsvox-windows-speech-registers-only-available-servers ()
  "Completion includes only executable native Windows launchers."
  (let ((tts-servers-alist '("dtk-soft"))
        (emacsvox-windows-speech-servers-directory "/support/servers/")
        (emacsvox-windows-speech--added-server-names nil))
    (cl-letf (((symbol-function 'file-executable-p)
               (lambda (file)
                 (string-suffix-p "windows-outloud" file))))
      (emacsvox-windows-speech--register-server-names)
      (should
       (equal tts-servers-alist '("dtk-soft" "windows-outloud")))
      (should
       (equal emacsvox-windows-speech--added-server-names
              '("windows-outloud"))))))

(ert-deftest emacsvox-windows-speech-routes-generated-audio ()
  "Native audio configuration includes direct SoX-generated cues."
  (let ((process-environment (copy-sequence process-environment))
        (emacsvox-windows-speech-servers-directory "/support/servers/")
        (emacsvox-windows-speech--saved-audio-state nil)
        (emacsvox-play-program "/usr/bin/play")
        (ems--play-args "-q")
        (sox-play "/usr/bin/play"))
    (setenv "EMACSVOX_PLAY" nil)
    (setenv
     emacsvox-windows-speech--audio-scope-environment-variable nil)
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_file) t)))
      (should
       (equal
        (emacsvox-windows-speech-configure-audio)
        "/support/servers/windows-play"))
      (should-not emacsvox-play-program)
      (should-not ems--play-args)
      (should
       (equal sox-play "/support/servers/windows-play"))
      (should
       (equal
        (getenv "EMACSVOX_PLAY") "/support/servers/windows-play"))
      (should
       (string-suffix-p
        ":direct"
        (getenv
         emacsvox-windows-speech--audio-scope-environment-variable)))
      (emacsvox-windows-speech-restore-audio)
      (should (equal emacsvox-play-program "/usr/bin/play"))
      (should (equal ems--play-args "-q"))
      (should (equal sox-play "/usr/bin/play"))
      (should-not (getenv "EMACSVOX_PLAY"))
      (should-not
       (getenv
        emacsvox-windows-speech--audio-scope-environment-variable)))))

(ert-deftest emacsvox-windows-speech-can-restart-after-audio-change ()
  "A requested restart happens after audio routing is configured."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/")
        (emacsvox-windows-speech--saved-audio-state nil)
        restarted)
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_file) t))
              ((symbol-function 'tts-restart)
               (lambda ()
                 (should
                  (equal sox-play "/support/servers/windows-play"))
                 (setq restarted t))))
      (unwind-protect
          (progn
            (emacsvox-windows-speech-configure-audio t)
            (should restarted))
        (emacsvox-windows-speech-restore-audio)))))

(ert-deftest emacsvox-windows-speech-defaults-to-bundled-servers ()
  "The owned integration should use Emacsvox's server directory by default."
  (should
   (equal
    (file-truename emacsvox-windows-speech-servers-directory)
    (file-truename emacsvox-servers-directory))))

(ert-deftest emacsvox-windows-speech-recognizes-both-servers ()
  "Friendly and absolute Windows server names should be recognized."
  (dolist
      (program
       '("windows-outloud"
         "windows-dtk"
         "/tmp/servers/windows-outloud"
         "/tmp/servers/windows-dtk"))
    (should (emacsvox-windows-speech--server-p program)))
  (should-not (emacsvox-windows-speech--server-p "outloud"))
  (should-not (emacsvox-windows-speech--server-p nil)))

(ert-deftest emacsvox-windows-speech-enables-notification-streams ()
  "Both Windows servers should satisfy the multistream contract."
  (dolist
      (tts-program
       '("/tmp/servers/windows-outloud"
         "/tmp/servers/windows-dtk"))
    (let ((emacsvox-windows-speech-enable-notification-stream t)
          (tts-multi-engines '("outloud" "dtk-soft"))
          (tts-notification-device nil))
      (should
       (equal
        '("windows-default" t)
        (emacsvox-windows-speech--with-notification-stream
         (lambda (&rest _)
           (list
            tts-notification-device
            (and (tts-multistream-p tts-program) t)))))))))

(ert-deftest emacsvox-windows-speech-preserves-notification-device ()
  "A user-specified notification device should remain dynamically visible."
  (let ((tts-program "/tmp/servers/windows-dtk")
        (emacsvox-windows-speech-enable-notification-stream t)
        (tts-multi-engines '("outloud" "dtk-soft"))
        (tts-notification-device "named-device"))
    (should
     (equal
      "named-device"
      (emacsvox-windows-speech--with-notification-stream
       (lambda (&rest _) tts-notification-device))))))

(ert-deftest emacsvox-windows-speech-positions-native-streams ()
  "Main and notification processes should receive independent pan values."
  (let ((tts-program "/tmp/servers/windows-dtk")
        (emacsvox-windows-speech-main-pan 0.0)
        (emacsvox-windows-speech-notification-pan 0.65)
        (process-environment (copy-sequence process-environment)))
    (dolist (entry '(("Speaker" . 0.0) ("Notify" . 0.65)))
      (should
       (=
        (cdr entry)
        (emacsvox-windows-speech--with-stereo-position
         (lambda (&rest _)
           (string-to-number
            (getenv
             emacsvox-windows-speech--pan-environment-variable)))
         (car entry)))))))

(ert-deftest emacsvox-windows-speech-clamps-process-pan ()
  "Out-of-range custom pan values should be safely clamped."
  (let ((tts-program "/tmp/servers/windows-outloud")
        (emacsvox-windows-speech-main-pan -4.0)
        (emacsvox-windows-speech-notification-pan 3.0)
        (process-environment (copy-sequence process-environment)))
    (dolist (entry '(("Speaker" . -1.0) ("Notify" . 1.0)))
      (should
       (=
        (cdr entry)
        (emacsvox-windows-speech--with-stereo-position
         (lambda (&rest _)
           (string-to-number
            (getenv
             emacsvox-windows-speech--pan-environment-variable)))
         (car entry)))))))

(ert-deftest emacsvox-windows-speech-enables-framing-on-native-processes ()
  "Windows process creation marks both streams for transaction framing."
  (let ((tts-program "/tmp/servers/windows-outloud")
        marked)
    (cl-letf
        (((symbol-function 'processp)
          (lambda (process) (eq process 'native-process)))
         ((symbol-function 'emacsvox-aural-enable-framed-delivery)
          (lambda (process)
            (setq marked process)
            process)))
      (should
       (eq
        (emacsvox-windows-speech--with-stereo-position
         (lambda (&rest _arguments) 'native-process)
         "Speaker")
        'native-process))
      (should (eq marked 'native-process)))))

(ert-deftest emacsvox-windows-speech-enables-framing-on-existing-processes ()
  "Enabling integration configures compatible processes that started first."
  (let ((tts-speaker-process 'existing-speaker)
        (tts-notify-process 'existing-notifier)
        (emacsvox-windows-speech--enabled nil)
        marked)
    (cl-letf
        (((symbol-function 'processp)
          (lambda (process)
            (memq process '(existing-speaker existing-notifier))))
         ((symbol-function 'process-live-p) (lambda (_process) t))
         ((symbol-function 'process-command)
          (lambda (process)
            (list
             (if (eq process 'existing-speaker)
                 "/repo/servers/windows-outloud"
               "/repo/servers/windows-dtk"))))
         ((symbol-function 'emacsvox-aural-enable-framed-delivery)
          (lambda (process) (push process marked)))
         ((symbol-function 'emacsvox-windows-speech--register-server-names)
          #'ignore)
         ((symbol-function 'advice-member-p) (lambda (&rest _) t)))
      (emacsvox-windows-speech-enable))
    (should emacsvox-windows-speech--enabled)
    (should
     (equal
      (sort marked :key #'symbol-name)
      '(existing-notifier existing-speaker)))))

(ert-deftest emacsvox-windows-speech-does-not-frame-existing-other-server ()
  "Late integration does not apply its protocol to an unrelated process."
  (let ((tts-speaker-process 'existing-speaker)
        (tts-notify-process nil)
        marked)
    (cl-letf
        (((symbol-function 'processp)
          (lambda (process) (eq process 'existing-speaker)))
         ((symbol-function 'process-live-p) (lambda (_process) t))
         ((symbol-function 'process-command)
          (lambda (_process) '("/repo/servers/espeak")))
         ((symbol-function 'emacsvox-aural-enable-framed-delivery)
          (lambda (process) (push process marked))))
      (emacsvox-windows-speech--enable-existing-process-framing))
    (should-not marked)))

(ert-deftest emacsvox-windows-speech-isolates-main-and-notification-cues ()
  "Native speech streams receive distinct stable auditory-icon scopes."
  (let ((tts-program "/tmp/servers/windows-outloud")
        (process-environment (copy-sequence process-environment))
        scopes)
    (dolist (name '("Speaker" "Notify"))
      (push
       (emacsvox-windows-speech--with-stereo-position
        (lambda (&rest _arguments)
          (getenv
           emacsvox-windows-speech--audio-scope-environment-variable))
        name)
       scopes))
    (should (= (length (delete-dups (copy-sequence scopes))) 2))
    (should (cl-some (lambda (scope)
                       (string-suffix-p ":main" scope))
                     scopes))
    (should (cl-some (lambda (scope)
                       (string-suffix-p ":notification" scope))
                     scopes))))

(ert-deftest emacsvox-windows-speech-exports-pan-across-wsl ()
  "The Tcl launcher should export Emacsvox pan to its Windows child."
  (let ((common
         (expand-file-name
          "windows-speech-common.tcl"
          emacsvox-servers-directory))
        (process-environment (copy-sequence process-environment)))
    (setenv "WSLENV" "KEEP_ME/w:EMACSVOX_WINDOWS_SPEECH_PAN/u")
    (with-temp-buffer
      (insert
       (format
        (concat
         "source {%s}\n"
         "windows_speech_export_to_windows "
         "EMACSVOX_WINDOWS_SPEECH_PAN\n"
         "puts $env(WSLENV)\n")
        common))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (should
       (equal
        "KEEP_ME/w:EMACSVOX_WINDOWS_SPEECH_PAN/w\n"
        (buffer-string))))))

(ert-deftest emacsvox-windows-speech-builds-wsl-init-pipeline ()
  "The Tcl launcher should preserve argv zero when invoking WSL's init."
  (let ((common
         (expand-file-name
          "windows-speech-common.tcl"
          emacsvox-servers-directory)))
    (with-temp-buffer
      (insert
       (format
        (concat
         "source {%s}\n"
         "puts [windows_speech_pipe_command "
         "{/tmp/Bridge.exe} {--stdio} {/init}]\n"
         "puts [windows_speech_pipe_command "
         "{/tmp/Bridge.exe} {--stdio} {}]\n")
        common))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (should
       (equal
        (concat
         "| /init /tmp/Bridge.exe /tmp/Bridge.exe --stdio\n"
         "| /tmp/Bridge.exe --stdio\n")
        (buffer-string))))))

(ert-deftest emacsvox-windows-speech-fatal-rpc-terminates-server ()
  "A fatal bridge response terminates instead of leaving a silent server."
  (let* ((directory (make-temp-file "emacsvox-windows-fatal-" t))
         (bridge (expand-file-name "fatal-bridge.tcl" directory))
         (common
          (expand-file-name
           "windows-speech-common.tcl"
           emacsvox-servers-directory))
         (message "TimeoutException: simulated bridge timeout")
         (payload
          (base64-encode-string
           (encode-coding-string message 'utf-8 t) t)))
    (unwind-protect
        (progn
          (with-temp-file bridge
            (insert
             "gets stdin\n"
             (format "puts {FATAL %s}\n" payload)
             "flush stdout\n"))
          (with-temp-buffer
            (insert
             (format
              (concat
               "source {%s}\n"
               "set test(description) {Test bridge}\n"
               "set test(channel) "
               "[open [list | [info nameofexecutable] {%s}] r+]\n"
               "fconfigure $test(channel) -buffering line\n"
               "windows_speech_rpc test PING\n"
               "puts {continued after fatal response}\n")
              common bridge))
            (let ((status
                   (call-process-region
                    (point-min) (point-max) "tclsh" t t nil)))
              (should (= status 1))
              (should (string-match-p (regexp-quote message) (buffer-string)))
              (should-not
               (string-match-p
                "continued after fatal response" (buffer-string))))))
      (delete-directory directory t))))

(ert-deftest emacsvox-windows-speech-bounds-launcher-round-trips ()
  "The real Windows launcher bounds ordinary and synchronizing requests."
  (unless (and (executable-find "powershell.exe")
               (executable-find "wslpath"))
    (ert-skip "Native Windows build tools require WSL interop"))
  (let* ((directory (make-temp-file "emacsvox-windows-timeout-" t))
         (fixture-directory
          (expand-file-name
           "../test/fixtures/windows-speech"
           emacsvox-servers-directory))
         (build-script
          (expand-file-name "build-timeout-launcher.ps1" fixture-directory))
         (common-source
          (expand-file-name
           "windows-speech-common/BridgeLauncher.cs"
           emacsvox-servers-directory))
         (launcher-source
          (expand-file-name "TimeoutLauncher.cs" fixture-directory))
         (hanging-source
          (expand-file-name "HangingBridge.cs" fixture-directory))
         (windows-path
          (lambda (path)
            (string-trim
             (with-temp-buffer
               (should
                (zerop
                 (call-process
                  "wslpath" nil t nil "-w" (expand-file-name path))))
               (buffer-string))))))
    (unwind-protect
        (let ((status
               (with-temp-buffer
                 (call-process
                  "powershell.exe" nil t nil
                  "-NoProfile" "-ExecutionPolicy" "Bypass"
                  "-File" (funcall windows-path build-script)
                  "-OutputDirectory" (funcall windows-path directory)
                  "-CommonSource" (funcall windows-path common-source)
                  "-LauncherSource" (funcall windows-path launcher-source)
                  "-HangingSource" (funcall windows-path hanging-source)))))
          (when (= status 77)
            (ert-skip "The .NET Framework C# compiler is unavailable"))
          (should (zerop status))
          (let ((launcher (expand-file-name "TimeoutLauncher.exe" directory))
                (child (expand-file-name "HangingBridge.exe" directory)))
            (set-file-modes launcher #o755)
            (set-file-modes child #o755)
            (dolist
                (case
                 '(("PING" "EMACSVOX_WINDOWS_SPEECH_RPC_TIMEOUT_MS")
                   ("SYNC" "EMACSVOX_WINDOWS_SPEECH_SYNC_TIMEOUT_MS")))
              (let* ((process-environment (copy-sequence process-environment))
                     (variable (cadr case))
                     (other
                      (if (string-suffix-p "SYNC_TIMEOUT_MS" variable)
                          "EMACSVOX_WINDOWS_SPEECH_RPC_TIMEOUT_MS"
                        "EMACSVOX_WINDOWS_SPEECH_SYNC_TIMEOUT_MS"))
                     (wslenv
                      (string-join
                       (delq nil
                             (list
                              (concat variable "/w")
                              (concat other "/w")
                              (getenv "WSLENV")))
                       ":"))
                     (started (float-time))
                     status output)
                (setenv variable "100")
                (setenv other "5000")
                (setenv "WSLENV" wslenv)
                (with-temp-buffer
                  (insert (car case) "\n")
                  (setq status
                        (call-process-region
                         (point-min) (point-max) launcher t t nil)
                        output (buffer-string)))
                (should (= status 1))
                (should (< (- (float-time) started) 3.0))
                (should (string-match "FATAL \\([^\r\n]+\\)" output))
                (should
                 (string-match-p
                  "timed out after 100 milliseconds"
                  (decode-coding-string
                   (base64-decode-string (match-string 1 output))
                   'utf-8 t)))))))
      (delete-directory directory t))))

(ert-deftest emacsvox-windows-speech-skips-obsolete-framed-transaction ()
  "The Tcl server evaluates only the latest consecutive buffered packet."
  (let* ((directory (make-temp-file "emacsvox-windows-transaction-" t))
         (log (expand-file-name "transactions.log" directory))
         (common
          (expand-file-name
           "windows-speech-common.tcl"
           emacsvox-servers-directory))
         (first
          (base64-encode-string
           (encode-coding-string "record {obsolete}\n" 'utf-8 t) t))
         (latest
          (base64-encode-string
           (encode-coding-string "record {latest 日本}\n" 'utf-8 t) t)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert
             (format
              (concat
               "source {%s}\n"
               "proc record {value} {\n"
               "  set channel [open {%s} a]\n"
               "  fconfigure $channel -encoding utf-8\n"
               "  puts $channel $value\n"
               "  close $channel\n"
               "}\n"
               "emacsvox_tx 1 {%s}\n"
               "emacsvox_tx 2 {%s}\n")
              common log first latest))
            (should
             (zerop
              (call-process-region
               (point-min) (point-max) "tclsh" t t nil))))
          (with-temp-buffer
            (insert-file-contents log)
            (should (equal (buffer-string) "latest 日本\n"))))
      (delete-directory directory t))))

(ert-deftest emacsvox-windows-speech-preserves-framed-transaction-before-barrier ()
  "Buffered ordinary input cannot make the final framed packet disappear."
  (let* ((common
          (expand-file-name
           "windows-speech-common.tcl"
           emacsvox-servers-directory))
         (first
          (base64-encode-string
           (encode-coding-string "record {obsolete}\n" 'utf-8 t) t))
         (latest
          (base64-encode-string
           (encode-coding-string "record {latest 日本}\n" 'utf-8 t) t)))
    (with-temp-buffer
      (insert
       (format
        (concat
         "source {%s}\n"
         "set log {}\n"
         "proc record {value} {lappend ::log $value}\n"
         "emacsvox_tx 1 {%s}\n"
         "emacsvox_tx 2 {%s}\n"
         "record {ordinary barrier}\n"
         "puts [join $log {|}]\n")
        common first latest))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (should
       (equal
        (buffer-string)
        "latest 日本|ordinary barrier\n")))))

(ert-deftest emacsvox-windows-speech-stop-barrier-cancels-pending-frame ()
  "An urgent stop drops a buffered replaceable frame before evaluation."
  (let* ((common
          (expand-file-name
           "windows-speech-common.tcl"
           emacsvox-servers-directory))
         (payload
          (base64-encode-string
           (encode-coding-string "record {stale speech}\n" 'utf-8 t) t)))
    (with-temp-buffer
      (insert
       (format
        (concat
         "source {%s}\n"
         "set log {}\n"
         "proc record {value} {lappend ::log $value}\n"
         "proc s {} {lappend ::log stop}\n"
         "emacsvox_tx 1 {%s}\n"
         "s\n"
         "puts [list $log $windows_speech_transaction(latest)]\n")
        common payload))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (should (equal (buffer-string) "stop 1\n")))))

(ert-deftest emacsvox-windows-speech-retries-failed-frame-generation ()
  "A failed framed payload does not make its generation unretryable."
  (let* ((common
          (expand-file-name
           "windows-speech-common.tcl"
           emacsvox-servers-directory))
         (payload
          (base64-encode-string
           (encode-coding-string
            "incr ::attempts\nmaybe_fail\nset ::completed 1\n"
            'utf-8 t)
           t)))
    (with-temp-buffer
      (insert
       (format
        (concat
         "source {%s}\n"
         "rename windows_speech_input_pending "
         "windows_speech_input_pending_original\n"
         "proc windows_speech_input_pending args {return 0}\n"
         "set attempts 0\n"
         "set completed 0\n"
         "proc maybe_fail {} {\n"
         "  if {$::attempts == 1} {error {first attempt failed}}\n"
         "}\n"
         "set first [catch {emacsvox_tx 7 {%s}}]\n"
         "set committed_after_failure "
         "[info exists windows_speech_transaction(latest)]\n"
         "set second [catch {emacsvox_tx 7 {%s}}]\n"
         "puts [list $first $committed_after_failure $second "
         "$attempts $completed $windows_speech_transaction(latest)]\n")
        common payload payload))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (should (equal (buffer-string) "1 0 0 2 1 7\n")))))

(ert-deftest emacsvox-windows-eloquence-drains-speech-before-native-cue ()
  "Eloquence should drain each cue-delimited segment before its cue."
  (should
   (equal
    (emacsvox-windows-speech-tests--run-server-library
     "windows-outloud"
     (concat
      "tts_initialize\n"
      "set tts(speech_rate) 75\n"
      "set log {}\n"
      "proc windows_speech_text_rpc {state command text} {\n"
      "  lappend ::log [list $command $text]\n"
      "}\n"
      "proc windows_eci_rpc {request} {\n"
      "  lappend ::log [list RPC $request]\n"
      "  if {$request eq \"SPEAKING\"} {return 0}\n"
      "  return \"\"\n"
      "}\n"
      "proc windows_speech_queue_sound {program sound} {\n"
      "  lappend ::log [list CUE $sound]\n"
      "}\n"
      "q {first}\n"
      "c {control}\n"
      "t 440 100\n"
      "a {/sounds/cue.ogg}\n"
      "q {second}\n"
      "d\n"
      "puts [join $log \\n]\n"))
    (concat
     "RPC SPEAKING\n"
     "ADD first\n"
     "ADD { control }\n"
     "ADD {`vs75 }\n"
     "RPC {INDEX_TONE 440 100}\n"
     "RPC SYNTH\n"
     "RPC SPEAKING\n"
     "CUE /sounds/cue.ogg\n"
     "ADD second\n"
     "RPC SYNTH\n"
     "RPC SPEAKING\n"))))

(ert-deftest emacsvox-windows-eloquence-reports-tracked-terminal-status ()
  "The Eloquence server distinguishes completed and interrupted playback."
  (should
   (equal
    (emacsvox-windows-speech-tests--run-server-library
     "windows-outloud"
     (concat
      "rename d emacsvox_test_real_d\n"
      "proc d {} {return 1}\n"
      "emacsvox_tracked_dispatch 41\n"
      "rename d {}\n"
      "proc d {} {return 0}\n"
      "emacsvox_tracked_dispatch 42\n"))
    (concat
     "__EMACSVOX_TRACKED__ 41 completed\n"
     "__EMACSVOX_TRACKED__ 42 cancelled\n"))))

(ert-deftest emacsvox-windows-eloquence-service-reports-interruption ()
  "The Eloquence playback wait distinguishes drain from pending input."
  (should
   (equal
    (emacsvox-windows-speech-tests--run-server-library
     "windows-outloud"
     (concat
      "set speaking_values {1 0}\n"
      "proc speakingP {} {\n"
      "  set value [lindex $::speaking_values 0]\n"
      "  set ::speaking_values [lrange $::speaking_values 1 end]\n"
      "  return $value\n"
      "}\n"
      "proc select args {return {}}\n"
      "puts [service]\n"
      "proc speakingP {} {return 1}\n"
      "proc select args {return {stdin}}\n"
      "puts [service]\n"))
    "1\n0\n")))

(ert-deftest emacsvox-windows-dectalk-batches-native-speech ()
  "DECtalk should submit one string per cue-delimited speech segment."
  (should
   (equal
    (emacsvox-windows-speech-tests--run-server-library
     "windows-dtk"
     (concat
      "tts_initialize\n"
      "set tts(speech_rate) 225\n"
      "set tts(old_rate) 225\n"
      "set log {}\n"
      "proc windows_speech_text_rpc {state command text} {\n"
      "  lappend ::log [list $command $text]\n"
      "}\n"
      "proc windows_dtk_rpc {request} {\n"
      "  lappend ::log [list RPC $request]\n"
      "  return \"\"\n"
      "}\n"
      "proc windows_speech_queue_sound {program sound} {\n"
      "  lappend ::log [list CUE $sound]\n"
      "}\n"
      "q {first}\n"
      "c {control}\n"
      "t 440 100\n"
      "a {/sounds/cue.ogg}\n"
      "q {second}\n"
      "d\n"
      "puts [join $log \\n]\n"))
    (concat
     "SPEAK {[:sa c][:np][:pu some]"
     "[:i r 1]first [:i r 1]control "
     "[:i r 1][:tone 440,100] }\n"
     "CUE /sounds/cue.ogg\n"
     "SPEAK {[:i r 1]second }\n"))))

(ert-deftest emacsvox-windows-audio-requests-carry-client-scope ()
  "The Tcl player attaches the same explicit scope to play and cancel."
  (let* ((player
          (expand-file-name "windows-play" emacsvox-servers-directory))
         (scope "client one:notification")
         (path "C:\\sounds\\unread mail.wav")
         (encoded-scope
          (base64-encode-string
           (encode-coding-string scope 'utf-8 t) t))
         (encoded-path
          (base64-encode-string
           (encode-coding-string path 'utf-8 t) t)))
    (with-temp-buffer
      (insert
       (format
        (concat
         "set env(EMACSVOX_WINDOWS_AUDIO_SCOPE) {%s}\n"
         "source {%s}\n"
         "puts [windows_play_play_request {%s}]\n"
         "puts [windows_play_cancel_request]\n")
        scope player path))
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (should
       (equal
        (buffer-string)
        (format
         "PLAY %s %s\nCANCEL %s\n"
         encoded-scope encoded-path encoded-scope))))))

(ert-deftest emacsvox-windows-speech-orders-and-cancels-native-cues ()
  "The shared server helper should accept a cue before cancelling its queue."
  (let* ((directory (make-temp-file "emacsvox-windows-audio-" t))
         (player (expand-file-name "windows-play" directory))
         (log (expand-file-name "requests.log" directory))
         (common
          (expand-file-name
           "windows-speech-common.tcl"
           emacsvox-servers-directory))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (with-temp-file player
            (insert "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$AUDIO_TEST_LOG\"\n"))
          (set-file-modes player #o755)
          (setenv "AUDIO_TEST_LOG" log)
          (with-temp-buffer
            (insert
             (format
              (concat
               "source {%s}\n"
               "windows_speech_queue_sound {%s} "
               "{/sounds/unread mail.ogg}\n"
               "windows_speech_cancel_sounds {%s}\n")
              common player player))
            (should
             (zerop
              (call-process-region
               (point-min) (point-max) "tclsh" t t nil))))
          (with-temp-buffer
            (insert-file-contents log)
            (should
             (equal
              "/sounds/unread mail.ogg\n--cancel\n"
              (buffer-string)))))
      (delete-directory directory t))))

(ert-deftest emacsvox-windows-speech-servers-cancel-cue-playback ()
  "Both native Windows servers should cancel cues when speech is stopped."
  (dolist (server '("windows-outloud" "windows-dtk"))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name server emacsvox-servers-directory))
      (should
       (search-forward
        "windows_speech_cancel_sounds $tts(play)" nil t))
      (goto-char (point-min))
      (should
       (search-forward
        "windows_speech_queue_sound $tts(play) $sound" nil t)))))

(ert-deftest emacsvox-windows-speech-uses-canonical-environment ()
  "Owned Windows sources should not depend on Emacspeak environment names."
  (dolist
      (file
       '("windows-outloud"
         "windows-dtk"
         "windows-play"
         "windows-speech-common.tcl"
         "windows-speech-common/WaveOutPlayer.cs"
         "windows-eloquence/EloquenceBridge.cs"
         "windows-dectalk/DectalkBridge.cs"))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name file emacsvox-servers-directory))
      (should-not (search-forward "EMACSPEAK_" nil t)))))

(ert-deftest emacsvox-windows-bridges-enforce-text-repertoires ()
  "Standalone native bridges must reject unencodable text."
  (dolist
      (file
       '("windows-eloquence/EloquenceBridge.cs"
         "windows-dectalk/DectalkBridge.cs"))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name file emacsvox-servers-directory))
      (should (search-forward "EncoderFallback.ExceptionFallback" nil t))
      (goto-char (point-min))
      (should-not
       (search-forward "EncoderFallback.ReplacementFallback" nil t)))))

(ert-deftest emacsvox-windows-omnivox-build-consumes-owned-helpers ()
  "The final Windows bundle should build helpers from the Omnivox checkout."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "../Makefile" emacsvox-servers-directory))
    (should
     (search-forward
      "OMNIVOX_HELPER_DIR = $(OMNIVOX_DIR)/windows-helpers" nil t))
    (should
     (search-forward
      "OMNIVOX_RECORD_RHVOICE=1" nil t))
    (should
     (search-forward
      "OMNIVOX_INCLUDE_PINNED_PIPER=0 windows-omnivox" nil t))
    (should (search-forward "windows-omnivox-piper-dev:" nil t))
    (should
     (search-forward
      "OMNIVOX_PIPER_COMPANION_STATE=github-actions-native-development-build"
      nil t))
    (should
     (search-forward
      "python3 tools/build_rhvoice.py --release" nil t))
    (should
     (search-forward
      "python3 tools/build_flite.py --release" nil t))
    (should
     (search-forward
      "python3 tools/build_rutts.py --release" nil t))
    (should
     (search-forward
      "eloquence_helper=\"$(OMNIVOX_HELPER_DIR)/bin/" nil t))
    (should
     (search-forward
      "dectalk_helper=\"$(OMNIVOX_HELPER_DIR)/bin/" nil t))
    (should (search-forward "WINDOWS-HELPERS-COPYING" nil t))
    (should (search-forward "OMNIVOX-LICENSE" nil t))
    (should (search-forward "rhvoice_companion=local-omnivox-build" nil t))
    (should (search-forward "rhvoice_configuration=" nil t))
    (should (search-forward "flite_companion=local-omnivox-build" nil t))
    (should (search-forward "rutts_companion=local-omnivox-build" nil t))
    (should (search-forward "rutts_built_in_voices=male,female" nil t))
    (should (search-forward "verify-windows-omnivox-live" nil t)))
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name
      "omnivox-release/verify-helper-determinism.sh"
      emacsvox-servers-directory))
    (should (search-forward "make -C \"$omnivox_root\"" nil t))
    (should-not (search-forward "servers/windows-eloquence" nil t))
    (should-not (search-forward "servers/windows-dectalk" nil t))))
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name
      "omnivox-release/verify-runtime-live.sh"
      emacsvox-servers-directory))
    (dolist (contract '("--engine flite --list-voices-alist"
                        "--engine rutts --list-voices-alist"
                        "--engine piper --list-voices-alist"
                        "--engine flite --dump-wav"
                        "--engine rutts --dump-wav"
                        "--engine piper --dump-wav"))
      (goto-char (point-min))
      (should (search-forward contract nil t))))
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name
      "omnivox-release/prepare-piper-development-companion.sh"
      emacsvox-servers-directory))
    (dolist (contract '("sha256sum --check SHA256SUMS"
                        "x86_64-pc-windows-msvc"
                        "tracked_worktree_dirty"
                        "status --porcelain --untracked-files=normal"))
      (goto-char (point-min))
      (should (search-forward contract nil t))))
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name
      "omnivox-release/verify-runtime.sh"
      emacsvox-servers-directory))
    (should
     (search-forward "github-actions-native-development-build" nil t)))

(provide 'emacsvox-windows-speech-tests)

;;; emacsvox-windows-speech-tests.el ends here
