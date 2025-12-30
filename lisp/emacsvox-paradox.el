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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
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
    (dtk-speak
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

(cl-loop
 for f in
 '(paradox-next-entry paradox-previous-entry)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-paradox-summarize-line)))))

;;;  Advice:


(defun ems--paradox-quit-and-close-after (&rest _)
  "provide auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))


(advice-add 'paradox-quit-and-close :after
	    #'ems--paradox-quit-and-close-after)




(cl-loop
 for f in
 '(
   paradox-sort-by-package paradox-sort-by-status
   paradox-sort-by-version paradox-sort-by-★) do
 (eval
  `(defadvice ,f  (after emacsvox pre act comp)
     "Speak after done."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'task-done)))))

;;;  Commit Navigation:
(cl-loop
 for f in 
 '(paradox-next-commit paradox-previous-commit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-tabulated-list-speak-cell)))))


(defun ems--paradox-menu-view-commit-list-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))


(advice-add 'paradox-menu-view-commit-list :after
	    #'ems--paradox-menu-view-commit-list-after)





(defun ems--fparadox-commit-list-visit-commit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))


(advice-add 'fparadox-commit-list-visit-commit :after
	    #'ems--fparadox-commit-list-visit-commit-after)




(provide 'emacsvox-paradox)
;;;  end of file

