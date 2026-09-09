;;; diagnose-choice-queue.el --- Legacy queue handoff observations -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run with the Emacs selected by local.mk, using -Q --batch -l this file.
;; Source-only, synthetic voices and muted writes. These observations reproduce
;; the review baseline; successful execution does not mean the gaps are fixed.
;;; Code:
(setq load-prefer-newer t)
(let* ((tests (file-name-directory (or load-file-name buffer-file-name)))
       (lisp (expand-file-name "../lisp" tests)))
  (add-to-list 'load-path lisp)
  (add-to-list 'load-path tests)
  (dolist (file '("emacsvox-preamble.el" "tts-speak.el"
                  "emacsvox-aural-compiler.el" "emacsvox-aural-planner.el"
                  "emacsvox-aural-transport.el" "omnivox-choice-codec.el"
                  "omnivox-voices.el" "emacsvox-speak.el"))
    (load (expand-file-name file lisp) nil t)))
(require 'omnivox-choice-consumer-tests)

(defun emacsvox-choice-queue-diagnostic--raw ()
  "Queue synthetic named speech without dispatch."
  (tts-speak-using-voice 'voice-bolden "RAW"))

(defun emacsvox-choice-queue-diagnostic--normal ()
  "Submit synthetic ordinary speech through the public producer."
  (tts-speak (propertize "NORMAL" 'personality 'voice-bolden)))

(dolist (case '((raw-only t raw)
                (raw-normal t raw normal)
                (normal-raw t normal raw)
                (normal-raw-dispatch t normal raw dispatch)
                (normal-normal t normal normal)
                (raw-dispatch-normal t raw dispatch normal)
                (normal-code t normal code)
                (normal-letter t normal letter)
                (letter-normal t letter normal)
                (outside-raw nil raw)
                (outside-raw-dispatch nil raw dispatch)
                (outside-raw-normal nil raw normal)
                (normal-rate-change t normal faster-normal)
                (named-tracked-dispatch t raw tracked-dispatch)
                (named-marked-dispatch t raw marked-dispatch)
                (nested-tracked-normal t tracked-normal)))
  (omnivox-choice-consumer-test--with-speech
   (let (failure
         (run (lambda ()
                (dolist (step (cddr case))
                  (pcase step
                    ('raw (emacsvox-choice-queue-diagnostic--raw))
                    ('normal (emacsvox-choice-queue-diagnostic--normal))
                    ('faster-normal
                     (let ((tts-speech-rate 200))
                       (emacsvox-choice-queue-diagnostic--normal)))
                    ('tracked-normal
                     (tts-speak-tracked (propertize "NORMAL" 'personality 'voice-bolden) #'ignore))
                    ('dispatch (tts--protocol-dispatch))
                    ('tracked-dispatch (tts--protocol-dispatch-tracked #'ignore))
                    ('marked-dispatch (tts--protocol-dispatch-marked #'ignore #'ignore))
                    ('code (tts--protocol-queue-code "[[pitch 1.1]]"))
                    ('letter (tts-letter "B")))))))
     (condition-case error-data
         (if (cadr case)
             (emacsvox-aural-call-with-delivery-transaction speaker run)
           (funcall run))
       (error (setq failure error-data)))
     (let ((wire (mapconcat #'cdr (reverse writes) "")))
       (princ (format "%S %S%s\n" (car case)
                      (split-string
                       (replace-regexp-in-string
                        "emacsvox_timeline {[^}]*}" "TIMELINE" wire)
                       "\n" t)
                      (if failure (format " error=%S" failure) "")))))))

;;; diagnose-choice-queue.el ends here
