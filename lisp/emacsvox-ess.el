;;; emacsvox-ess.el --- Speech-enable ESS -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ESS An Emacs Interface to R and others
;; Keywords: Emacsvox,  Audio Desktop Statistics, R
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ESS == Emacs Speaks Statistics
;; This module makes ESS speak.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Advice edeitor to speak

(defvar emacsvox-ess--advice nil
  "Current ESS targets and their native advice functions.")
(setq emacsvox-ess--advice nil)

(defun emacsvox--advice-ess-indent-command-after (&rest _)
  "Speak the line after interactive ESS indentation."
  (when (ems-interactive-p 'ess-indent-command)
    (emacsvox-speak-line)))

(push '(ess-indent-command :after
        emacsvox--advice-ess-indent-command-after)
      emacsvox-ess--advice)

(defun emacsvox--advice-ess-smart-underscore-around
    (original &rest args)
  "Call ORIGINAL once with ARGS and speak inserted text."
  (let ((start (point))
        (result (apply original args)))
    (when (ems-interactive-p 'ess-smart-underscore)
      (dtk-speak (buffer-substring start (point))))
    result))

(push '(ess-smart-underscore :around
        emacsvox--advice-ess-smart-underscore-around)
      emacsvox-ess--advice)

;;;  Structure commands 

(defun emacsvox-ess--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-ess--advice))))

(defun emacsvox-ess--structure-feedback ()
  "Speak after moving across an ESS function."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-ess--register-after-group
 '(ess-beginning-of-function ess-end-of-function)
 #'emacsvox-ess--structure-feedback)

(defun emacsvox--advice-ess-mark-function-after (&rest _)
  "Report the ESS function selected by the mark."
  (when (ems-interactive-p 'ess-mark-function)
    (emacsvox-icon 'select-object)
    (message "Marked function containing %s lines."
             (count-lines (point) (mark)))))

(push '(ess-mark-function :after emacsvox--advice-ess-mark-function-after)
      emacsvox-ess--advice)

(defun emacsvox--advice-ess-indent-exp-after (&rest _)
  "Report indenting an ESS expression."
  (when (ems-interactive-p 'ess-indent-exp)
    (emacsvox-icon 'fill-object)
    (message "Indented current s expression ")))

(push '(ess-indent-exp :after emacsvox--advice-ess-indent-exp-after)
      emacsvox-ess--advice)

;;;  Evaluators

(defun emacsvox-ess--evaluation-feedback ()
  "Confirm evaluation of ESS code."
  (emacsvox-icon 'select-object))

(emacsvox-ess--register-after-group
 '(ess-eval-function ess-eval-buffer
   ess-eval-function-and-go ess-eval-buffer-and-go
   ess-eval-line ess-eval-line-and-go
   ess-eval-paragraph ess-eval-paragraph-and-go
   ess-eval-paragraph-and-step
   ess-eval-region ess-eval-region-and-go
   ess-eval-line-and-step ess-eval-function-or-paragraph-and-step)
 #'emacsvox-ess--evaluation-feedback)

;;;  Switchers

(defun emacsvox--advice-ess-display-help-on-object-after (&rest _)
  "Announce help."
  (when (ems-interactive-p 'ess-display-help-on-object)
    (emacsvox-icon 'help) (message "Displayed help in other window.")))

(push '(ess-display-help-on-object :after
        emacsvox--advice-ess-display-help-on-object-after)
      emacsvox-ess--advice)

(defun emacsvox-ess--switch-feedback ()
  "Speak after switching between ESS buffers."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(emacsvox-ess--register-after-group
 '(ess-switch-to-ESS ess-switch-to-end-of-ESS)
 #'emacsvox-ess--switch-feedback)

(defconst emacsvox-ess--removed-targets
  '(ess-electric-brace ess-eval-chunk ess-eval-chunk-and-go
    ess-switch-to-ess)
  "Obsolete ESS commands removed or renamed in current releases.")

(defun emacsvox-ess--install-advice ()
  "Install native advice for currently loaded ESS features."
  (dolist (entry emacsvox-ess--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(ess-site ess-mode ess-inf ess-help))
  (eval
   `(with-eval-after-load ',feature
      (emacsvox-ess--install-advice))))

;;;  set up programming mode:

(add-hook 'ess-mode-hook 'emacsvox-setup-programming-mode)

(provide 'emacsvox-ess)
;;;  end of file
