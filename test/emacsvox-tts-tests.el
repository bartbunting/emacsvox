;;; emacsvox-tts-tests.el --- TTS runtime contract tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Pin the generic speech runtime behavior before the DTK-to-TTS namespace
;; migration.  These tests do not start a speech server or produce audio.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'dectalk-voices)
(require 'tts-speak)
(require 'emacsvox-sounds)
(require 'espeak-voices)
(require 'mac-voices)
(require 'outloud-voices)
(require 'plain-voices)
(require 'swiftmac-voices)
(require 'voice-setup)

(defconst emacsvox-test--legacy-protocol-functions
  '(dtk-interp-silence
    dtk-interp-tone
    dtk-interp-queue
    dtk-interp-queue-code
    dtk-interp-speak
    dtk-interp-say
    dtk-interp-stop
    dtk-interp-sync
    dtk-interp-letter
    dtk-interp-next-language
    dtk-interp-previous-language
    dtk-interp-language
    dtk-interp-preferred-language
    dtk-interp-say-version
    dtk-interp-set-rate
    dtk-interp-set-character-scale
    dtk-interp-toggle-split-caps
    dtk-interp-set-punctuations
    dtk-interp-reset-state)
  "Removed DECtalk-era names for the generic speech-server protocol.")

(defconst emacsvox-test--legacy-notification-functions
  '(dtk-notify-process
    dtk-notify-stop
    dtk-notify-apply
    dtk-notify
    dtk-notify-icon
    dtk-notify-initialize)
  "Removed DECtalk-era names for generic notification speech.")

(defconst emacsvox-test--legacy-audio-cue-functions
  '(dtk-tone-deletion
    dtk-tone-upcase
    dtk-tone-downcase
    dtk-silence
    dtk-tone)
  "Removed DECtalk-era names for generic tones and silence.")

(defconst emacsvox-test--legacy-punctuation-functions
  '(dtk-set-punctuations
    dtk-set-punctuations-to-all
    dtk-set-punctuations-to-some
    dtk-toggle-punctuation-mode)
  "Removed DECtalk-era names for generic punctuation commands.")

(defconst emacsvox-test--legacy-rate-functions
  '(dtk-set-rate
    dtk-rate-adjust
    dtk-set-predefined-rate
    dtk-set-character-scale)
  "Removed DECtalk-era names for generic speech-rate commands.")

(defconst emacsvox-test--legacy-behavior-functions
  '(dtk-strip-octals
    dtk-handle-caps
    dtk-toggle-quiet
    dtk-toggle-split-caps
    dtk-toggle-strip-octals
    dtk-toggle-caps
    dtk-toggle-speak-nonprinting-chars)
  "Removed DECtalk-era names for generic speech behavior.")

(defconst emacsvox-test--legacy-style-functions
  '(dtk-get-style
    dtk-get-voice-for-face
    dtk-speak-using-voice
    dtk-next-single-property-change
    dtk-next-style-change
    dtk-previous-style-change
    dtk-plain-cons-p
    dtk-audio-format)
  "Removed DECtalk-era names for generic styled speech.")

(defconst emacsvox-test--legacy-text-preparation-functions
  '(dtk-add-cleanup-pattern
    dtk-handle-repeating-patterns
    dtk-replace-duplicates
    dtk-fix-brackets
    dtk-fix-control-chars
    dtk-fix-backslash
    dtk-quote
    dtk-complement-chunk-separator-syntax
    dtk-chunk-on-white-space-and-punctuations
    dtk-chunk-only-on-punctuations
    dtk-move-across-a-chunk
    dtk-toggle-splitting-on-white-space
    dtk-set-chunk-separator-syntax
    dtk-org-fold
    dtk--skip-invisible-forward
    dtk--skip-invisible-backward
    dtk--delete-invisible-text
    dtk--with-charset-priority)
  "Removed DECtalk-era names for generic text preparation.")

