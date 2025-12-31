;;; emacsvox-projectile.el --- PROJECTILE  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable PROJECTILE An Emacs Project Manager
;; Keywords: Emacsvox,  Audio Desktop projectile
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
;; MERCHANTABILITY or FITNPROJECTILE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; PROJECTILE ==  @samp{M-x package-install projectile}.
;; Project management in Emacs.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Emacsvox Helpers:

(defun emacsvox-projectile-file-action ()
  "speak for file open actions."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

;;;  Speech-enable Interactive Commands:

(defun ems--projectile-vc-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'projectile-vc :after #'ems--projectile-vc-after)

(cl-loop
 for f in
 '(projectile-ag
   projectile-cleanup-known-projects
   projectile-clear-known-projects
   projectile-compile-project
   projectile-regenerate-tags
   projectile-run-async-shell-command-in-root
   projectile-run-command-in-root
   projectile-run-project
   projectile-run-shell-command-in-root
   projectile-test-project
   projectile-ibuffer
   )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)))))
(add-hook 'projectile-find-file-hook 'emacsvox-projectile-file-action)

(defun ems--projectile-edit-dir-locals-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'projectile-edit-dir-locals :after
            #'ems--projectile-edit-dir-locals-after)

(cl-loop
 for f in
 '(projectile-run-shell projectile-run-eshell projectile-run-term)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-mode-line)
       (emacsvox-icon 'open-object)))))

(provide 'emacsvox-projectile)
;;;  end of file

