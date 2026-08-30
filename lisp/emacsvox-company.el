;;; emacsvox-company.el --- Speech-enable COMPANY -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop company
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; COMPANY -mode: Complete Anything Support for emacs.
;; 
;; This module provides an Emacsvox Company Front-end, And advises
;; the needed interactive commands in Company. It adds an
;; emacsvox-specific front-end @code{emacsvox-company-frontend} to
;; the value of company-frontends. Note that @var{company-frontends}
;; is a user-customizable option and ends up getting saved by emacs
;; along with other custom settings. Function
;; @code{emacsvox-company-frontend} handles providing spoken
;; feedback, and leaves it to other frontends on
;; @var{company-frontends}   to generate their own feedback.
;;; Code:

;;; Forward variable declarations:

(defvar company-candidates)
(defvar company-selection)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(declare-function company-call-backend "company" (&rest args))
(declare-function company-fetch-metadata "company" nil)

;;;  map faces:
(voice-setup-add-map
 '(
   (company-echo voice-bolden)
   (company-echo-common voice-bolden-medium)
   (company-preview voice-lighten)
   (company-preview-common voice-lighten-medium)
   (company-preview-search voice-brighten)
   (company-template-field voice-smoothen)))

;;;  Helpers:
(defun ems-company-current ()
  "Helper: Return current selection in company."
  
  (nth company-selection company-candidates))

(defun emacsvox-company-speak-this ()
  "Formatting rule for speaking company selection."
  (let ((metadata (company-fetch-metadata)))
    (when metadata
      (setq metadata
            (propertize metadata 'personality 'voice-annotate)))
    (message (concat (ems-company-current) " " metadata))))

;;;  Emacsvox Front-End For Company:

(defun emacsvox-company-frontend (command)
  "Emacsvox front-end for Company."
  (cl-case command
    (pre-command nil)
    (post-command (emacsvox-icon 'help)
                  (emacsvox-company-speak-this))
    (hide nil)))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-company-complete-selection-before (&rest _)
  "Speak the selection."
  (when (ems-interactive-p 'company-complete-selection)
    (emacsvox-icon 'select-object) (tts-speak (ems-company-current))))

(defun emacsvox--advice-company-complete-tooltip-row-after (&rest _)
  "Speak what we completed."
  (when (ems-interactive-p 'company-complete-tooltip-row)
    (emacsvox-speak-line)))

(defun emacsvox--advice-company-show-doc-buffer-before (&rest _)
  "Speak."
  (let* ((selection (or company-selection 0))
       (selected (nth selection company-candidates))
       (doc-buffer
        (or (company-call-backend 'doc-buffer selected)
            (error "No documentation available"))))
    (when (consp doc-buffer)
      (setq doc-buffer (car doc-buffer)))
    (with-current-buffer doc-buffer (tts-speak (buffer-string)))))

(defconst emacsvox-company--advice
  '((company-complete-selection :before
     emacsvox--advice-company-complete-selection-before)
    (company-complete-tooltip-row :after
     emacsvox--advice-company-complete-tooltip-row-after)
    (company-show-doc-buffer :before
     emacsvox--advice-company-show-doc-buffer-before))
  "Current Company targets and their native advice functions.")

(defun emacsvox-company--install-advice ()
  "Install advice for the current Company API."
  (dolist (entry emacsvox-company--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

;;;  Company Setup For Emacsvox:

(defun emacsvox-company-setup ()
  "Set front-end to our  front-end action."
  
  (when (boundp 'company-frontends)
    (cl-pushnew 'emacsvox-company-frontend company-frontends))
  (add-hook
   'company-completion-started-hook
   #'(lambda (&rest _ignore) (emacsvox-icon 'open-object)))
  (add-hook
   'company-completion-finished-hook
   #'(lambda (&rest _ignore) (emacsvox-icon 'close-object))))

(with-eval-after-load 'company
  (emacsvox-company--install-advice)
  (emacsvox-company-setup))
(provide 'emacsvox-company)

;;; emacsvox-company.el ends here
