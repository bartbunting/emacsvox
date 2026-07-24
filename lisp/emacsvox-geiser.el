;;; emacsvox-geiser.el --- Speech-enable GEISER  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable GEISER An Emacs Interface to geiser
;; Keywords: Emacsvox,  Audio Desktop geiser (Scheme IDE)
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;; 
;; This file is not part of GNU Emacs, but the same permissions apply.
;; 
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNGEISER FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; geiser.el --- GNU Emacs and Scheme talk to each other
;; This module speech-enables all interactive aspects of geiser,
;; including the geiser->scheme REPL.
;; This is used by racket-mode for racket interaction,
;; And also for interacting with Guile.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (geiser-font-lock-autodoc-current-arg  voice-bolden)
   (geiser-font-lock-autodoc-identifier voice-animate)
   (geiser-font-lock-doc-button voice-bolden-extra)
   (geiser-font-lock-doc-link voice-bolden)
   (geiser-font-lock-doc-title voice-smoothen)
   (geiser-font-lock-error-link voice-annotate)
   (geiser-font-lock-image-button voice-bolden-medium)
   (geiser-font-lock-repl-input voice-lighten)
   (geiser-font-lock-repl-prompt voice-lighten)
   (geiser-font-lock-xref-header voice-smoothen)
   (geiser-font-lock-xref-link voice-bolden)))

;;;  Interactive Commands:

(defvar emacsvox-geiser--advice nil
  "Current Geiser targets and their native advice functions.")
(setq emacsvox-geiser--advice nil)

(defun emacsvox-geiser--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function)
            emacsvox-geiser--advice))))

(defun emacsvox-geiser--mode-line-feedback ()
  "Speak the mode line after changing Geiser context."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))

(emacsvox-geiser--register-after-group
 '(geiser run-geiser geiser-repl--switch-to-repl
   geiser-mode-switch-to-repl geiser-doc-switch-to-repl
   geiser-mode-switch-to-repl-and-enter geiser-show-logs)
 #'emacsvox-geiser--mode-line-feedback)

(defun emacsvox-geiser--task-feedback ()
  "Speak the current line after completing a Geiser task."
  (emacsvox-speak-line)
  (emacsvox-icon 'task-done))

(emacsvox-geiser--register-after-group
 '(geiser-compile-current-buffer geiser-compile-definition
   geiser-compile-definition-and-go geiser-compile-file geiser-eval-buffer
   geiser-eval-buffer-and-go geiser-eval-definition
   geiser-eval-definition-and-go geiser-eval-last-sexp geiser-eval-region
   geiser-eval-region-and-go geiser-expand-definition
   geiser-expand-last-sexp geiser-expand-region geiser-load-current-buffer
   geiser-load-file geiser-log-clear geiser-repl-clear-buffer
   geiser-squarify geiser-pop-symbol-stack geiser-insert-lambda)
 #'emacsvox-geiser--task-feedback)

(defun emacsvox-geiser--open-feedback ()
  "Speak the line after opening a Geiser definition or document."
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(emacsvox-geiser--register-after-group
 '(geiser-doc-edit-symbol-at-point geiser-edit-symbol-at-point
   geiser-doc-symbol-at-point geiser-doc-refresh
   geiser-doc-previous-section geiser-doc-previous
   geiser-doc-next-section geiser-doc-next geiser-doc-module
   geiser-doc-look-up-manual geiser-edit--open-next geiser-edit-module
   geiser-edit-module-at-point geiser-edit-symbol)
 #'emacsvox-geiser--open-feedback)

(defun emacsvox-geiser--selection-feedback ()
  "Speak the selected Geiser REPL line."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-geiser--register-after-group
 '(geiser-repl--bol geiser-repl--newline-and-indent)
 #'emacsvox-geiser--selection-feedback)

(defun emacsvox-geiser--movement-feedback ()
  "Speak after a large Geiser movement."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-geiser--register-after-group
 '(geiser-repl-previous-prompt geiser-repl-next-prompt
   geiser-repl--previous-error geiser-repl-tab-dwim
   geiser-xref-callees geiser-xref-callers geiser-xref-generic-methods)
 #'emacsvox-geiser--movement-feedback)

(defun emacsvox--advice-geiser-repl-exit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'geiser-repl-exit)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(push '(geiser-repl-exit :after emacsvox--advice-geiser-repl-exit-after)
      emacsvox-geiser--advice)

(defun emacsvox--advice-geiser-repl-import-module-around (orig-fun &rest args)
  "Call ORIG-FUN once, then speak imported output when interactive."
  (let ((start (point))
        (result (apply orig-fun args)))
    (when (ems-interactive-p 'geiser-repl-import-module)
      (emacsvox-icon 'task-done)
      (emacsvox-speak-region start (point)))
    result))

(push '(geiser-repl-import-module :around
        emacsvox--advice-geiser-repl-import-module-around)
      emacsvox-geiser--advice)

(defun emacsvox--advice-geiser-repl--maybe-send-around (orig-fun &rest args)
  "Call ORIG-FUN once, then speak submitted output when interactive."
  (let ((start (point))
        (result (apply orig-fun args)))
    (when (ems-interactive-p 'geiser-repl--maybe-send)
      (emacsvox-icon 'close-object)
      (emacsvox-speak-region start (point)))
    result))

(push '(geiser-repl--maybe-send :around
        emacsvox--advice-geiser-repl--maybe-send-around)
      emacsvox-geiser--advice)

(defun emacsvox--advice-geiser-repl--doc-module-after (&rest _)
  "speak."
  (when (ems-interactive-p 'geiser-repl--doc-module)
    (with-current-buffer (window-buffer (selected-window))
      (emacsvox-icon 'open-object) (emacsvox-speak-buffer))))

(push '(geiser-repl--doc-module :after
        emacsvox--advice-geiser-repl--doc-module-after)
      emacsvox-geiser--advice)

(defun emacsvox-geiser--install-advice ()
  "Install advice for the Geiser features loaded so far."
  (dolist (entry emacsvox-geiser--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(geiser geiser-compile geiser-doc geiser-edit geiser-mode
                   geiser-repl geiser-xref))
  (eval `(with-eval-after-load ',feature
           (emacsvox-geiser--install-advice))))

(provide 'emacsvox-geiser)
;;;  end of file
