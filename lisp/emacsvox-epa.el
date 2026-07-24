;;; emacsvox-epa.el --- Speech-enable GPG Helper  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable EPA An Emacs Interface to epa
;; Keywords: Emacsvox,  Audio Desktop epa
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
;; MERCHANTABILITY or FITNEPA FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EPA == EasyPG Assistant
;; Integrate GPG functionality into Emacs.
;; Speech-enable all interactive commands.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'epa)
(require 'epa-dired)
(require 'epa-file)
(require 'epa-mail)

;;;  Map Faces:
(voice-setup-add-map
 '(
   (epa-validity-high voice-animate)
   (epa-validity-medium voice-smoothen)
   (epa-validity-low voice-smoothen-extra)
   (epa-validity-disabled voice-monotone-extra)
   (epa-string voice-lighten)
   (epa-mark voice-bolden)
   (epa-field-name voice-smoothen)
   (epa-field-body voice-animate)))

;;;  Advice Interactive Commands:

(defmacro emacsvox-epa--define-operation-advice (targets)
  "Define native operation advice for each command in TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest args)
                 "Run the EPA operation quietly and cue interactive completion."
                 (ems-with-messages-silenced
                   (let ((result (apply orig-fun args)))
                     (when (ems-interactive-p ',target)
                       (emacsvox-icon 'task-done))
                     result)))
               (advice-add ',target :around #',function))))
        targets)))

(emacsvox-epa--define-operation-advice
    (epa-progress-callback-function
     epa-mail-verify
     epa-mail-import-keys
     epa-file-select-keys
     epa-insert-keys
     epa-verify-region
     epa-verify-file
     epa-verify-cleartext-in-region
     epa-sign-region
     epa-sign-file
     epa-mail-sign
     epa-mail-encrypt
     epa-mail-decrypt
     epa-import-keys-region
     epa-import-keys
     epa-import-armor-in-region
     epa-export-keys
     epa-decrypt-region
     epa-decrypt-file
     epa-decrypt-armor-in-region
     epa-encrypt-file
     epa-encrypt-region
     epa-dired-do-verify
     epa-dired-do-sign
     epa-dired-do-encrypt
     epa-dired-do-decrypt))

(add-hook
 'epa-key-list-mode-hook
 #'(lambda nil
     (when (sit-for 0.3)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line))))

(defun emacsvox--advice-epa-delete-keys-after (&rest _)
  "speak."
  (when (ems-interactive-p 'epa-delete-keys)
    (emacsvox-icon 'delete-object)))

(advice-add 'epa-delete-keys :after
            #'emacsvox--advice-epa-delete-keys-after)

(defun emacsvox--advice-epa-exit-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'epa-exit-buffer)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'epa-exit-buffer :after
            #'emacsvox--advice-epa-exit-buffer-after)

(defmacro emacsvox-epa--define-after-advice
    (targets docstring &rest body)
  "Define native after advice for TARGETS using DOCSTRING and BODY."
  (declare (indent 2) (debug (sexp stringp body)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,docstring
                 (when (ems-interactive-p ',target)
                   ,@body))
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-epa--define-after-advice
    (epa-mail-mode
     epa-global-mail-mode
     epa-file-disable
     epa-file-enable)
    "Announce the resulting EPA mode state."
  (emacsvox-speak-line)
  (emacsvox-icon 'button))

(emacsvox-epa--define-after-advice
    (epa-list-keys epa-list-secret-keys)
    "Announce an EPA key list."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defun emacsvox--advice-epa-mark-key-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p 'epa-mark-key)
    (emacsvox-speak-line) (emacsvox-icon 'mark-object)))

(advice-add 'epa-mark-key :after
            #'emacsvox--advice-epa-mark-key-after)

(defun emacsvox--advice-epa-unmark-key-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p 'epa-unmark-key)
    (emacsvox-speak-line) (emacsvox-icon 'unmark-object)))

(advice-add 'epa-unmark-key :after
            #'emacsvox--advice-epa-unmark-key-after)

(provide 'emacsvox-epa)
;;;  end of file
