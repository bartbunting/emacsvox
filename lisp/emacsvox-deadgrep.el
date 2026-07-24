;;; emacsvox-deadgrep.el --- Speech-enable DEADGREP -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable DEADGREP An Emacs Interface to deadgrep
;; Keywords: Emacsvox,  Audio Desktop deadgrep
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
;; MERCHANTABILITY or FITNDEADGREP FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; DEADGREP ==  Front-end to ripgrep.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (deadgrep-filename-face voice-smoothen)
   (deadgrep-match-face voice-animate)
   (deadgrep-meta-face voice-annotate)
   (deadgrep-regexp-metachar-face voice-lighten)
   (deadgrep-search-term-face voice-bolden)))

;;;  Interactive Commands:

(defun emacsvox--advice-deadgrep-toggle-file-results-after (&rest _)
  "Report whether the current Deadgrep file results are visible."
  (when (ems-interactive-p 'deadgrep-toggle-file-results)
    (emacsvox-speak-line)
    (emacsvox-icon
     (if (get-text-property (1+ (line-end-position)) 'invisible) 'off
       'on))))

(defun emacsvox--advice-deadgrep-after (&rest _)
  "Speak after opening a Deadgrep results buffer."
  (when (ems-interactive-p 'deadgrep)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-deadgrep--visit-targets
  '(deadgrep-visit-result-other-window deadgrep-visit-result)
  "Deadgrep commands that visit a result.")

(cl-loop
 for target in emacsvox-deadgrep--visit-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak after visiting a Deadgrep result."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)
       (emacsvox-icon 'open-object)))))

(defconst emacsvox-deadgrep--movement-targets
  '(deadgrep-forward-match
    deadgrep-forward
    deadgrep-backward-match
    deadgrep-backward
    deadgrep-forward-filename
    deadgrep-backward-filename)
  "Deadgrep result navigation commands.")

(cl-loop
 for target in emacsvox-deadgrep--movement-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak after moving through Deadgrep results."
     (when (ems-interactive-p ',target)
       (let ((emacsvox-show-point t))
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line))))))

(defconst emacsvox-deadgrep--advice-targets
  (append '(deadgrep-toggle-file-results deadgrep)
          emacsvox-deadgrep--visit-targets
          emacsvox-deadgrep--movement-targets)
  "Current Deadgrep targets that receive native after advice.")

(defun emacsvox-deadgrep--install-advice ()
  "Install advice after the optional Deadgrep package loads."
  (dolist (target emacsvox-deadgrep--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'deadgrep
  (emacsvox-deadgrep--install-advice))

(provide 'emacsvox-deadgrep)
;;;  end of file
