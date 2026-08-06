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
    dtk-tone
    tts-tone-deletion
    tts-tone-upcase
    tts-tone-downcase)
  "Removed legacy names for generic tones and silence.")

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

(defconst emacsvox-test--legacy-character-functions
  '(dtk-speak-setup-character-table
    dtk-char-to-speech
    dtk-letter
    dtk-unicode-charset-limits
    dtk-unicode-build-skip-regexp
    dtk-unicode-update-untouched-charsets
    dtk-unicode-char-in-charsets-p
    dtk-unicode-char-untouched-p
    dtk-unicode-name-for-char
    dtk-unicode-char-punctuation-p
    dtk-unicode-apply-name-transformation-rules
    dtk-unicode-uncustomize-char
    dtk-unicode-customize-char
    dtk-unicode-user-table-handler
    dtk-unicode-full-table-handler
    dtk-unicode-full-name-for-char
    dtk-unicode-short-name-for-char
    dtk-unicode-replace-chars)
  "Removed DECtalk-era names for generic character pronunciation.")

(defconst emacsvox-test--legacy-server-functions
  '(dtk-set-language
    dtk-set-next-language
    dtk-set-previous-language
    dtk-set-preferred-language
    dtk-dispatch
    dtk-reset-default-voice
    dtk-reset-state
    dtk-select-server
    dtk-cloud
    dtk-local-server
    dtk-make-process
    dtk-initialize)
  "Removed DECtalk-era names for generic server lifecycle operations.")

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

