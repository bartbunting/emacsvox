;;; run-core-advice-tests.el --- Verify core advice boundaries -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Run with Emacs -Q --batch -l test/run-core-advice-tests.el.
;; Set EMACSVOX_CORE_ADVICE_TEST_LOAD=compiled after make bytecode to verify
;; fresh byte-code.  Otherwise load the affected modules explicitly from source.
;; Definition modules must leave advice, hooks and error-handler selection to
;; the facade.  Reuse the existing behavioral and registration contracts.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'subr-x)

(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (compiled (equal (getenv "EMACSVOX_CORE_ADVICE_TEST_LOAD") "compiled"))
       (extension (if compiled ".elc" ".el"))
       (modules '(("emacsvox-advice-completion" . emacsvox--completion-around)
                  ("emacsvox-advice-input" . emacsvox-minibuffer-setup-hook)))
       (targets '(pcomplete completion-at-point read-event read-passwd--hide-password
                  y-or-n-p message timer-event-handler))
       (variables '(minibuffer-setup-hook minibuffer-exit-hook
                    eldoc-display-functions command-error-function)))
  (setq load-prefer-newer (not compiled))
  (dolist (directory '("lisp" "test" "utils"))
    (add-to-list 'load-path (expand-file-name directory root)))
  (setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" root))
  (require 'emacsvox-preamble)
  (cl-labels
      ((registrations ()
         (mapcar
          (lambda (target)
            (let (entries)
              (advice-mapc (lambda (function properties)
                            (push (cons function properties) entries)) target)
              (cons target entries)))
          targets))
       (state ()
         (mapcar (lambda (variable)
                   (list variable (boundp variable)
                         (and (boundp variable) (copy-tree (symbol-value variable)))))
                 variables)))
    (let ((before-advice (registrations))
          (before-state (state))
          (before-processes (process-list)))
      (dolist (module modules)
        (load (expand-file-name
               (concat "lisp/core/" (car module) extension) root) nil t t))
      (when (featurep 'emacsvox-advice)
        (error "Advice definitions loaded the activation facade"))
      (unless (and (equal before-advice (registrations))
                   (equal before-state (state))
                   (equal before-processes (process-list)))
        (error "Advice definitions changed runtime activation"))))
  (load (expand-file-name (concat "lisp/core/emacsvox-advice" extension) root) nil t t)
  ;; ERT reports must not reach the speech backend after delivery stubs unwind.
  (setq-default emacsvox-speak-messages nil)
  (dolist (name '(advice advice-audit core-migration completion input message search
                 timer tooltip overlay navigation help region eval formatting
                 narrowing button register keymap speak))
    (load (expand-file-name (format "test/emacsvox-%s-tests.el" name) root) nil t t))
  (dolist (module (cons '("emacsvox-advice" . emacsvox--advice-next-line-around) modules))
    (let ((expected (expand-file-name
                     (concat "lisp/core/" (car module) extension) root))
          (actual (symbol-file (cdr module) 'defun)))
      (unless (equal expected actual)
        (error "Wrong owner for %S: expected %s, got %s" (cdr module) expected actual))
      (message "%s: %s" (cdr module) actual))))

;; This existing scrolling fixture replaces two defsubst functions.  Its mocks
;; cannot intercept compiled callers; the same failure occurs before extraction.
;; Keep it in the source run and report its exclusion from compiled verification.
(if (equal (getenv "EMACSVOX_CORE_ADVICE_TEST_LOAD") "compiled")
    (progn
      (message "Source-only fixture excluded: emacsvox-core-scroll-advice-preserves-semantic-feedback (inlined helpers)")
      (ert-run-tests-batch-and-exit
       '(not (member emacsvox-core-scroll-advice-preserves-semantic-feedback))))
  (ert-run-tests-batch-and-exit))

;;; run-core-advice-tests.el ends here
