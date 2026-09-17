;;; run-live-catalogue-tests.el --- Native download and Apply acceptance -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Opt-in network test in a fresh Emacs using current byte-code and a complete
;; native runtime. EMACSVOX_LIBRARY_TEST_SERVER selects the executable.
;; Windows tests also supply an empty native EMACSVOX_LIBRARY_TEST_ROOT.
;; EMACSVOX_LIBRARY_TEST_ENGINE optionally selects piper or rhvoice instead of flite.
;; Covers filters, exact preview, palette saving and return navigation as well.
;; Speech output is muted. No user profile or existing Emacs is modified.
;;; Code:
(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (require 'emacsvox-preamble)
  (require 'tts-speak)
  (require 'omnivox-voices)
  (require 'omnivox-catalogue)
  (require 'emacsvox-aural-voice-editor))
(let ((directory (make-temp-file "catalogue-palette-acceptance-" t)))
  (setq emacsvox-aural-schemes-file (expand-file-name "aural.el" directory)
        emacsvox-aural-routing-profiles-file (expand-file-name "routing.el" directory)))
(setq tts-program "omnivox" emacsvox-speak-messages nil tts-notification-device "both" debug-on-error t)
(unless (getenv "EMACSVOX_LIBRARY_TEST_SERVER") (error "Supply a complete native runtime"))
(dolist (function '(omnivox-catalogue omnivox-library-apply tts-make-process))
  (unless (string-suffix-p ".elc" (or (symbol-file function) ""))
    (error "Expected compiled %s" function)))
(dolist (name '("OMNIVOX_VOICE_LIBRARY" "OMNIVOX_PIPER_MODEL" "OMNIVOX_FLITE_VOICES"
                "OMNIVOX_OWNED_STARTUP" "OMNIVOX_OWNED_STARTUP_SHA256" "OMNIVOX_OWNED_LIBRARY"))
  (setenv name nil))
(setenv "OMNIVOX_PROGRAM" (getenv "EMACSVOX_LIBRARY_TEST_SERVER"))
(when (and (string-suffix-p ".exe" (getenv "OMNIVOX_PROGRAM"))
           (not (getenv "EMACSVOX_LIBRARY_TEST_ROOT")))
  (error "Supply a fresh native Windows voice root"))
(setenv "OMNIVOX_VOICE_ROOT" (or (getenv "EMACSVOX_LIBRARY_TEST_ROOT") (make-temp-file "omnivox-catalogue-acceptance-" t)))
(setenv "OMNIVOX_ENGINE" "espeak")
(setenv "OMNIVOX_AUDIO_OUTPUT" "null")
;; Initialize the same voice adapter as the full profile before opening speech UI.
(omnivox-configure-tts)
;; Exercise Apply with an owned voice choice as in a customized live profile.
;; Its empty adjustment is a JSON object, represented by an Emacs hash table.
(puthash 'catalogue-acceptance
         (emacsvox-aural-compile-voice-palette-data
          '(:schema-version 3 :id catalogue-acceptance :summary "Catalogue acceptance"
            :parent acss-default :routing owned
            :entries ((bolden :style (:family nil :average-pitch nil :pitch-range nil
                                     :stress 5 :richness nil)
                              :choices ((:id "espeak-default"
                                         :selector (:kind engine-default :scope portable
                                                    :engine-id "espeak")
                                         :adjustments nil))))))
         emacsvox-aural-voice-palette-registry)
(setq emacsvox-aural-voice-palette-override 'catalogue-acceptance)
(emacsvox-aural--write-user-data
 (list :schema-version 9 :voice-palettes
       (list (emacsvox-aural-voice-palette-data-form
              (gethash 'catalogue-acceptance emacsvox-aural-voice-palette-registry)))))
(emacsvox-aural-save-routing-profiles)
(defconst omnivox-catalogue-test--engine (or (getenv "EMACSVOX_LIBRARY_TEST_ENGINE") "flite"))
(defconst omnivox-catalogue-test--entry
  (pcase omnivox-catalogue-test--engine
    ("flite" "flite-cmu-us-awb") ("piper" "piper-en-us-kristin-medium")
    ("rhvoice" "rhvoice-alan-eng")
    (_ (error "Test engine must be flite, piper or rhvoice"))))
(defconst omnivox-catalogue-test--voice
  (pcase omnivox-catalogue-test--engine
    ("flite" "flitevox:cmu_us_awb") ("rhvoice" "rhvoice:Alan")
    (_ "piper:v1/c/piper-en-us-kristin-medium/0")))
(princ (format "Private voice root: %s\n" (getenv "OMNIVOX_VOICE_ROOT")))

(defun omnivox-catalogue-test--inspect ()
  (let ((service (omnivox-library--service)))
    (unwind-protect (omnivox-library--request service '(:command "inspect"))
      (delete-process service))))

(defun omnivox-catalogue-test--check-choice (process)
  "Check that PROCESS acknowledged the fixture's unchanged owned choice."
  (let* ((registration (process-get process 'omnivox-library-accepted-registration))
         (row (seq-find
               (lambda (entry) (equal "voice-bolden" (plist-get (plist-get entry :definition) :id)))
               (plist-get registration :definitions)))
         (choices (plist-get (plist-get row :definition) :choices)))
    (unless (and (equal "layered" (plist-get row :mode)) (= 1 (length choices))
                 (equal "espeak-default" (plist-get (aref choices 0) :id))
                 (hash-table-p (plist-get (aref choices 0) :adjustments))
                 (zerop (hash-table-count (plist-get (aref choices 0) :adjustments))))
      (error "Owned voice choice or empty adjustment object was lost"))))

(defun omnivox-catalogue-test--wait (predicate label)
  "Wait at most 45 seconds for PREDICATE, reporting LABEL on failure."
  (let ((deadline (+ (float-time) 45)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (unless (funcall predicate) (error "Timed out: %s" label))))

(defun omnivox-catalogue-test--browser-ready ()
  "Wait for the combined browser's library and both current workers."
  (omnivox-catalogue-test--wait
   (lambda ()
     (and (not emacsvox-aural-voice-workbench--library-ticket)
          (emacsvox-aural-voice-workbench--library-index)
          (not (eq 'unknown
                   (emacsvox-aural-voice-workbench--needs-apply
                    (emacsvox-aural-voice-workbench--library-row
                     (list omnivox-catalogue-test--engine omnivox-catalogue-test--voice)))))))
   "Browser library and worker status"))

(defun omnivox-catalogue-test--check-preview (result)
  "Require completed exact native playback evidence in RESULT."
  (unless (and (eq (plist-get result :status) 'completed)
               (seq-some
                (lambda (entry)
                  (if (eq (plist-get result :preview-kind) 'layered)
                      (seq-some
                       (lambda (audio)
                         (let ((realized (plist-get audio :realized)))
                           (and (eq t (plist-get audio :playback_started))
                                (equal (plist-get realized :engine_id) omnivox-catalogue-test--engine)
                                (equal (plist-get realized :voice_id) omnivox-catalogue-test--voice))))
                       (plist-get entry :accepted-audio))
                    (let ((realized (plist-get entry :realized)))
                      (and (equal (plist-get realized :engine-id) omnivox-catalogue-test--engine)
                           (equal (plist-get realized :voice-id) omnivox-catalogue-test--voice)))))
                (plist-get result :results)))
    (error "Preview did not complete with the downloaded voice: %S" result)))

(unwind-protect
    (progn
      (unless (zerop (length (plist-get (plist-get (omnivox-catalogue-test--inspect) :index) :voices)))
        (error "Test requires an empty private library"))
      (setq tts-speaker-process (tts-make-process "Speaker"))
      (tts-notify-initialize)
      (dolist (process (list tts-speaker-process tts-notify-process))
        (omnivox--negotiate-process process)
        (omnivox-library--wait (lambda () (process-get process 'omnivox-library-accepted-registration))
                               process "Initial registration")
        (omnivox-catalogue-test--check-choice process))
      (let ((before (list tts-speaker-process tts-notify-process)))
        (omnivox-catalogue omnivox-catalogue-test--engine)
        (omnivox-catalogue-search (pcase omnivox-catalogue-test--engine ("flite" "AWB") ("rhvoice" "Alan") (_ "Kristin")))
        (emacsvox-aural-ui-goto-row omnivox-catalogue-test--entry)
        (unless (equal (tabulated-list-get-id) omnivox-catalogue-test--entry) (error "Missing catalogue row"))
        (cl-letf (((symbol-function 'omnivox-library--confirm) (lambda (&rest _) t)))
          (omnivox-catalogue-install))
        (let* ((key (omnivox-catalogue--key omnivox-catalogue--host omnivox-catalogue--entry))
               (process (plist-get (gethash key omnivox-catalogue--operations) :process))
               (deadline (+ (float-time) 240)))
          (while (and (process-live-p process) (< (float-time) deadline))
            (accept-process-output process 0.1))
          (when (process-live-p process)
            (process-send-eof process)
            (error "Acquisition timed out; cleanup requested"))
          (unless (equal "installed-disabled"
                         (plist-get (plist-get (gethash key omnivox-catalogue--operations) :progress) :state))
            (error "Unexpected acquisition result: %S" (gethash key omnivox-catalogue--operations))))
        (unless (equal before (list tts-speaker-process tts-notify-process))
          (error "Installation replaced a speech process"))
        (let* ((library (omnivox-catalogue-test--inspect)) (voices (plist-get (plist-get library :index) :voices)))
          (unless (and (= 1 (length voices)) (eq :false (plist-get (aref voices 0) :enabled))
                       (eq :null (plist-get library :active)))
            (error "Install changed enablement or active state")))
        (princ "PASS: accessible catalogue downloaded and installed voice disabled; exact speech pair retained\n"))
      (omnivox-catalogue-library)
      (unless (equal emacsvox-aural-voice-workbench--voice-list-parent omnivox-catalogue-test--engine)
        (error "Browser lost provider scope"))
      (omnivox-catalogue-test--browser-ready)
      (emacsvox-aural-voice-workbench-quick-filter 'downloaded)
      (unless (= 1 (alist-get 'downloaded emacsvox-aural-voice-workbench--filter-counts))
        (error "Downloaded filter did not find the disabled voice"))
      (emacsvox-aural-voice-workbench-refresh
       (list omnivox-catalogue-test--engine omnivox-catalogue-test--voice))
      ;; A disabled download requires activation before its exact preview.
      (unless (condition-case nil (progn (emacsvox-aural-voice-workbench-preview) nil)
                (user-error t))
        (error "Disabled voice preview was not rejected"))
      (emacsvox-aural-voice-workbench--library-toggle)
      (omnivox-catalogue-test--browser-ready)
      (emacsvox-aural-voice-workbench-quick-filter 'needs-apply)
      (unless (equal (tabulated-list-get-id) (list omnivox-catalogue-test--engine omnivox-catalogue-test--voice))
        (error "Needs Apply lost the enabled download"))
      (let* (observed-pair
             (tts-voice-inventory-changed-hook
              (list (lambda () (setq observed-pair (list tts-speaker-process tts-notify-process))))))
        (cl-letf (((symbol-function 'omnivox-library--confirm) (lambda (&rest _) t)))
          (emacsvox-aural-voice-workbench--library-apply))
        (unless (equal observed-pair (list tts-speaker-process tts-notify-process))
          (error "Views did not receive the final published speech pair")))
      (unless (eq 'succeeded (plist-get omnivox-library-last-result :status))
        (error "Apply failed: %S" omnivox-library-last-result))
      (dolist (process (list tts-speaker-process tts-notify-process))
        (omnivox-catalogue-test--check-choice process)
        (let ((status (plist-get (omnivox-library--proof process 'speaker) :status)))
          (unless (seq-find (lambda (voice) (equal omnivox-catalogue-test--voice (plist-get voice :voice_id)))
                            (plist-get status :eligible_voices))
            (error "Downloaded voice absent from replacement worker"))))
      (when (equal omnivox-catalogue-test--engine "rhvoice")
        (dolist (process (list tts-speaker-process tts-notify-process))
          (unless (seq-some (lambda (voice) (equal (plist-get voice :voice_id) "rhvoice:Slt"))
                            (plist-get (plist-get (omnivox-library--proof process 'speaker) :status)
                                       :eligible_voices))
            (error "RHVoice Apply lost the externally installed SLT voice"))))
      (princ "PASS: explicit enable and reviewed Apply made voice eligible on both replacement workers and refreshed views\n")
      (omnivox-catalogue-test--browser-ready)
      (emacsvox-aural-voice-workbench-refresh)
      (unless (and (zerop (alist-get 'needs-apply emacsvox-aural-voice-workbench--filter-counts 0))
                   (not tabulated-list-entries))
        (error "Needs Apply did not clear after successful activation"))
      (emacsvox-aural-voice-workbench-quick-filter 'downloaded)
      (unless (equal (tabulated-list-get-id) (list omnivox-catalogue-test--engine omnivox-catalogue-test--voice))
        (error "Downloaded filter did not restore its selected voice"))
      (emacsvox-aural-voice-workbench-preview)
      (omnivox-catalogue-test--wait
       (lambda () (memq (plist-get emacsvox-aural-voice-workbench-last-preview :status) '(completed failed cancelled)))
       "Exact browser preview")
      (omnivox-catalogue-test--check-preview emacsvox-aural-voice-workbench-last-preview)
      (princ "PASS: Downloaded restored its selected voice; exact native preview completed\n")
      (let ((browser (current-buffer)) experiment)
        (emacsvox-aural-ui-goto-tabulated-column 2)
        (emacsvox-aural-voice-workbench-tune)
        (setq experiment (current-buffer))
        (let ((answers '("catalogue-acceptance" "bolden")))
          (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (pop answers))))
            (emacsvox-aural-voice-editor-keep-experiment 'physical 'preferred)))
        (emacsvox-aural-voice-editor-save)
        (omnivox-catalogue-test--wait
         (lambda ()
           (eq 'applied (emacsvox-aural-voice-save-state
                        (emacsvox-aural-voice-draft-proposal (emacsvox-aural-voice-editor--draft)))))
         "Palette save and apply")
        (let ((selector (car (plist-get (emacsvox-aural-voice-editor--working) :selectors))))
          (unless (and (equal (plist-get selector :engine-id) omnivox-catalogue-test--engine)
                       (equal (plist-get selector :voice-id) omnivox-catalogue-test--voice))
            (error "Saved palette lost the exact preferred voice")))
        (emacsvox-aural-voice-editor-play)
        (omnivox-catalogue-test--wait
         (lambda () (memq (plist-get (emacsvox-aural-voice-editor--get :preview-result) :status) '(completed failed cancelled)))
         "Saved palette preview")
        (omnivox-catalogue-test--check-preview (emacsvox-aural-voice-editor--get :preview-result))
        (emacsvox-aural-voice-editor-leave)
        (unless (eq (current-buffer) experiment) (error "Palette editor lost experiment return"))
        (emacsvox-aural-voice-editor-leave)
        (unless (and (eq (current-buffer) browser)
                     (equal (tabulated-list-get-id) (list omnivox-catalogue-test--engine omnivox-catalogue-test--voice))
                     (= 2 (emacsvox-aural-ui-tabulated-column-index)))
          (error "Editor lost browser selection or column")))
      (princ "PASS: kept exact voice in a private palette, saved, applied, previewed, and returned to browser position\n"))
  (dolist (process (list tts-speaker-process tts-notify-process))
    (when (process-live-p process) (omnivox-library--retire process))))
;;; run-live-catalogue-tests.el ends here
