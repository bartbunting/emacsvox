;;; emacsvox-tts-tests.el --- TTS runtime contract tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Pin the generic speech runtime behavior before the DTK-to-TTS namespace
;; migration.  These tests do not start a speech server or produce audio.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'dtk-speak)
(require 'voice-setup)

(defun emacsvox-test--tts-capture-protocol (thunk)
  "Call THUNK and return chronological speech protocol writes."
  (let ((dtk-speaker-process 'speaker)
        writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (funcall thunk))
    (nreverse writes)))

(ert-deftest emacsvox-tts-protocol-queues-text-and-control-codes ()
  "Text and engine control codes retain their wire representation."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (dtk-interp-queue "hello")
       (dtk-interp-queue-code "voice")
       (dtk-interp-queue "   ")))
    '((speaker "q {hello }\n")
      (speaker "c {voice }\n")))))

(ert-deftest emacsvox-tts-protocol-dispatches-speech-operations ()
  "Core speech operations retain their exact server commands."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (dtk-interp-speak)
       (dtk-interp-say "hello")
       (dtk-interp-letter "x")
       (dtk-interp-stop)
       (dtk-interp-say-version)))
    '((speaker "d\n")
      (speaker "tts_say { hello}\n")
      (speaker "l {x}\n")
      (speaker "s\n")
      (speaker "version\n")))))

(ert-deftest emacsvox-tts-protocol-dispatches-tone-and-silence ()
  "Tone and silence commands preserve optional forced dispatch."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (dtk-interp-tone 440 100)
       (dtk-interp-tone 880 50 t)
       (dtk-interp-silence 25)
       (dtk-interp-silence 30 t)))
    '((speaker "t 440 100\n")
      (speaker "t 880 50\nd\n")
      (speaker "sh 25\n")
      (speaker "sh 30\nd\n")))))

(ert-deftest emacsvox-tts-protocol-updates-engine-state ()
  "Rate, punctuation, character, capitalization, and reset stay stable."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (dtk-interp-set-rate 175)
       (dtk-interp-set-character-scale 1.5)
       (dtk-interp-toggle-split-caps t)
       (dtk-interp-toggle-split-caps nil)
       (dtk-interp-set-punctuations 'some)
       (dtk-interp-reset-state)))
    '((speaker "tts_set_speech_rate 175\n")
      (speaker "tts_set_character_scale 1.5\n")
      (speaker "tts_split_caps 1\n")
      (speaker "tts_split_caps 0\n")
      (speaker "tts_set_punctuations some\nd\n")
      (speaker "tts_reset \n")))))

(ert-deftest emacsvox-tts-protocol-synchronizes-buffer-state ()
  "The synchronization command snapshots the current speech state."
  (let ((dtk-punctuation-mode 'none)
        (dtk-split-caps t)
        (dtk-caps nil)
        (dtk-speech-rate 210))
    (should
     (equal
      (emacsvox-test--tts-capture-protocol #'dtk-interp-sync)
      '((speaker "tts_sync_state none 1 0 210\n"))))))

(ert-deftest emacsvox-tts-protocol-dispatches-language-operations ()
  "Language navigation and preference commands retain their protocol."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (dtk-interp-next-language t)
       (dtk-interp-previous-language nil)
       (dtk-interp-language "en-gb" t)
       (dtk-interp-preferred-language "en" "en-gb")))
    '((speaker "set_next_lang t\n")
      (speaker "set_previous_lang nil\n")
      (speaker "set_lang en-gb t \n")
      (speaker "set_preferred_lang en en-gb \n")))))

(ert-deftest emacsvox-tts-process-routing-honors-dynamic-binding ()
  "Temporarily selecting another process redirects protocol writes."
  (let ((dtk-speaker-process 'primary)
        writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (dtk-interp-stop)
      (let ((dtk-speaker-process 'notification))
        (dtk-interp-stop)))
    (should
     (equal
      (nreverse writes)
      '((primary "s\n")
        (notification "s\n"))))))

(ert-deftest emacsvox-tts-notification-apply-selects-notification-process ()
  "Notification calls dynamically use the live notification process."
  (let ((dtk-speaker-process 'primary)
        (dtk-notify-process 'notification)
        selected)
    (cl-letf (((symbol-function 'processp) (lambda (_) t))
              ((symbol-function 'process-status) (lambda (_) 'run)))
      (dtk-notify-apply
       (lambda (_text) (setq selected dtk-speaker-process))
       "notice"))
    (should (eq selected 'notification))))

(ert-deftest emacsvox-tts-state-remains-buffer-local ()
  "Changing speech state in one buffer does not alter another buffer."
  (let ((default-quiet (default-value 'dtk-quiet))
        (default-rate (default-value 'dtk-speech-rate)))
    (with-temp-buffer
      (setq dtk-quiet (not default-quiet)
            dtk-speech-rate (1+ default-rate))
      (should (eq dtk-quiet (not default-quiet)))
      (should (= dtk-speech-rate (1+ default-rate))))
    (with-temp-buffer
      (should (eq dtk-quiet default-quiet))
      (should (= dtk-speech-rate default-rate)))))

(ert-deftest emacsvox-tts-voice-setup-selects-engine-adapter ()
  "Each speech-server name selects the corresponding voice adapter."
  (dolist
      (case
       '(("outloud" outloud-voices outloud)
         ("dtk-soft" dectalk-voices dectalk)
         ("swiftmac" swiftmac-voices swiftmac)
         ("mac" mac-voices mac)
         ("espeak" espeak-voices espeak)
         ("unknown" plain-voices plain)))
    (let ((dtk-program (nth 0 case))
          required
          configured
          fastloaded)
      (cl-letf (((symbol-function 'require)
                 (lambda (feature &rest _)
                   (push feature required)
                   feature))
                ((symbol-function 'outloud-configure-tts)
                 (lambda () (setq configured 'outloud)))
                ((symbol-function 'dectalk-configure-tts)
                 (lambda () (setq configured 'dectalk)))
                ((symbol-function 'swiftmac-configure-tts)
                 (lambda () (setq configured 'swiftmac)))
                ((symbol-function 'mac-configure-tts)
                 (lambda () (setq configured 'mac)))
                ((symbol-function 'espeak-configure-tts)
                 (lambda () (setq configured 'espeak)))
                ((symbol-function 'plain-configure-tts)
                 (lambda () (setq configured 'plain)))
                ((symbol-function 'ems--fastload)
                 (lambda (file) (setq fastloaded file))))
        (voice-setup))
      (should (memq (nth 1 case) required))
      (should (eq configured (nth 2 case)))
      (should (equal fastloaded "voice-defs")))))

(provide 'emacsvox-tts-tests)
;;; emacsvox-tts-tests.el ends here
