;;; emacsvox-paradox.el --- Speech-enable PARADOX  -*- lexical-binding: t; -*-
;; $Id: emacsvox-paradox.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable PARADOX An Emacs Interface to paradox
;; Keywords: Emacsvox,  Audio Desktop paradox
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
;; MERCHANTABILITY or FITNPARADOX FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; PARADOX == paradox.el Improved package management interface
;; Manage Emacs packages.
;; This module speech-enables paradox.el with a few convenience commands.

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'paradox "paradox" 'no-error)
(require 'calendar)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (paradox-name-face voice-bolden)
   (paradox-download-face voice-smoothen)
   (paradox-description-face voice-lighten)
   (paradox-description-face-multiline voice-monotone-extra)
   (paradox-comment-face voice-monotone)
   (paradox-star-face voice-animate)
   (paradox-starred-face voice-bolden-and-animate)
   (paradox-archive-face voice-smoothen)
   (paradox-commit-tag-face voice-brighten)
   (paradox-highlight-face voice-animate)
   (paradox-homepage-button-face voice-bolden-medium)))

;;;  Additional Commands

(defun emacsvox-paradox-summarize-line ()
  "Succinct Summary."
  (interactive)
  (let* ((entry   (tabulated-list-get-entry))
         (name (aref entry 0))
         (desc (aref entry 5))
         (state (aref entry 2)))
    (cond
     ((string= state "installed") (emacsvox-icon 'mark-object))
     ((string= state "built-in") (emacsvox-icon 'select-object))
     ((string= state "dependency") (emacsvox-icon 'close-object))
     ((string= state "obsolete") (emacsvox-icon 'deselect-object))
     ((string= state "incompat") (emacsvox-icon
                                  'alert-user))
     (t (emacsvox-icon 'doc)))
    (tts-speak
     (concat
      (propertize name 'personality voice-animate) "  "desc))))

(defun emacsvox-paradox-mode-hook ()
  "Emacsvox setup hook for paradox-mode."
  
  (define-key paradox-menu-mode-map " " 'emacsvox-paradox-summarize-line)
  (emacsvox-pronounce-add-local-entry
   emacsvox-pronounce-date-yyyymmdd-pattern
   (cons 're-search-forward 'emacsvox-pronounce-yyyymmdd-date))
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(add-hook 'paradox-menu-mode-hook 'emacsvox-paradox-mode-hook)

;;;  Managing Packages:

(defvar emacsvox-paradox--advice nil
  "Current Paradox targets and their native advice functions.")
(setq emacsvox-paradox--advice nil)

(defun emacsvox-paradox--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-paradox--advice))))

(emacsvox-paradox--register-after-group
 '(paradox-next-entry paradox-previous-entry)
 #'emacsvox-paradox-summarize-line)

;;;  Advice:

(defun emacsvox--advice-paradox-quit-and-close-after (&rest _)
  "provide auditory feedback."
  (when (ems-interactive-p 'paradox-quit-and-close)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(push '(paradox-quit-and-close :after
        emacsvox--advice-paradox-quit-and-close-after)
      emacsvox-paradox--advice)

(defun emacsvox-paradox--sort-feedback ()
  "Speak after sorting Paradox entries."
  (emacsvox-speak-line)
  (emacsvox-icon 'task-done))

(emacsvox-paradox--register-after-group
 '(paradox-sort-by-package paradox-sort-by-status
   paradox-sort-by-version paradox-sort-by-★)
 #'emacsvox-paradox--sort-feedback)

;;;  Commit Navigation:
(defun emacsvox-paradox--commit-feedback ()
  "Speak the selected Paradox commit."
  (emacsvox-icon 'select-object)
  (emacsvox-tabulated-list-speak-cell))

(emacsvox-paradox--register-after-group
 '(paradox-next-commit paradox-previous-commit)
 #'emacsvox-paradox--commit-feedback)

(defun emacsvox--advice-paradox-menu-view-commit-list-after (&rest _)
  "speak."
  (when (ems-interactive-p 'paradox-menu-view-commit-list)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(push '(paradox-menu-view-commit-list :after
        emacsvox--advice-paradox-menu-view-commit-list-after)
      emacsvox-paradox--advice)

(defun emacsvox--advice-paradox-commit-list-visit-commit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'paradox-commit-list-visit-commit)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(push '(paradox-commit-list-visit-commit :after
        emacsvox--advice-paradox-commit-list-visit-commit-after)
      emacsvox-paradox--advice)

(defun emacsvox-paradox--install-advice ()
  "Install native advice after Paradox loads."
  (dolist (entry emacsvox-paradox--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'paradox
  (emacsvox-paradox--install-advice))

(provide 'emacsvox-paradox)
;;;  end of file
