;;; emacsvox-tts-tests.el --- TTS runtime contract tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Pin the generic speech runtime behavior before the DTK-to-TTS namespace
;; migration.  These tests do not start a speech server or produce audio.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'dtk-speak)
(require 'voice-setup)

(defconst emacsvox-test--tts-protocol-aliases
  '((tts--protocol-silence . dtk-interp-silence)
    (tts--protocol-tone . dtk-interp-tone)
    (tts--protocol-queue-text . dtk-interp-queue)
    (tts--protocol-queue-code . dtk-interp-queue-code)
    (tts--protocol-dispatch . dtk-interp-speak)
    (tts--protocol-say . dtk-interp-say)
    (tts--protocol-stop . dtk-interp-stop)
    (tts--protocol-sync . dtk-interp-sync)
    (tts--protocol-letter . dtk-interp-letter)
    (tts--protocol-next-language . dtk-interp-next-language)
    (tts--protocol-previous-language . dtk-interp-previous-language)
    (tts--protocol-set-language . dtk-interp-language)
    (tts--protocol-set-preferred-language . dtk-interp-preferred-language)
    (tts--protocol-version . dtk-interp-say-version)
    (tts--protocol-set-rate . dtk-interp-set-rate)
    (tts--protocol-set-character-scale . dtk-interp-set-character-scale)
    (tts--protocol-set-split-caps . dtk-interp-toggle-split-caps)
    (tts--protocol-set-punctuations . dtk-interp-set-punctuations)
    (tts--protocol-reset . dtk-interp-reset-state))
  "Canonical protocol aliases and their legacy implementations.")

(defconst emacsvox-test--tts-public-aliases
  '((tts-get-style . dtk-get-style)
    (tts-get-voice-for-face . dtk-get-voice-for-face)
    (tts-tone-deletion . dtk-tone-deletion)
    (tts-tone-upcase . dtk-tone-upcase)
    (tts-tone-downcase . dtk-tone-downcase)
    (tts-silence . dtk-silence)
    (tts-tone . dtk-tone)
    (tts-speak-using-voice . dtk-speak-using-voice)
    (tts-dispatch . dtk-dispatch)
    (tts-stop . dtk-stop)
    (tts-set-rate . dtk-set-rate)
    (tts-set-punctuations . dtk-set-punctuations)
    (tts-set-punctuations-to-all . dtk-set-punctuations-to-all)
    (tts-set-punctuations-to-some . dtk-set-punctuations-to-some)
    (tts-reset-state . dtk-reset-state)
    (tts-initialize . dtk-initialize)
    (tts-add-cleanup-pattern . dtk-add-cleanup-pattern)
    (tts-rate-adjust . dtk-rate-adjust)
    (tts-set-predefined-rate . dtk-set-predefined-rate)
    (tts-set-character-scale . dtk-set-character-scale)
    (tts-toggle-quiet . dtk-toggle-quiet)
    (tts-toggle-split-caps . dtk-toggle-split-caps)
    (tts-toggle-strip-octals . dtk-toggle-strip-octals)
    (tts-toggle-caps . dtk-toggle-caps)
    (tts-toggle-speak-nonprinting-chars
     . dtk-toggle-speak-nonprinting-chars)
    (tts-toggle-punctuation-mode . dtk-toggle-punctuation-mode)
    (tts-select-server . dtk-select-server)
    (tts-cloud . dtk-cloud)
    (tts-local-server . dtk-local-server)
    (tts-set-language . dtk-set-language)
    (tts-set-next-language . dtk-set-next-language)
    (tts-set-previous-language . dtk-set-previous-language)
    (tts-toggle-splitting-on-white-space
     . dtk-toggle-splitting-on-white-space)
    (tts-set-chunk-separator-syntax . dtk-set-chunk-separator-syntax)
    (tts-chunk-on-white-space-and-punctuations
     . dtk-chunk-on-white-space-and-punctuations)
    (tts-char-to-speech . dtk-char-to-speech)
    (tts-unicode-char-untouched-p . dtk-unicode-char-untouched-p)
    (tts-unicode-name-for-char . dtk-unicode-name-for-char)
    (tts-unicode-full-name-for-char . dtk-unicode-full-name-for-char)
    (tts-speak . dtk-speak)
    (tts-speak-list . dtk-speak-list)
    (tts-letter . dtk-letter)
    (tts-notify-process . dtk-notify-process)
    (tts-notify-stop . dtk-notify-stop)
    (tts-notify-apply . dtk-notify-apply)
    (tts-notify . dtk-notify)
    (tts-notify-icon . dtk-notify-icon)
    (tts-notify-initialize . dtk-notify-initialize))
  "Canonical public aliases and their legacy implementations.")

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

