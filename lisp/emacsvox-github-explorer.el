;;; emacsvox-github-explorer.el --- GitHub Explorer  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description: Speech-enable the github-explorer package
;; Keywords: Emacsvox, Audio Desktop, github-explorer
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
;; MERCHANTABILITY or FITNGH-EXPLORER FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; GH-EXPLORER ==  GitHub Explorer 
;; This module speech-enables Github Explorer.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '((github-explorer-directory-face voice-bolden-medium)))

;;;  Interactive Commands:

(cl-loop
 for target in
 '(github-explorer github-explorer-at-point)
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-speak-mode-line)
       (emacsvox-icon 'open-object)))))

(defun emacsvox-github-explorer--navigate (direction)
  "Move forward/back based on `direction' and speak current entry."
  (emacsvox-icon 'select-object)
  (forward-line direction)
  (save-excursion
    (goto-char (line-beginning-position))
    (let ((path (cdr (assoc 'path (get-text-property (point) 'invisible))))
          (type (cdr (assoc 'type (get-text-property (point) 'invisible)))))
      (cond
       ((null path) (emacsvox-speak-line))
       (t
        (tts-speak
         (propertize path 'personality
                     (when (string= type "tree") voice-bolden-medium))))))))

(defun emacsvox-github-explorer-next ()
  "Move forward and speak current entry."
  (interactive)
  (emacsvox-github-explorer--navigate 1))

(defun emacsvox-github-explorer-previous ()
  "Moveback and speak current entry."
  (interactive)
  
  (emacsvox-github-explorer--navigate -1))

(defconst emacsvox-github-explorer--advice-targets
  '(github-explorer github-explorer-at-point)
  "Current GitHub Explorer targets that receive native advice.")

(defun emacsvox-github-explorer--setup ()
  "Install GitHub Explorer advice and Emacsvox navigation bindings."
  (dolist (target emacsvox-github-explorer--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (when (boundp 'github-explorer-mode-map)
    (define-key
     github-explorer-mode-map "p" #'emacsvox-github-explorer-previous)
    (define-key
     github-explorer-mode-map "n" #'emacsvox-github-explorer-next)))

(with-eval-after-load 'github-explorer
  (emacsvox-github-explorer--setup))

(provide 'emacsvox-github-explorer)
;;;  end of file
