;;; emacsvox-welcome-native-check.el --- Fresh native startup check -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;; Loaded only in an owned fixture Emacs before the ordinary startup file.
(require 'cl-lib)
(defvar emacsvox-welcome-check--deadline (+ (float-time) 30))
(defun emacsvox-welcome-check--finish (text status)
  (with-temp-file (getenv "EMACSVOX_WELCOME_TEST_RESULT") (insert text))
  (kill-emacs status))
(defun emacsvox-welcome-check--poll ()
  (condition-case problem
      (if (bound-and-true-p emacsvox-welcome--offered)
          (let* ((expected (getenv "EMACSVOX_WELCOME_TEST_EXPECT"))
                 (welcome (get-buffer "*Emacsvox Welcome*")))
            (unless (string-suffix-p ".elc" (symbol-file 'emacsvox-welcome))
              (error "Welcome did not load native byte-code"))
            (pcase expected
              ("show"
               (unless (and welcome (eq (window-buffer) welcome))
                 (error "Startup did not select welcome; buffer=%s input=%S/%S modified=%S enabled=%S files=%S"
                        (buffer-name (window-buffer)) emacsvox-welcome--initial-input num-input-keys
                        (buffer-modified-p) (emacsvox-welcome--enabled-p)
                        (delq nil (mapcar #'buffer-file-name (buffer-list)))))
               (emacsvox-welcome-toggle-startup)
               (when (emacsvox-welcome--enabled-p) (error "Toggle was not saved")))
              ("hide" (when welcome (error "Saved preference ignored")))
              ("file"
               (when welcome (error "Welcome replaced explicit file"))
               (unless (buffer-file-name (window-buffer)) (error "Explicit file not selected")))
              (_ (error "Invalid expected result")))
            (emacsvox-welcome-check--finish (concat "PASS: native welcome startup " expected "\n") 0))
        (if (> (float-time) emacsvox-welcome-check--deadline)
            (error "Welcome startup did not finish; startup=%S ready=%S input=%S/%S"
                   (bound-and-true-p emacsvox-welcome--startup-finished)
                   (bound-and-true-p emacsvox-welcome--ready)
                   (bound-and-true-p emacsvox-welcome--initial-input) num-input-keys)
          (run-at-time 0.25 nil #'emacsvox-welcome-check--poll)))
    (error (emacsvox-welcome-check--finish (error-message-string problem) 1))))
(if (equal (getenv "EMACSVOX_WELCOME_TEST_EXPECT") "speech-check")
    ;; Exercise the readiness race: start the dedicated speech check before
    ;; registration arrives, so the ready timer would compete with its sample.
    (advice-add 'run-at-time :around
                (lambda (function time repeat callback &rest args)
                  (apply function (if (eq callback 'emacsvox-windows-check) 0 time)
                         repeat callback args)))
  (add-hook 'emacs-startup-hook
            (lambda () (run-at-time 0.5 nil #'emacsvox-welcome-check--poll))))
