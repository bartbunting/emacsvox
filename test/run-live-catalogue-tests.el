;;; run-live-catalogue-tests.el --- Native download and Apply acceptance -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Opt-in network test in a fresh Emacs using current byte-code and a complete
;; native runtime. EMACSVOX_LIBRARY_TEST_SERVER selects the executable.
;; Windows tests also supply an empty native EMACSVOX_LIBRARY_TEST_ROOT.
;; Speech output is muted. No user profile or existing Emacs is modified.
;;; Code:
(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (require 'emacsvox-preamble)
  (require 'tts-speak)
  (require 'omnivox-voices)
  (require 'omnivox-catalogue))
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
        (omnivox-catalogue "flite")
        (goto-char (point-min))
        (unless (equal (tabulated-list-get-id) "flite-cmu-us-awb") (error "Missing AWB catalogue row"))
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
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
        (princ "PASS: accessible catalogue downloaded and installed AWB disabled; exact speech pair retained\n"))
      (omnivox-catalogue-library)
      (goto-char (point-min))
      (unless (equal omnivox-library--engine "flite") (error "Library lost provider scope"))
      (omnivox-library-toggle)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (call-interactively #'omnivox-library-apply))
      (unless (eq 'succeeded (plist-get omnivox-library-last-result :status))
        (error "Apply failed: %S" omnivox-library-last-result))
      (dolist (process (list tts-speaker-process tts-notify-process))
        (omnivox-catalogue-test--check-choice process)
        (let ((status (plist-get (omnivox-library--proof process 'speaker) :status)))
          (unless (seq-find (lambda (voice) (equal "flitevox:cmu_us_awb" (plist-get voice :voice_id)))
                            (plist-get status :eligible_voices))
            (error "Downloaded AWB absent from replacement worker"))))
      (princ "PASS: explicit enable and reviewed Apply made AWB eligible on both replacement workers\n"))
  (dolist (process (list tts-speaker-process tts-notify-process))
    (when (process-live-p process) (omnivox-library--retire process))))
;;; run-live-catalogue-tests.el ends here
