;;; emacsvox-iedit.el --- Speech-enable IEDIT  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable IEDIT An Emacs Interface to iedit
;; Keywords: Emacsvox,  Audio Desktop iedit
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
;; MERCHANTABILITY or FITNIEDIT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; IEDIT ==  Edit multiple regions
;; This module speech-enables iedit.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (iedit-occurrence voice-overlay-1)
   (iedit-read-only-occurrence voice-monotone-extra)))

;;;  Interactive Commands:

'(
  iedit-apply-global-modification
  iedit-execute-last-modification
  iedit-expand-down-a-line
  iedit-expand-down-to-occurrence
  iedit-expand-up-a-line
  iedit-expand-up-to-occurrence
  iedit-number-occurrences
  iedit-replace-occurrences
  iedit-restrict-current-line
  iedit-restrict-function

  )

(defvar emacsvox-iedit--advice nil
  "Current Iedit targets and their native advice functions.")
(setq emacsvox-iedit--advice nil)

(defun emacsvox--advice-iedit-mode-after (&rest _)
  "speak." 
  (when (ems-interactive-p 'iedit-mode)
    (emacsvox-icon (if iedit-mode 'on 'off))))

(push '(iedit-mode :after emacsvox--advice-iedit-mode-after)
      emacsvox-iedit--advice)

(defun emacsvox--advice-iedit-done-after (&rest _)
  "speak." (emacsvox-icon 'close-object) (message "IEdit done"))

(push '(iedit-done :after emacsvox--advice-iedit-done-after)
      emacsvox-iedit--advice)

(defun emacsvox-iedit--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback ',target))))
      (push (list target :after advice-function)
            emacsvox-iedit--advice))))

(defun emacsvox-iedit--movement-feedback (_target)
  "Speak after moving to another Iedit occurrence."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-iedit--register-after-group
 '(iedit-prev-occurrence iedit-next-occurrence
   iedit-goto-last-occurrence iedit-goto-first-occurrence)
 #'emacsvox-iedit--movement-feedback)

(defun emacsvox-iedit--help-feedback (_target)
  "Play the help icon after an Iedit help command."
  (emacsvox-icon 'help))

(emacsvox-iedit--register-after-group
 '(iedit-describe-bindings iedit-describe-key iedit-describe-mode)
 #'emacsvox-iedit--help-feedback)

(defun emacsvox-iedit--task-feedback (target)
  "Announce completion of Iedit command TARGET."
  (emacsvox-icon 'task-done)
  (message "%s" target))

(emacsvox-iedit--register-after-group
 '(iedit-upcase-occurrences iedit-downcase-occurrences
   iedit-blank-occurrences iedit-delete-occurrences)
 #'emacsvox-iedit--task-feedback)

(defun emacsvox--advice-iedit-show/hide-lines-after (&rest _)
  "speak."
  (when (memq ems--interactive-fn-name
              '(iedit-show/hide-context-lines
                iedit-show/hide-occurrence-lines))
    (emacsvox-speak-line)
    (emacsvox-icon (if iedit-hiding 'on 'off))))

(dolist (target '(iedit-show/hide-context-lines
                  iedit-show/hide-occurrence-lines))
  (push (list target :after
              'emacsvox--advice-iedit-show/hide-lines-after)
        emacsvox-iedit--advice))

(defun emacsvox-iedit--install-advice ()
  "Install native advice after Iedit loads."
  (dolist (entry emacsvox-iedit--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'iedit
  (emacsvox-iedit--install-advice))

(provide 'emacsvox-iedit)
;;;  end of file
