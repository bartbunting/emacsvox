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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

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

(cl-loop
 for f in
 '(
   epa-progress-callback-function
   epa-mail-verify epa-mail-import-keys
   epa-file-select-keys epa-insert-keys
   epa-verify-region epa-verify-file epa-verify-cleartext-in-region
   epa-sign-region epa-sign-file epa-mail-sign
   epa-mail-encrypt epa-mail-decrypt
   epa-import-keys-region epa-import-keys
   epa-import-armor-in-region epa-export-keys
   epa-decrypt-region epa-decrypt-file epa-decrypt-armor-in-region
   epa-encrypt-file epa-encrypt-region
   epa-dired-do-verify epa-dired-do-sign
   epa-dired-do-encrypt epa-dired-do-decrypt
   )
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "speak. "
     (ems-with-messages-silenced
      ad-do-it
      (when (ems-interactive-p) (emacsvox-icon 'task-done))))))

(add-hook
 'epa-key-list-mode-hook
 #'(lambda nil
     (when (sit-for 0.3)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line))))

(defun ems--epa-delete-keys-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'delete-object)))

(advice-add 'epa-delete-keys :after #'ems--epa-delete-keys-after)

(defun ems--epa-exit-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'epa-exit-buffer :after #'ems--epa-exit-buffer-after)

(cl-loop
 for f in
 '(
   epa-mail-mode epa-global-mail-mode
   epa-file-disable epa-file-enable)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak. "
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'button)))))

(cl-loop
 for f in
 '(epa-list-keys epa-list-secret-keys)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak. "
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-mode-line)))))

(defun ems--epa-mark-key-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'mark-object)))

(advice-add 'epa-mark-key :after #'ems--epa-mark-key-after)

(defun ems--epa-unmark-key-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'unmark-object)))

(advice-add 'epa-unmark-key :after #'ems--epa-unmark-key-after)

(provide 'emacsvox-epa)
;;;  end of file