(defconst emacsvox-test--tts-public-aliases
  '((tts-dispatch . dtk-dispatch)
    (tts-reset-state . dtk-reset-state)
    (tts-initialize . dtk-initialize)
    (tts-select-server . dtk-select-server)
    (tts-cloud . dtk-cloud)
    (tts-local-server . dtk-local-server)
    (tts-set-language . dtk-set-language)
    (tts-set-next-language . dtk-set-next-language)
    (tts-set-previous-language . dtk-set-previous-language)
    (tts-char-to-speech . dtk-char-to-speech)
    (tts-unicode-update-untouched-charsets
     . dtk-unicode-update-untouched-charsets)
    (tts-unicode-char-untouched-p . dtk-unicode-char-untouched-p)
    (tts-unicode-name-for-char . dtk-unicode-name-for-char)
    (tts-unicode-full-name-for-char . dtk-unicode-full-name-for-char)
    (tts-letter . dtk-letter))
  "Canonical public aliases and their legacy implementations.")

(defun emacsvox-test--tts-capture-protocol (thunk)
  "Call THUNK and return chronological speech protocol writes."
  (let ((tts-speaker-process 'speaker)
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
       (tts--protocol-queue-text "hello")
       (tts--protocol-queue-code "voice")
       (tts--protocol-queue-text "   ")))
    '((speaker "q {hello }\n")
      (speaker "c {voice }\n")))))

(ert-deftest emacsvox-tts-protocol-dispatches-speech-operations ()
  "Core speech operations retain their exact server commands."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-dispatch)
       (tts--protocol-say "hello")
       (tts--protocol-letter "x")
       (tts--protocol-stop)
       (tts--protocol-version)))
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
       (tts--protocol-tone 440 100)
       (tts--protocol-tone 880 50 t)
       (tts--protocol-silence 25)
       (tts--protocol-silence 30 t)))
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
       (tts--protocol-set-rate 175)
       (tts--protocol-set-character-scale 1.5)
       (tts--protocol-set-split-caps t)
       (tts--protocol-set-split-caps nil)
       (tts--protocol-set-punctuations 'some)
       (tts--protocol-reset)))
    '((speaker "tts_set_speech_rate 175\n")
      (speaker "tts_set_character_scale 1.5\n")
      (speaker "tts_split_caps 1\n")
      (speaker "tts_split_caps 0\n")
      (speaker "tts_set_punctuations some\nd\n")
      (speaker "tts_reset \n")))))

