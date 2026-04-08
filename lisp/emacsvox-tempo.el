;;; emacsvox-tempo.el --- Speech enable tempo  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description:  Emacsvox extensions for tempo.el (used by html-helper-mode)
;; Keywords: Emacsvox, Spoken Feedback, Template filling, html editing
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; tempo.el provides the
;; infrastructure  for building up templates.
;; This is used by html-helper-mode to allow for easy writing of HTML
;; This module extends Emacsvox to provide fluent spoken feedback
;;; Code:

;;;  requires
(require 'emacsvox-preamble)

;;;   First setup tempo variables:

;; Prompting in the minibuffer is useful:

(cl-declaim  (special tempo-interactive))
(setq tempo-interactive t)
(add-hook
 'tempo-insert-string-hook
 #'(lambda (string)
     (dtk-speak string)
     string))

;;;   Advice: 

(defun ems--tempo-forward-mark-after (&rest _)
  "Speak the line." (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'tempo-forward-mark :after #'ems--tempo-forward-mark-after)

(defun ems--tempo-backward-mark-after (&rest _)
  "Speak the line." (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'tempo-backward-mark :after
            #'ems--tempo-backward-mark-after)

(defun ems--html-helper-smart-insert-item-after (&rest _)
  "Speak the line." (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'html-helper-smart-insert-item :after
            #'ems--html-helper-smart-insert-item-after)

(emacsvox-pronounce-add-super 'sgml-mode 'html-helper-mode)

(provide 'emacsvox-tempo)

;;;  end of file 

;;;  end of file 

