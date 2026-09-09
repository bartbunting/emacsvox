;;; diagnose-prepared-cancellation.el --- Prepared Stop ordering -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run in a fresh batch Emacs. All writes are substituted; no engine is started.
;; This characterizes ordering without asserting that a defect must persist.
;; See docs/voice-editor-client-handoff-review.org for the pending XHI boundary.

;;; Code:
(unless noninteractive (error "Run this diagnostic in a fresh batch Emacs"))
(setq load-prefer-newer t)
(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (add-to-list 'load-path (expand-file-name "test/" root))
  (dolist (file '("emacsvox-preamble.el" "tts-speak.el" "omnivox-choice-codec.el"
                  "emacsvox-aural-transport.el" "omnivox-voices.el"))
    (load (expand-file-name file (expand-file-name "lisp/" root)) nil t)))
(require 'omnivox-choice-playback-tests)

(dolist (version '(3 4))
  (dolist (second-stop '(nil t))
    (omnivox-choice-playback-test--with-runtime
     (process-put speaker emacsvox-aural--structured-timeline-process-property version)
     (let ((emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-submission-delivery-policy 'urgent)
           injected commands result)
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (_owner command)
                    (push command commands)
                    (when (and second-stop (equal command "s\n") (not injected))
                      (setq injected t)
                      (tts-stop t)))))
         (setq result (omnivox-choice-playback-test--submit)))
       (princ (format "version=%d second-stop=%S returned-id=%S timeline-written=%S observing=%S\n"
                      version injected result
                      (cl-some (lambda (command) (string-prefix-p "emacsvox_timeline " command)) commands)
                      (and result (tts--dispatch-observing-p (tts--dispatch-owner-for speaker result)))))))))

;;; diagnose-prepared-cancellation.el ends here