(ert-deftest emacsvox-tts-protocol-synchronizes-buffer-state ()
  "The synchronization command snapshots the current speech state."
  (let ((tts-punctuation-mode 'none)
        (tts-split-caps t)
        (tts-caps nil)
        (tts-speech-rate 210))
    (should
     (equal
      (emacsvox-test--tts-capture-protocol #'tts--protocol-sync)
      '((speaker "tts_sync_state none 1 0 210\n"))))))

(ert-deftest emacsvox-tts-protocol-dispatches-language-operations ()
  "Language navigation and preference commands retain their protocol."
  (should
   (equal
    (emacsvox-test--tts-capture-protocol
     (lambda ()
       (tts--protocol-next-language t)
       (tts--protocol-previous-language nil)
       (tts--protocol-set-language "en-gb" t)
       (tts--protocol-set-preferred-language "en" "en-gb")))
    '((speaker "set_next_lang t\n")
      (speaker "set_previous_lang nil\n")
      (speaker "set_lang en-gb t \n")
      (speaker "set_preferred_lang en en-gb \n")))))

(ert-deftest emacsvox-tts-process-routing-honors-dynamic-binding ()
  "Temporarily selecting another process redirects protocol writes."
  (let ((tts-speaker-process 'primary)
        writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (tts--protocol-stop)
      (let ((tts-speaker-process 'notification))
        (tts--protocol-stop)))
    (should
     (equal
      (nreverse writes)
      '((primary "s\n")
        (notification "s\n"))))))

(ert-deftest emacsvox-tts-notification-apply-selects-notification-process ()
  "Notification calls dynamically use the live notification process."
  (let ((tts-speaker-process 'primary)
        (tts-notify-process 'notification)
        selected)
    (cl-letf (((symbol-function 'processp) (lambda (_) t))
              ((symbol-function 'process-status) (lambda (_) 'run)))
      (tts-notify-apply
       (lambda (_text) (setq selected tts-speaker-process))
       "notice"))
    (should (eq selected 'notification))))

(ert-deftest emacsvox-tts-transitional-public-aliases-are-installed ()
  "Public functions not yet migrated resolve through transitional aliases."
  (dolist (entry emacsvox-test--tts-public-aliases)
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

(ert-deftest emacsvox-tts-protocol-functions-support-native-advice ()
  "Canonical protocol functions remain directly adviceable."
  (let* ((calls 0)
         (advice (lambda (&rest _) (cl-incf calls))))
    (unwind-protect
        (progn
          (advice-add 'tts--protocol-stop :before advice)
          (emacsvox-test--tts-capture-protocol #'tts--protocol-stop)
          (should (= calls 1)))
      (advice-remove 'tts--protocol-stop advice))))

(ert-deftest emacsvox-tts-legacy-protocol-functions-are-removed ()
  "The generic protocol no longer exposes DECtalk-era function names."
  (dolist (function emacsvox-test--legacy-protocol-functions)
    (should-not (fboundp function))))

(ert-deftest emacsvox-tts-legacy-speech-function-is-removed ()
  "The generic speech entry point no longer exposes its DECtalk-era name."
  (should-not (fboundp 'dtk-speak)))

(ert-deftest emacsvox-tts-legacy-stop-function-is-removed ()
  "The speech stop entry point no longer exposes its DECtalk-era name."
  (should-not (fboundp 'dtk-stop)))

(ert-deftest emacsvox-tts-legacy-speak-list-function-is-removed ()
  "List speech no longer exposes its DECtalk-era function name."
  (should-not (fboundp 'dtk-speak-list)))

(ert-deftest emacsvox-tts-legacy-notification-api-is-removed ()
  "Notification speech no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-notification-functions)
    (should-not (fboundp function)))
  (should-not (boundp 'dtk-notify-process)))

(ert-deftest emacsvox-tts-legacy-audio-cue-functions-are-removed ()
  "Generic tones and silence no longer expose DECtalk-era names."
  (dolist (function emacsvox-test--legacy-audio-cue-functions)
    (should-not (fboundp function))))

(ert-deftest emacsvox-tts-legacy-punctuation-api-is-removed ()
  "Generic punctuation state and commands no longer expose DTK names."
  (dolist (function emacsvox-test--legacy-punctuation-functions)
    (should-not (fboundp function)))
  (should-not (boundp 'dtk-punctuation-mode))
  (should-not (boundp 'dtk-punctuation-mode-alist)))

(ert-deftest emacsvox-tts-legacy-rate-api-is-removed ()
  "Generic speech-rate state and commands no longer expose DTK names."
  (dolist (function emacsvox-test--legacy-rate-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-speech-rate
         dtk-speech-rate-base
         dtk-speech-rate-step
         dtk-character-scale))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-behavior-api-is-removed ()
  "Generic speech behavior no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-behavior-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-quiet
         dtk-split-caps
         dtk-caps
         dtk-strip-octals
         dtk-speak-nonprinting-chars
         dtk-octal-chars
         dtk-caps-regexp
         dtk-caps-prefix
         dtk-allcaps-prefix))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-style-api-is-removed ()
  "Generic styled speech no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-style-functions)
    (should-not (fboundp function))))

(ert-deftest emacsvox-tts-legacy-text-preparation-api-is-removed ()
  "Generic text preparation no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-text-preparation-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-cleanup-repeats
         dtk-bracket-regexp
         dtk-chunk-separator-syntax
         dtk-yank-excluded-properties))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-state-remains-buffer-local ()
  "Changing speech state in one buffer does not alter another buffer."
  (let ((default-quiet (default-value 'tts-quiet))
        (default-rate (default-value 'tts-speech-rate)))
    (with-temp-buffer
      (setq tts-quiet (not default-quiet)
            tts-speech-rate (1+ default-rate))
      (should (eq tts-quiet (not default-quiet)))
      (should (= tts-speech-rate (1+ default-rate))))
    (with-temp-buffer
      (should (eq tts-quiet default-quiet))
      (should (= tts-speech-rate default-rate)))))

(ert-deftest emacsvox-tts-canonical-state-aliases-share-storage ()
  "Canonical and legacy global state names address the same values."
  (let ((dtk-program "legacy")
        (tts-speaker-process 'primary)
        (dtk-character-to-speech-table ["legacy"]))
    (should (equal tts-program "legacy"))
    (should (eq tts-speaker-process 'primary))
    (should (equal tts-character-to-speech-table ["legacy"]))
    (setq tts-program "canonical"
          tts-speaker-process 'replacement
          tts-character-to-speech-table ["canonical"])
    (should (equal dtk-program "canonical"))
    (should (eq tts-speaker-process 'replacement))
    (should (equal dtk-character-to-speech-table ["canonical"]))))

(ert-deftest emacsvox-tts-legacy-speaker-process-state-is-removed ()
  "The primary speech process no longer exposes its DECtalk-era state name."
  (should-not (boundp 'dtk-speaker-process)))

(ert-deftest emacsvox-tts-legacy-immediate-stop-state-is-removed ()
  "Immediate-stop state no longer exposes its DECtalk-era variable name."
  (should-not (boundp 'dtk-stop-immediately)))

(ert-deftest emacsvox-tts-auditory-icons-use-canonical-process ()
  "Queued and served icons write through the canonical TTS process."
  (let ((tts-speaker-process 'canonical)
        (emacsvox-sounds-cache (make-hash-table))
        writes)
    (puthash 'served "/sounds/served.ogg" emacsvox-sounds-cache)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes)))
              ((symbol-function 'emacsvox-sounds-resource)
               (lambda (_icon) "/sounds/queued.ogg")))
      (emacsvox-queue-icon 'queued)
      (emacsvox-serve-icon 'served))
    (should
     (equal
      (nreverse writes)
      '((canonical "a /sounds/queued.ogg\n")
        (canonical "p /sounds/served.ogg\n"))))))

(ert-deftest emacsvox-tts-dectalk-soft-uses-canonical-runtime ()
  "The software DECtalk selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'dectalk-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events)))
              ((symbol-function 'tts-set-rate)
               (lambda (rate scope)
                 (push (list 'rate rate scope) events))))
      (dectalk-soft))
    (should
     (equal
      (nreverse events)
      `(configure
        (fastload "voice-defs")
        (select "dtk-soft")
        initialize
        (rate ,dectalk-default-speech-rate global))))))

(ert-deftest emacsvox-tts-dectalk-configures-canonical-state ()
  "The DECtalk adapter configures generic TTS state and dispatch."
  (let ((saved-state
         (mapcar
          (lambda (symbol)
            (list symbol
                  (boundp symbol)
                  (and (boundp symbol) (symbol-value symbol))))
          '(tts-default-voice tts-default-speech-rate
            tts-speech-rate-step tts-speech-rate-base
            tts-handle-unicode)))
        defaults
        character-scale
        untouched-charsets)
    (unwind-protect
        (cl-letf (((symbol-function 'set-default)
                   (lambda (symbol value)
                     (push (cons symbol value) defaults)))
                  ((symbol-function 'tts-set-character-scale)
                   (lambda (scale scope)
                     (setq character-scale (list scale scope))))
                  ((symbol-function 'tts-unicode-update-untouched-charsets)
                   (lambda (charsets)
                     (setq untouched-charsets charsets)))
                  ((symbol-function 'tts-voice-defined-p) #'ignore)
                  ((symbol-function 'tts-get-voice-command) #'ignore)
                  ((symbol-function 'tts-define-voice-from-acss) #'ignore))
          (dectalk-configure-tts)
          (should (eq (symbol-value 'tts-default-voice) 'paul))
          (should
           (= (symbol-value 'tts-default-speech-rate)
              dectalk-default-speech-rate))
          (should (= (symbol-value 'tts-speech-rate-step) 50))
          (should (= (symbol-value 'tts-speech-rate-base) 150))
          (should (symbol-value 'tts-handle-unicode))
          (should
           (eq (symbol-function 'tts-voice-defined-p)
               'dectalk-voice-defined-p))
          (should
           (eq (symbol-function 'tts-get-voice-command)
               'dectalk-get-voice-command))
          (should
           (eq (symbol-function 'tts-define-voice-from-acss)
               'dectalk-define-voice-from-acss)))
      (dolist (entry saved-state)
        (if (nth 1 entry)
            (set (car entry) (nth 2 entry))
          (makunbound (car entry)))))
    (should
     (equal
      (nreverse defaults)
      `((tts-default-speech-rate . ,dectalk-default-speech-rate)
        (tts-speech-rate-step . 50)
        (tts-speech-rate-base . 150))))
    (should (equal character-scale '(1.5 default)))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-outloud-uses-canonical-runtime ()
  "The Outloud selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'outloud-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (outloud))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "outloud")
        initialize)))))

(ert-deftest emacsvox-tts-outloud-configures-canonical-state ()
  "The Outloud adapter configures generic TTS state and dispatch."
  (let (defaults
        character-scale
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          tts-speech-rate-step tts-speech-rate-base
          tts-speech-rate tts-handle-unicode)
        '(nil 1 2 3 4 nil)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-set-character-scale)
                 (lambda (scale scope)
                   (setq character-scale (list scale scope))))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (outloud-configure-tts)
        (should (eq (symbol-value 'tts-default-voice) 'paul))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            outloud-default-speech-rate))
        (should (= (symbol-value 'tts-speech-rate-step) 10))
        (should (= (symbol-value 'tts-speech-rate-base) 50))
        (should
         (= (symbol-value 'tts-speech-rate)
            outloud-default-speech-rate))
        (should (symbol-value 'tts-handle-unicode))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'outloud-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'outloud-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'outloud-define-voice-from-acss))))
    (should
     (equal
      (nreverse defaults)
      `((tts-default-speech-rate . ,outloud-default-speech-rate)
        (tts-speech-rate-step . 10)
        (tts-speech-rate . ,outloud-default-speech-rate)
        (tts-speech-rate-base . 50))))
    (should (equal character-scale '(1.5 default)))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-espeak-uses-canonical-runtime ()
  "The eSpeak selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'espeak-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (espeak))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "espeak")
        initialize)))))

(ert-deftest emacsvox-tts-espeak-copies-canonical-character-table ()
  "The eSpeak table derives from canonical pronunciation state."
  (let ((espeak-character-to-speech-table nil)
        (source ["plain" "left [*] right"]))
    (cl-progv '(tts-character-to-speech-table) (list source)
      (espeak-setup-character-to-speech-table))
    (should
     (equal espeak-character-to-speech-table
            ["plain" "left   right"]))
    (should (equal source ["plain" "left [*] right"]))
    (should-not (eq espeak-character-to-speech-table source))))

(ert-deftest emacsvox-tts-espeak-configures-canonical-state ()
  "The eSpeak adapter configures generic TTS state and dispatch."
  (let (defaults
        character-table-setup
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate)
        '(unset 1)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'espeak-setup-character-to-speech-table)
                 (lambda () (setq character-table-setup t)))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (espeak-configure-tts)
        (should-not (symbol-value 'tts-default-voice))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            espeak-default-speech-rate))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'espeak-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'espeak-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'espeak-define-voice-from-acss))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,espeak-default-speech-rate))))
    (should character-table-setup)
    (should (equal untouched-charsets '(ascii latin-iso8859-1)))))

(ert-deftest emacsvox-tts-swiftmac-uses-canonical-runtime ()
  "The SwiftMac selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'swiftmac-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (swiftmac))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "swiftmac")
        initialize)))))

(ert-deftest emacsvox-tts-swiftmac-configures-canonical-state ()
  "The SwiftMac adapter configures generic TTS state and dispatch."
  (let (defaults
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          emacsvox-play-program)
        '(unset 1 local-player)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (swiftmac-configure-tts)
        (should (eq (symbol-value 'tts-default-voice) 'paul))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            swiftmac-default-speech-rate))
        (should-not (symbol-value 'emacsvox-play-program))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'swiftmac-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'swiftmac-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'swiftmac-define-voice-from-acss))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,swiftmac-default-speech-rate))))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-mac-uses-canonical-runtime ()
  "The macOS selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'mac-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (mac))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "mac")
        initialize)))))

(ert-deftest emacsvox-tts-mac-configures-canonical-state ()
  "The macOS adapter configures generic TTS state and dispatch."
  (let (defaults
        untouched-charsets)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate
          emacsvox-play-program)
        '(unset 1 local-player)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-unicode-update-untouched-charsets)
                 (lambda (charsets)
                   (setq untouched-charsets charsets)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (mac-configure-tts)
        (should
         (eq (symbol-value 'tts-default-voice) 'systemDefault))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            mac-default-speech-rate))
        (should-not (symbol-value 'emacsvox-play-program))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'mac-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'mac-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'mac-define-voice-from-acss))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,mac-default-speech-rate))))
    (should
     (equal
      untouched-charsets
      '(ascii latin-iso8859-1 latin-iso8859-15
              latin-iso8859-9 eight-bit-graphic)))))

(ert-deftest emacsvox-tts-plain-uses-canonical-runtime ()
  "The Plain selector uses the generic TTS runtime API."
  (let (events)
    (cl-letf (((symbol-function 'plain-configure-tts)
               (lambda () (push 'configure events)))
              ((symbol-function 'ems--fastload)
               (lambda (file) (push (list 'fastload file) events)))
              ((symbol-function 'tts-select-server)
               (lambda (server) (push (list 'select server) events)))
              ((symbol-function 'tts-initialize)
               (lambda () (push 'initialize events))))
      (plain))
    (should
     (equal
      (nreverse events)
      '(configure
        (fastload "voice-defs")
        (select "plain")
        initialize)))))

(ert-deftest emacsvox-tts-plain-configures-canonical-state ()
  "The Plain adapter configures generic TTS state and dispatch."
  (let (defaults)
    (cl-progv
        '(tts-default-voice tts-default-speech-rate)
        '(unset 1)
      (cl-letf (((symbol-function 'set-default)
                 (lambda (symbol value)
                   (push (cons symbol value) defaults)))
                ((symbol-function 'tts-voice-defined-p) #'ignore)
                ((symbol-function 'tts-get-voice-command) #'ignore)
                ((symbol-function 'tts-define-voice-from-acss) #'ignore))
        (plain-configure-tts)
        (should (eq (symbol-value 'tts-default-voice) 'paul))
        (should
         (= (symbol-value 'tts-default-speech-rate)
            plain-default-speech-rate))
        (should
         (eq (symbol-function 'tts-voice-defined-p)
             'plain-voice-defined-p))
        (should
         (eq (symbol-function 'tts-get-voice-command)
             'plain-get-voice-command))
        (should
         (eq (symbol-function 'tts-define-voice-from-acss)
             'plain-define-voice-from-acss))))
    (should
     (equal
      defaults
      `((tts-default-speech-rate . ,plain-default-speech-rate))))))

(ert-deftest emacsvox-tts-canonical-state-aliases-remain-buffer-local ()
  "Canonical buffer-local state does not leak between buffers."
  (let ((default-quiet (default-value 'tts-quiet))
        (default-rate (default-value 'tts-speech-rate))
        (default-separators (default-value 'tts-chunk-separator-syntax)))
    (with-temp-buffer
      (setq tts-quiet (not default-quiet)
            tts-speech-rate (1+ default-rate)
            tts-chunk-separator-syntax "canonical")
      (should (eq tts-quiet (not default-quiet)))
      (should (= tts-speech-rate (1+ default-rate)))
      (should (equal tts-chunk-separator-syntax "canonical"))
      (should (local-variable-p 'tts-quiet))
      (should (local-variable-p 'tts-chunk-separator-syntax)))
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
