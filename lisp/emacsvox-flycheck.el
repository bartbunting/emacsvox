;;; emacsvox-flycheck.el --- Speech-enable FLYCHECK -*- lexical-binding: t; -*-
;; $Id: emacsvox-flycheck.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable FLYCHECK An Emacs Interface to flycheck
;; Keywords: Emacsvox,  Audio Desktop flycheck
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
;; MERCHANTABILITY or FITNFLYCHECK FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; FLYCHECK == On-the-fly checking.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map faces

(voice-setup-add-map
 '(
   (flycheck-warning voice-animate)
   (flycheck-error voice-bolden)
   (flycheck-info voice-monotone-extra)
   (flycheck-error-list-highlight-at-point voice-bolden-extra)
   (flycheck-error-list-highlight voice-bolden-medium)
   (flycheck-error-list-line-number voice-lighten)
   (flycheck-error-list-info voice-monotone-extra)
   (flycheck-error-list-warning voice-animate)
   (flycheck-error-list-error voice-bolden)))

;;;  Advice interactive commands.

(cl-loop
 for target in
 '(flycheck-next-error flycheck-previous-error flycheck-first-error)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defun emacsvox--advice-flycheck-list-errors-after (&rest _)
  "speak."
  (when (ems-interactive-p 'flycheck-list-errors)
    (emacsvox-icon 'task-done)
    (tts-speak "Displayed error listing in other window.")))

(defun emacsvox--advice-flycheck-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'flycheck-buffer)
    (emacsvox-icon 'task-done) (tts-speak "Checking buffer.")))

(defun emacsvox--advice-flycheck-clear-after (&rest _)
  "speak."
  (when (ems-interactive-p 'flycheck-clear)
    (emacsvox-icon 'task-done) (tts-speak "Cleared errors")))

(defun emacsvox--advice-flycheck-compile-after (&rest _)
  "speak."
  (when (ems-interactive-p 'flycheck-compile)
    (emacsvox-icon 'task-done) (tts-speak "Compiling buffer")))

(defun emacsvox--advice-flycheck-error-list-refresh-after (&rest _)
  "speak."
  (when (ems-interactive-p 'flycheck-error-list-refresh)
    (emacsvox-icon 'task-done) (tts-speak "Refreshed errors")))

(defconst emacsvox-flycheck--advice
  '((flycheck-next-error
     emacsvox--advice-flycheck-next-error-after)
    (flycheck-previous-error
     emacsvox--advice-flycheck-previous-error-after)
    (flycheck-first-error
     emacsvox--advice-flycheck-first-error-after)
    (flycheck-list-errors
     emacsvox--advice-flycheck-list-errors-after)
    (flycheck-buffer emacsvox--advice-flycheck-buffer-after)
    (flycheck-clear emacsvox--advice-flycheck-clear-after)
    (flycheck-compile emacsvox--advice-flycheck-compile-after)
    (flycheck-error-list-refresh
     emacsvox--advice-flycheck-error-list-refresh-after))
  "Current Flycheck targets and their native advice functions.")

(defun emacsvox-flycheck--install-advice ()
  "Install advice after the optional Flycheck package loads."
  (dolist (entry emacsvox-flycheck--advice)
    (pcase-let ((`(,target ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'flycheck
  (emacsvox-flycheck--install-advice))

(provide 'emacsvox-flycheck)
;;; emacsvox-flycheck ends here
;;;  end of file
