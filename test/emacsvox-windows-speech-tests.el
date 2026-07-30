;;; emacsvox-windows-speech-tests.el --- Windows speech tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for native Windows speech server discovery and selection.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-windows-speech)

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
      (emacsvox-windows-speech-restore-audio)
      (should (equal emacsvox-play-program "/usr/bin/play"))
      (should (equal ems--play-args "-q"))
      (should (equal sox-play "/usr/bin/play"))
      (should-not (getenv "EMACSVOX_PLAY")))))

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

(ert-deftest emacsvox-windows-speech-skips-obsolete-framed-transaction ()
  "The shared Tcl server layer evaluates only the latest buffered packet."
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

(provide 'emacsvox-windows-speech-tests)

;;; emacsvox-windows-speech-tests.el ends here
