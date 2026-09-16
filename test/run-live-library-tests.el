;;; run-live-library-tests.el --- Isolated native Apply acceptance -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Opt-in, muted acceptance using actual workers and helpers.  Run in a fresh
;; selected Emacs with -Q --batch -l this file after make bytecode-check.
;; EMACSVOX_LIBRARY_TEST_SERVER names a complete staged native server payload.
;; For WSL, EMACSVOX_LIBRARY_TEST_ROOT must name a fresh native Windows directory.
;; No user's live Emacs, voices, or speech process is used.  Native records are
;; retained in the printed test root for inspection; they contain private inputs.

;;; Code:

(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (require 'emacsvox-preamble)
  (require 'tts-speak)
  (require 'omnivox-voices)
  (require 'omnivox-library)
  (setq emacsvox-servers-directory (expand-file-name "servers/" root)))

(setq tts-program "omnivox" emacsvox-speak-messages nil
      tts-notification-device "both" debug-on-error t)
(unless (getenv "EMACSVOX_LIBRARY_TEST_SERVER")
  (error "Set EMACSVOX_LIBRARY_TEST_SERVER to a complete staged server"))
(dolist (function '(tts-make-process omnivox-library-apply omnivox--negotiate-process))
  (unless (string-suffix-p ".elc" (or (symbol-file function) ""))
    (error "Expected current byte-code for %s" function)))

;; Avoid inheriting the maintainer's file overrides or active profile.
(dolist (name '("OMNIVOX_VOICE_LIBRARY" "OMNIVOX_PIPER_MODEL" "OMNIVOX_FLITE_VOICES"
                "OMNIVOX_OWNED_STARTUP" "OMNIVOX_OWNED_STARTUP_SHA256" "OMNIVOX_OWNED_LIBRARY"))
  (setenv name nil))
(setenv "OMNIVOX_PROGRAM" (getenv "EMACSVOX_LIBRARY_TEST_SERVER"))
(when (and (string-suffix-p ".exe" (getenv "OMNIVOX_PROGRAM"))
           (not (getenv "EMACSVOX_LIBRARY_TEST_ROOT")))
  (error "Supply a fresh native Windows EMACSVOX_LIBRARY_TEST_ROOT"))
(setenv "OMNIVOX_VOICE_ROOT"
        (or (getenv "EMACSVOX_LIBRARY_TEST_ROOT") (make-temp-file "omnivox-emacs-apply-" t)))
(setenv "OMNIVOX_ENGINE" "espeak")
(setenv "OMNIVOX_AUDIO_OUTPUT" "null")
(setenv "OMNIVOX_LOG_DIRECTORY" (make-temp-file "omnivox-apply-logs-" t))

(defun omnivox-library-test--inspect ()
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (omnivox-library--request service '(:command "inspect"))
      (delete-process service))))

(defun omnivox-library-test--apply (expected &optional providers)
  (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
    (let ((result (omnivox-library-apply (or providers "flite"))))
      (princ (format "Apply: %S\n" result))
      (unless (eq (plist-get result :status) expected)
        (error "Expected %s, got %S" expected result))
      result)))

(defun omnivox-library-test--pair ()
  (mapcar (lambda (process)
            (plist-get (omnivox-library--proof process 'speaker) :status))
          (list tts-speaker-process tts-notify-process)))

(defun omnivox-library-test--slt (enabled)
  (dolist (status (omnivox-library-test--pair))
    (unless (eq enabled (and (seq-find
                             (lambda (voice) (and (equal (plist-get voice :engine_id) "flite")
                                                   (equal (plist-get voice :voice_id) "cmu_us_slt")))
                             (plist-get status :eligible_voices)) t))
      (error "Unexpected Flite SLT eligibility; expected enabled=%s" enabled))))

(unwind-protect
    (progn
      (let ((initial (omnivox-library-test--inspect)))
        (unless (and (eq (plist-get initial :active) :null)
                     (zerop (length (plist-get (plist-get initial :index) :voices))))
          (error "Acceptance requires an empty isolated native voice root")))
      (setq tts-speaker-process (tts-make-process "Speaker"))
      (tts-notify-initialize)
      (dolist (process (list tts-speaker-process tts-notify-process))
        (omnivox--negotiate-process process))
      (dolist (process (list tts-speaker-process tts-notify-process))
        (omnivox-library--wait
         (lambda () (process-get process 'omnivox-library-accepted-registration))
         process "Initial pair registration"))
      (let ((service (omnivox-library--service)))
        (unwind-protect
            (omnivox-library--request service
              (list :command "include-flite-slt"
                    :expected_sha256 (plist-get (omnivox-library-test--inspect) :sha256)))
          (delete-process service)))
      (omnivox-library-test--apply 'succeeded)
      (omnivox-library-test--slt t)
      (princ "Enabled SLT is eligible on both real workers\n")
      (let ((execute (symbol-function 'omnivox-library--execute))
            (old-pair (list tts-speaker-process tts-notify-process)))
        (cl-letf (((symbol-function 'omnivox-library--execute)
                   (lambda (&rest args)
                     (let ((inhibit-quit t) (quit-flag t)) (apply execute args)))))
          (omnivox-library-test--apply 'cancelled))
        (unless (equal old-pair (list tts-speaker-process tts-notify-process))
          (error "Early cancellation replaced the original pair")))
      (princ "Cancellation before admission left the exact original pair intact\n")
      (let ((service (omnivox-library--service)))
        (unwind-protect
            (omnivox-library--request service
              (list :command "enable" :engine "flite" :voice "cmu_us_slt" :enabled :false
                    :expected_sha256 (plist-get (omnivox-library-test--inspect) :sha256)))
          (delete-process service)))
      (let ((ready (symbol-function 'omnivox-library--ready)) (count 0)
            (before (omnivox-library-test--pair))
            (active (plist-get (omnivox-library-test--inspect) :active)))
        (cl-letf (((symbol-function 'omnivox-library--ready)
                   (lambda (process startup)
                     (cl-incf count)
                     (when (= count 4)
                       (omnivox-library--retire process)
                       (error "Injected loss of the real notification replacement"))
                     (funcall ready process startup))))
          (omnivox-library-test--apply 'rolled-back))
        (unless (and (equal (mapcar (lambda (status) (plist-get status :configuration)) before)
                            (mapcar (lambda (status) (plist-get status :configuration))
                                    (omnivox-library-test--pair)))
                     (equal active (plist-get (omnivox-library-test--inspect) :active)))
          (error "Rollback changed the previous configurations or active pointer")))
      (omnivox-library-test--slt t)
      (princ "Real paired rollback preserved the old enabled voice and pointer\n")
      (let ((make (symbol-function 'tts-make-process)) (count 0))
        (cl-letf (((symbol-function 'tts-make-process)
                   (lambda (name)
                     (cl-incf count)
                     (let ((omnivox--library-startup
                            (if (= count 4)
                                (plist-put (copy-sequence omnivox--library-startup) :path
                                           (concat (plist-get omnivox--library-startup :path) ".missing"))
                              omnivox--library-startup)))
                       (funcall make name)))))
          (omnivox-library-test--apply 'rolled-back)))
      (omnivox-library-test--slt t)
      (princ "Native startup refusal rolled back both workers\n")
      (let ((retire (symbol-function 'omnivox-library--retire))
            (old-notification tts-notify-process))
        (cl-letf (((symbol-function 'omnivox-library--retire)
                   (lambda (process)
                     (prog1 (funcall retire process)
                       (when (eq process old-notification) (setq quit-flag t))))))
          (unless (plist-get (omnivox-library-test--apply 'rolled-back) :cancel-requested)
            (error "Cancellation was not recorded"))))
      (omnivox-library-test--slt t)
      (princ "Cancellation after retirement restored both previous workers\n")
      (omnivox-library-test--apply 'succeeded)
      (omnivox-library-test--slt nil)
      (princ "Second commit disabled SLT on both workers and replaced the active pointer\n")
      (when-let* ((operation (getenv "EMACSVOX_LIBRARY_TEST_IMPORT")))
        (with-temp-buffer
          (omnivox-library-mode)
          (omnivox-library-refresh)
          (omnivox-library-import-validated operation))
        (let* ((library (omnivox-library-test--inspect))
               (voices (seq-filter (lambda (voice) (equal (plist-get voice :engine_id) "piper"))
                                   (plist-get (plist-get library :index) :voices)))
               (id (plist-get (elt voices 1) :physical_id)))
          (unless (and (= (length voices) 2)
                       (seq-every-p (lambda (voice) (eq (plist-get voice :enabled) :false)) voices))
            (error "Native Piper import did not start with both speakers disabled"))
          (dolist (enabled '(t :false))
            (let ((service (omnivox-library--service)))
              (unwind-protect
                  (omnivox-library--request service
                    (list :command "enable" :engine "piper" :voice id :enabled enabled
                          :expected_sha256 (plist-get (omnivox-library-test--inspect) :sha256)))
                (delete-process service)))
            (omnivox-library-test--apply 'succeeded "both")
            (dolist (status (omnivox-library-test--pair))
              (let ((actual (seq-filter (lambda (voice) (equal (plist-get voice :engine_id) "piper"))
                                        (plist-get status :eligible_voices))))
                (unless (equal (mapcar (lambda (voice) (plist-get voice :voice_id)) (append actual nil))
                               (when (eq enabled t) (list id)))
                  (error "Piper speaker enablement differs from desired state")))))
          (princ "Validated Piper import starts disabled; Apply enables only the selected speaker, then disables it on both workers\n"))))
  (dolist (process (list tts-speaker-process tts-notify-process))
    (when (process-live-p process) (omnivox-library--retire process)))
  (princ (format "Native test root retained: %s\n" (getenv "OMNIVOX_VOICE_ROOT"))))

;;; run-live-library-tests.el ends here