(ert-deftest emacsvox-tts-canonical-function-aliases-are-installed ()
  "Canonical protocol and public functions resolve through legacy entry points."
  (dolist
      (entry
       (append
        emacsvox-test--tts-protocol-aliases
        emacsvox-test--tts-public-aliases))
    (should (eq (symbol-function (car entry)) (cdr entry)))))

(ert-deftest emacsvox-tts-canonical-protocol-preserves-wire-format ()
  "Canonical protocol entry points produce the established commands."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-queue-text "hello")
       (tts--protocol-set-rate 180)
       (tts--protocol-dispatch)))
    '((speaker "q {hello }\n")
      (speaker "tts_set_speech_rate 180\n")
      (speaker "d\n")))))

(ert-deftest emacsvox-tts-canonical-aliases-preserve-legacy-advice ()
  "Advice on a legacy entry point still observes canonical calls."
  (let* ((calls 0)
         (advice (lambda (&rest _) (cl-incf calls))))
    (unwind-protect
        (progn
          (advice-add 'dtk-interp-stop :before advice)
          (emacsvox-test--tts-capture-protocol #'tts--protocol-stop)
          (should (= calls 1)))
      (advice-remove 'dtk-interp-stop advice))))

(ert-deftest emacsvox-tts-canonical-speech-preserves-legacy-interception ()
  "Replacing the legacy speech function still intercepts canonical speech."
  (let (spoken)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (setq spoken text))))
      (tts-speak "hello"))
    (should (equal spoken "hello"))))

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

(ert-deftest emacsvox-tts-canonical-state-aliases-share-storage ()
  "Canonical and legacy global state names address the same values."
  (let ((dtk-program "legacy")
        (dtk-stop-immediately t)
        (dtk-speaker-process 'primary))
    (should (equal tts-program "legacy"))
    (should tts-stop-immediately)
    (should (eq tts-speaker-process 'primary))
    (setq tts-program "canonical"
          tts-stop-immediately nil
          tts-speaker-process 'replacement)
    (should (equal dtk-program "canonical"))
    (should-not dtk-stop-immediately)
    (should (eq dtk-speaker-process 'replacement))))

(ert-deftest emacsvox-tts-canonical-state-aliases-preserve-dynamic-routing ()
  "Binding either process name is visible through its corresponding alias."
  (let ((tts-speaker-process 'canonical))
    (should (eq dtk-speaker-process 'canonical)))
  (let ((dtk-speaker-process 'legacy))
    (should (eq tts-speaker-process 'legacy))))

(ert-deftest emacsvox-tts-canonical-state-aliases-remain-buffer-local ()
  "Canonical buffer-local state shares legacy storage without leaking."
  (let ((default-quiet (default-value 'dtk-quiet))
        (default-rate (default-value 'dtk-speech-rate))
        (default-separators (default-value 'dtk-chunk-separator-syntax)))
    (with-temp-buffer
      (setq tts-quiet (not default-quiet)
            tts-speech-rate (1+ default-rate)
            tts-chunk-separator-syntax "canonical")
      (should (eq dtk-quiet (not default-quiet)))
      (should (= dtk-speech-rate (1+ default-rate)))
      (should (equal dtk-chunk-separator-syntax "canonical"))
      (should (local-variable-p 'tts-quiet))
      (should (local-variable-p 'dtk-quiet))
      (should (local-variable-p 'tts-chunk-separator-syntax))
      (should (local-variable-p 'dtk-chunk-separator-syntax)))
    (with-temp-buffer
      (should (eq tts-quiet default-quiet))
      (should (= tts-speech-rate default-rate))
      (should (equal tts-chunk-separator-syntax default-separators)))))

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
    (let ((tts-program (nth 0 case))
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