(ert-deftest emacsvox-tts-protocol-dispatches-tracked-speech ()
  "Tracked speech uses the supported playback command and returns its token."
  (let ((tts--tracked-dispatch-sequence 40)
        (tts-program "windows-outloud")
        identifier
        writes)
    (unwind-protect
        (cl-letf
            (((symbol-function 'tts--ensure-tracked-process-filter)
              #'ignore))
          (setq
           writes
           (emacsvox-test--tts-capture-protocol
            (lambda ()
              (setq
               identifier
               (tts--protocol-dispatch-tracked #'ignore)))))
          (should (= identifier 41))
          (should
           (equal
            writes
            '((speaker
               "emacsvox_tracked_dispatch 41\n")))))
      (tts-cancel-tracked-dispatch identifier))))

(ert-deftest emacsvox-tts-tracked-speech-rejects-unsupported-server ()
  "Tracked speech fails clearly when its server cannot report completion."
  (let ((tts-program "espeak") called)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (_text) (setq called t))))
      (should-error
       (tts-speak-tracked "hello" #'ignore)
       :type 'user-error)
      (should-not called))))

(ert-deftest emacsvox-tts-recognizes-tracked-server-by-basename ()
  "An absolute Windows Outloud path retains its completion capability."
  (should
   (tts-tracked-playback-completion-p
    "/tmp/emacsvox/servers/windows-outloud"))
  (should-not (tts-tracked-playback-completion-p "windows-dtk")))

(ert-deftest emacsvox-tts-tracked-filter-handles-fragments-and-forwards-output ()
  "Tracked process output tolerates fragments and preserves other output."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-tracked-filter-test" :buffer nil :noquery t))
         (identifier 73)
         statuses
         forwarded)
    (unwind-protect
        (progn
          (process-put
           process tts--tracked-filter-property
           (lambda (_process output)
             (push output forwarded)))
          (process-put process tts--tracked-fragment-property "")
          (puthash
           identifier
           (cons
            process
            (lambda (value status)
              (push (list value status) statuses)))
           tts--tracked-dispatches)
          (tts--speaker-process-filter
           process
           "server notice\n__EMACSVOX_TRACKED_")
          (should-not statuses)
          (tts--speaker-process-filter
           process "_ 73 completed\r\n")
          (should (equal statuses '((73 completed))))
          (should-not (gethash identifier tts--tracked-dispatches))
          (should (equal (nreverse forwarded) '("server notice\n"))))
      (remhash identifier tts--tracked-dispatches)
      (delete-process process))))

(ert-deftest emacsvox-tts-tracked-filter-reports-cancellation ()
  "Tracked cancellation retires its callback without claiming completion."
  (let* ((process
          (make-pipe-process
           :name "emacsvox-tracked-cancel-test" :buffer nil :noquery t))
         status)
    (unwind-protect
        (progn
          (puthash
           74
           (cons
            process
            (lambda (identifier outcome)
              (setq status (list identifier outcome))))
           tts--tracked-dispatches)
          (tts--speaker-process-filter
           process "__EMACSVOX_TRACKED__ 74 cancelled\n")
          (should (equal status '(74 cancelled)))
          (should-not (gethash 74 tts--tracked-dispatches)))
      (remhash 74 tts--tracked-dispatches)
      (delete-process process))))

(ert-deftest emacsvox-tts-retiring-process-cleans-owned-runtime-state ()
  "Retiring a server cancels delivery, callbacks, clients, and the process."
  (let ((process
         (make-pipe-process
          :name "emacsvox-retire-process-test" :buffer nil :noquery t))
        (tts--tracked-dispatches (make-hash-table :test #'eql))
        events)
    (unwind-protect
        (progn
          (puthash 17 (cons process #'ignore) tts--tracked-dispatches)
          (let ((tts-stopped-hook
                 (list (lambda (stopped) (push (list 'hook stopped) events)))))
            (cl-letf
                (((symbol-function 'emacsvox-aural-cancel-pending-deliveries)
                  (lambda (owner) (push (list 'cancel owner) events)))
                 ((symbol-function 'emacsvox-aural-delivery-send)
                  (lambda (owner command kind)
                    (push (list 'send owner command kind) events)))
                 ((symbol-function 'delete-process)
                  (lambda (owner) (push (list 'delete owner) events))))
              (tts--retire-process process)))
          (should-not (gethash 17 tts--tracked-dispatches))
          (should
           (equal
            (nreverse events)
            `((cancel ,process)
              (send ,process "s\n" stop)
              (hook ,process)
              (delete ,process)))))
      (when (process-live-p process)
        (delete-process process)))))

(ert-deftest emacsvox-tts-initialize-retires-old-process-after-new-starts ()
  "Successful initialization retires the old server before publishing new."
  (let ((tts-speaker-process 'old)
        (tts-program "test-server")
        events)
    (cl-letf
        (((symbol-function 'tts-make-process)
          (lambda (_name)
            (push 'started events)
            'new))
         ((symbol-function 'tts--retire-process)
          (lambda (process)
            (push (list 'retired process) events)))
         ((symbol-function 'processp)
          (lambda (process) (memq process '(old new))))
         ((symbol-function 'tts-multistream-p) (lambda (_) nil))
         ((symbol-function 'require) (lambda (&rest _) t))
         ((symbol-function 'voice-setup)
          (lambda () (push (list 'configured tts-speaker-process) events))))
      (tts-initialize))
    (should (eq tts-speaker-process 'new))
    (should
     (equal
      (nreverse events)
      '(started (retired old) (configured new))))))

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

(ert-deftest emacsvox-tts-voice-capabilities-are-adapter-owned-and-copied ()
  "The generic interface returns an isolated adapter descriptor."
  (let* ((descriptor
          '(:adapter test
            :source static
            :family-selection enumerated
            :families ((test-voice :label "Test voice"))
            :dimensions (family)))
         (tts-voice-capabilities-function (lambda () descriptor))
         (first (tts-voice-capabilities))
         (second (tts-voice-capabilities)))
    (should (equal first descriptor))
    (setcar (plist-get first :dimensions) 'average-pitch)
    (should (equal (plist-get second :dimensions) '(family)))
    (should (equal (plist-get descriptor :dimensions) '(family)))))

(ert-deftest emacsvox-tts-outloud-describes-and-compiles-base-voices ()
  "Eloquence publishes all presets and compiles portable family names."
  (let* ((capabilities (outloud-voice-capabilities))
         command)
    (should (eq (plist-get capabilities :adapter) 'outloud))
    (should (eq (plist-get capabilities :family-selection) 'enumerated))
    (should (= (length (plist-get capabilities :families)) 8))
    (should
     (eq (tts-voice-family-id 'female capabilities) 'outloud-v2))
    (should (eq (tts-voice-family-id "V7" capabilities) 'outloud-v7))
    (cl-letf (((symbol-function 'outloud-define-voice)
               (lambda (_name value) (setq command value))))
      (outloud-define-voice-from-acss
       'test-outloud-family
       (make-acss :family 'female :average-pitch 5)))
    (should (string-match-p (regexp-quote "`v2") command))
    (should (string-match-p (regexp-quote "`vb65") command))))

(ert-deftest emacsvox-tts-dectalk-describes-and-compiles-base-voices ()
  "DECtalk publishes its built-ins and accepts non-Paul ACSS settings."
  (let* ((capabilities (dectalk-voice-capabilities))
         command)
    (should (eq (plist-get capabilities :adapter) 'dectalk))
    (should (eq (plist-get capabilities :family-selection) 'enumerated))
    (should (= (length (plist-get capabilities :families)) 9))
    (should (eq (tts-voice-family-id 'female capabilities) 'betty))
    (should (eq (tts-voice-family-id 'child capabilities) 'kit))
    (cl-letf (((symbol-function 'dectalk-define-voice)
               (lambda (_name value) (setq command value))))
      (dectalk-define-voice-from-acss
       'test-dectalk-family
       (make-acss :family 'betty :average-pitch 5)))
    (should (string-match-p (regexp-quote ":nb") command))
    (should (string-match-p (regexp-quote "ap 122") command))))

(ert-deftest emacsvox-tts-free-form-mac-families-compile-installed-names ()
  "The macOS adapters preserve free-form installed voice identifiers."
  (should
   (equal (mac-get-family-code "Samantha")
          " [{voice samantha}] "))
  (should
   (equal (swiftmac-get-family-code "en-US:Alex")
          " [{voice en-US:Alex}] ")))

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

(ert-deftest emacsvox-tts-notification-preserves-semantic-occasion ()
  "Notification transport does not replace an established semantic occasion."
  (let ((emacsvox-aural-submission-context
         '(:module agent-shell :occasion state-change))
        (emacsvox-aural-submission-occasion 'state-change)
        captured-context
        captured-occasion)
    (cl-letf (((symbol-function 'tts-notify-process) #'ignore)
              ((symbol-function 'tts-speak)
               (lambda (_text)
                 (setq
                  captured-context
                  (copy-tree emacsvox-aural-submission-context)
                  captured-occasion
                  emacsvox-aural-submission-occasion))))
      (tts-notify "Session mode changed" 'dont-log))
    (should (eq captured-occasion 'state-change))
    (should
     (eq (plist-get captured-context :occasion) 'state-change))))

(ert-deftest emacsvox-tts-org-fold-uses-current-hidden-spec ()
  "Org link visibility uses the current Emacs 31 folding spec."
  (let (events)
    (cl-progv
        '(org-fold-core-style org-link-descriptive)
        '(text-properties t)
      (cl-letf (((symbol-function 'outline-mode)
                 (lambda () (push '(outline) events)))
                ((symbol-function 'org-fold-initialize)
                 (lambda (ellipsis)
                   (push (list 'initialize ellipsis) events)))
                ((symbol-function 'org-fold-core-set-folding-spec-property)
                 (lambda (spec property value &optional force)
                   (push
                    (list 'spec spec property value force)
                    events))))
        (tts-org-fold)))
    (should
     (equal
      (nreverse events)
      '((outline)
        (initialize "...")
        (spec org-fold-hidden :visible nil nil))))))

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
  "Generic tones and silence no longer expose legacy helper names."
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

(ert-deftest emacsvox-tts-legacy-character-api-is-removed ()
  "Generic character pronunciation no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-character-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-handle-unicode
         dtk-character-to-speech-table
         dtk-unicode-character-replacement-alist
         dtk-unicode-name-transformation-rules-alist
         dtk-unicode-untouched-charsets
         dtk-unicode-handlers
         dtk-unicode-charset-filter-regexp
         dtk-unicode-cache))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-legacy-server-api-is-removed ()
  "Generic server lifecycle no longer exposes DECtalk-era names."
  (dolist (function emacsvox-test--legacy-server-functions)
    (should-not (fboundp function)))
  (dolist
      (variable
       '(dtk-program
         dtk-servers-alist
         dtk-cloud-server
         dtk-local-server-process
         dtk-speech-server-program
         dtk-local-server-port
         dtk-local-engine
         dtk-pamixer))
    (should-not (boundp variable))))

(ert-deftest emacsvox-tts-program-uses-canonical-environment-variable ()
  "TTS_PROGRAM selects the server and the removed DTK variable is ignored."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "TTS_PROGRAM" "plain")
    (setenv "DTK_PROGRAM" "legacy")
    (should (equal (tts--default-program) "plain"))
    (setenv "TTS_PROGRAM" nil)
    (should-not (equal (tts--default-program) "legacy"))))

(defun emacsvox-test--tts-server-player (emacsvox-player emacspeak-player)
  "Return the Tcl TTS player selected from the supplied environment.

EMACSVOX-PLAYER and EMACSPEAK-PLAYER set their respective environment
variables; nil removes the variable."
  (let ((process-environment (copy-sequence process-environment))
        (library
         (expand-file-name "servers/tts-lib.tcl" emacsvox-directory)))
    (setenv "EMACSVOX_PLAY" emacsvox-player)
    (setenv "EMACSPEAK_PLAY" emacspeak-player)
    (with-temp-buffer
      (insert
       (format
        "source {%s}; tts_initialize; puts $tts(play)"
        library))
      (let ((status
             (call-process-region
              (point-min) (point-max) "tclsh" t t)))
        (unless (and (integerp status) (zerop status))
          (error "Could not exercise Tcl TTS initialization: %s"
                 (buffer-string)))
        (string-trim (buffer-string))))))

(ert-deftest emacsvox-tts-server-player-uses-emacsvox-environment ()
  "TTS servers honor EMACSVOX_PLAY and ignore the removed Emacspeak name."
  (skip-unless (executable-find "tclsh"))
  (should
   (equal
    (emacsvox-test--tts-server-player
     "/tmp/emacsvox-player" "/tmp/emacspeak-player")
    "/tmp/emacsvox-player"))
  (should
   (equal
    (emacsvox-test--tts-server-player nil "/tmp/emacspeak-player")
    "/usr/bin/paplay")))

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

(ert-deftest emacsvox-tts-legacy-speaker-process-state-is-removed ()
  "The primary speech process no longer exposes its DECtalk-era state name."
  (should-not (boundp 'dtk-speaker-process)))

(ert-deftest emacsvox-tts-legacy-immediate-stop-state-is-removed ()
  "Immediate-stop state no longer exposes its DECtalk-era variable name."
  (should-not (boundp 'dtk-stop-immediately)))

(ert-deftest emacsvox-tts-auditory-icons-use-canonical-process ()
  "Queued resources and served icons use the canonical TTS process."
  (let ((tts-speaker-process 'canonical)
        (emacsvox-sounds-cache (make-hash-table))
        writes)
    (puthash 'served "/sounds/served.ogg" emacsvox-sounds-cache)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process string)
                 (push (list process string) writes))))
      (emacsvox-queue-resource "/sounds/queued.ogg")
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
            tts-handle-unicode tts-voice-capabilities-function)))
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
               'dectalk-define-voice-from-acss))
          (should
           (eq tts-voice-capabilities-function
               #'dectalk-voice-capabilities)))
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
          tts-speech-rate tts-handle-unicode
          tts-voice-capabilities-function)
        '(nil 1 2 3 4 nil nil)
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
             'outloud-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'outloud-voice-capabilities))))
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
        '(tts-default-voice tts-default-speech-rate
          tts-voice-capabilities-function)
        '(unset 1 nil)
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
             'espeak-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'espeak-voice-capabilities))))
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
          emacsvox-play-program tts-voice-capabilities-function)
        '(unset 1 local-player nil)
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
             'swiftmac-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'swiftmac-voice-capabilities))))
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
          emacsvox-play-program tts-voice-capabilities-function)
        '(unset 1 local-player nil)
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
             'mac-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'mac-voice-capabilities))))
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
        '(tts-default-voice tts-default-speech-rate
          tts-voice-capabilities-function)
        '(unset 1 nil)
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
             'plain-define-voice-from-acss))
        (should
         (eq tts-voice-capabilities-function
             #'plain-voice-capabilities))))
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
