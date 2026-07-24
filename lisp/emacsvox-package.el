;;; emacsvox-package.el --- Speech-enable PACKAGE  -*- lexical-binding: t; -*-
;; $Id: emacsvox-package.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable PACKAGE An Emacs Interface to package
;; Keywords: Emacsvox,  Audio Desktop package
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
;; MERCHANTABILITY or FITNPACKAGE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; PACKAGE == package.el
;; Manage Emacs packages.
;; This module speech-enables package.el with a few convenience commands.

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'calendar)
(require 'package)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (package-help-section-name voice-lighten)
   (package-name voice-bolden)
   (package-description voice-lighten)
   (package-status-built-in voice-monotone-medium)
   (package-status-external voice-animate)
   (package-status-available voice-annotate)
   (package-status-new voice-brighten)
   (package-status-held voice-monotone-extra)
   (package-status-disabled voice-smoothen)
   (package-status-installed voice-lighten-extra)
   (package-status-dependency voice-monotone-medium)
   (package-status-unsigned voice-animate-extra)
   (package-status-incompat voice-animate-extra)
   (package-status-avail-obso voice-monotone-extra)
   ))

;;;  Additional Commands

(defun emacsvox-package-summarize-line ()
  "Succinct Summary."
  (interactive)
  (let* ((entry   (get-text-property (point) 'tabulated-list-entry))
         (name (copy-sequence (cl-first (aref entry 0))))
         (desc (aref entry 4))
         (state (aref entry 2)))
    (cond
     ((string= state "installed")
      (emacsvox-icon 'select-object))
     ((string= state "built-in")
      (emacsvox-icon 'mark-object))
     ((string= state "dependency")
      (emacsvox-icon 'close-object))
     ((string= state "obsolete")
      (emacsvox-icon 'deselect-object))
     ((string= state "incompat")
      (emacsvox-icon 'alert-user))
     (t (emacsvox-icon 'item)))
    (put-text-property 0 (length name)
                       'personality voice-bolden-medium name)
    (message  (concat name ": "desc))))

(defun emacsvox-package-next-line ()
  "Move to next line and speak it."
  (interactive)
  (forward-line 1)
  (emacsvox-package-summarize-line))

(defun emacsvox-package-previous-line ()
  "Move to next line and speak it."
  (interactive)
  (forward-line -1)
  (emacsvox-package-summarize-line))

(defun emacsvox-package-mode-hook ()
  "Emacsvox setup hook for package-mode."
  (define-key package-menu-mode-map " " 'emacsvox-package-summarize-line)
  (define-key package-menu-mode-map "n" 'emacsvox-package-next-line)
  (define-key package-menu-mode-map "p" 'emacsvox-package-previous-line)
  (emacsvox-pronounce-add-local-entry
   emacsvox-pronounce-date-yyyymmdd-pattern
   (cons #'re-search-forward 'emacsvox-pronounce-yyyymmdd-date)))

(add-hook 'package-menu-mode-hook 'emacsvox-package-mode-hook)

;;;  Managing packages:

(defun emacsvox--advice-package-menu-describe-package-after (&rest _)
  "Speak displayed description."
  (when (ems-interactive-p 'package-menu-describe-package)
    (emacsvox-icon 'help) (emacsvox-speak-help)))

(advice-add 'package-menu-describe-package :after
            #'emacsvox--advice-package-menu-describe-package-after)

(defun emacsvox--advice-package-menu-execute-around (orig-fun &rest args)
  "Silence messages while installing packages. "
  (let ((result
         (ems-with-messages-silenced
           (apply orig-fun args))))
    (emacsvox-speak-message-again)
    result))

(advice-add 'package-menu-execute :around
            #'emacsvox--advice-package-menu-execute-around)

(cl-loop
 for target in
 '(
   package-menu-mark-delete package-menu-mark-install package-show-package-list
   package-menu-mark-unmark package-menu-backup-unmark)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak and cue an interactive Package menu marking command."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-line)
         (emacsvox-icon 'mark-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  Advice Upgrade:

(defun emacsvox--advice-package-menu-mark-upgrades-after (&rest _)
  "Speak list of packages we marked for upgrading."
  (when (ems-interactive-p 'package-menu-mark-upgrades)
    (let ((upgrades (package-menu--find-upgrades)))
      (when upgrades
        (dtk-notify (format "%s" (mapcar #'car upgrades)))))))

(advice-add 'package-menu-mark-upgrades :after
            #'emacsvox--advice-package-menu-mark-upgrades-after)

(provide 'emacsvox-package)
;;;  end of file
