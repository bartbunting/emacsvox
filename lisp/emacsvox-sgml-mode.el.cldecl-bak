;;; emacsvox-sgml-mode.el --- Speech enable SGML -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Emacsvox extension for sgml mode
;; Keywords:emacsvox, audio interface to emacs sgml 
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
;; Copyright (c) 1995 by T. V. Raman  
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


;;;   Introduction
;;; Commentary:
;; emacsvox extensions to sgml mode
;;; Code:

;;;  requires
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  advice interactive commands 


(defun ems--sgml-skip-tag-forward-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))


(advice-add 'sgml-skip-tag-forward :after
	    #'ems--sgml-skip-tag-forward-after)





(defun ems--sgml-skip-tag-backward-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))


(advice-add 'sgml-skip-tag-backward :after
	    #'ems--sgml-skip-tag-backward-after)





(defun ems--sgml-slash-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-speak-this-char (preceding-char))))


(advice-add 'sgml-slash :after #'ems--sgml-slash-after)





(defun ems--sgml-delete-tag-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'delete-object)))


(advice-add 'sgml-delete-tag :after #'ems--sgml-delete-tag-after)





(defun ems--sgml-name-char-around (orig-fun &rest args)
  "Speak the character you typed"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
	(message "Type the char: ") (apply orig-fun args)
	(emacsvox-speak-region start (point))))
     (t (apply orig-fun args)))
    result))


(advice-add 'sgml-name-char :around #'ems--sgml-name-char-around)





(defun ems--sgml-tags-invisible-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (dtk-speak "Toggled display of tags")))


(advice-add 'sgml-tags-invisible :after
	    #'ems--sgml-tags-invisible-after)




(provide  'emacsvox-sgml-mode)

