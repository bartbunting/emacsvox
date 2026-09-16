;;; run-live-mbrola-library-tests.el --- Native MBROLA Apply acceptance -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Use the private root produced by Omnivox's verify_mbrola_library.py.
;; Requires current byte-code, EMACSVOX_LIBRARY_TEST_SERVER,
;; EMACSVOX_LIBRARY_TEST_ROOT and the explicit OMNIVOX_MBROLA_HELPER.

(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (require 'emacsvox-preamble)
  (require 'tts-speak)
  (require 'omnivox-voices)
  (require 'omnivox-library)
  (setq emacsvox-servers-directory (expand-file-name "servers/" root)))

(dolist (name '("EMACSVOX_LIBRARY_TEST_SERVER" "EMACSVOX_LIBRARY_TEST_ROOT" "OMNIVOX_MBROLA_HELPER"))
  (unless (getenv name) (error "Missing isolated test setting: %s" name)))
(dolist (function '(tts-make-process omnivox-library-apply omnivox-library--managed-providers))
  (unless (string-suffix-p ".elc" (or (symbol-file function) ""))
    (error "Expected current byte-code for %s" function)))
(dolist (name '("OMNIVOX_VOICE_LIBRARY" "OMNIVOX_PIPER_MODEL" "OMNIVOX_FLITE_VOICES"
                "OMNIVOX_OWNED_STARTUP" "OMNIVOX_OWNED_STARTUP_SHA256" "OMNIVOX_OWNED_LIBRARY"))
  (setenv name nil))
(setenv "OMNIVOX_PROGRAM" (getenv "EMACSVOX_LIBRARY_TEST_SERVER"))
(setenv "OMNIVOX_VOICE_ROOT" (getenv "EMACSVOX_LIBRARY_TEST_ROOT"))
(setenv "OMNIVOX_ENGINE" "espeak")
(setenv "OMNIVOX_AUDIO_OUTPUT" "null")
(setenv "OMNIVOX_LOG_DIRECTORY" (make-temp-file "omnivox-mbrola-apply-" t))
(setq tts-program "omnivox" emacsvox-speak-messages nil tts-notification-device "both")

(cl-labels
    ((call (command &rest fields)
       (let ((service (omnivox-library--service)))
         (unwind-protect
             (omnivox-library--request service (append (list :command command) fields))
           (delete-process service))))
     (enable (enabled)
       (call "enable" :engine "mbrola" :voice "mbrola:v1/mb-us1/us1" :enabled enabled
             :expected_sha256 (plist-get (call "inspect") :sha256)))
     (apply-library (expected)
       (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
         (let ((result (omnivox-library-apply "both")))
           (unless (eq (plist-get result :status) expected)
             (error "Apply expected %s: %S" expected result))
           (princ (format "Apply %s\n" expected)))))
     (check (us1-enabled)
       (dolist (process (list tts-speaker-process tts-notify-process))
         (let* ((status (plist-get (omnivox-library--proof process 'speaker) :status))
                (ids (mapcar (lambda (voice) (plist-get voice :voice_id))
                             (append (plist-get status :eligible_voices) nil))))
           (unless (and (member "mbrola:v1/mb-en1/en1" ids)
                        (eq us1-enabled (and (member "mbrola:v1/mb-us1/us1" ids) t)))
             (error "Unexpected MBROLA eligibility: %S" ids))))))
  (unwind-protect
      (progn
        (let ((initial (call "inspect")))
          (unless (and (eq (plist-get initial :active) :null)
                       (= 4 (length (plist-get (plist-get initial :index) :voices))))
            (error "Use the isolated four-voice root from verify_mbrola_library.py")))
        (setq tts-speaker-process (tts-make-process "Speaker"))
        (tts-notify-initialize)
        (dolist (process (list tts-speaker-process tts-notify-process))
          (omnivox--negotiate-process process)
          (omnivox-library--wait
           (lambda () (process-get process 'omnivox-library-accepted-registration))
           process "Initial pair registration"))
        (enable t)
        (apply-library 'succeeded)
        (check t)
        (enable :false)
        (let ((ready (symbol-function 'omnivox-library--ready)) (count 0)
              (active (plist-get (call "inspect") :active)))
          (cl-letf (((symbol-function 'omnivox-library--ready)
                     (lambda (process startup)
                       (cl-incf count)
                       (when (= count 4)
                         (omnivox-library--retire process)
                         (error "Injected notification replacement failure"))
                       (funcall ready process startup))))
            (apply-library 'rolled-back))
          (unless (equal active (plist-get (call "inspect") :active))
            (error "Rollback changed the active pointer")))
        (check t)
        (apply-library 'succeeded)
        (check nil)
        (princ "PASS: compiled MBROLA Apply, two-stream eligibility, rollback and independent disablement\n"))
    (dolist (process (list tts-speaker-process tts-notify-process))
      (when (process-live-p process) (omnivox-library--retire process)))))
