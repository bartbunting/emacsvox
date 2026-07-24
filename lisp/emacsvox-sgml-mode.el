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
;; Location https://github.com/robertmeta/emacsvox
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
(require 'emacsvox-preamble)
(require 'sgml-mode)

;;;  advice interactive commands 

(defmacro emacsvox-sgml--define-navigation-advice (targets)
  "Define native navigation feedback for SGML TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 "Speak the SGML navigation destination."
                 (when (ems-interactive-p ',target)
                   (emacsvox-icon 'large-movement)
                   (emacsvox-speak-line)))
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-sgml--define-navigation-advice
    (sgml-skip-tag-forward sgml-skip-tag-backward))

(defun emacsvox--advice-sgml-slash-after (&rest _)
  "speak"
  (when (ems-interactive-p 'sgml-slash)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add 'sgml-slash :after #'emacsvox--advice-sgml-slash-after)

(defun emacsvox--advice-sgml-delete-tag-after (&rest _)
  "speak"
  (when (ems-interactive-p 'sgml-delete-tag)
    (emacsvox-icon 'delete-object)))

(advice-add 'sgml-delete-tag :after
            #'emacsvox--advice-sgml-delete-tag-after)

(defun emacsvox--advice-sgml-name-char-around (orig-fun &rest args)
  "Speak the character you typed"
  (if (ems-interactive-p 'sgml-name-char)
      (let ((start (point)))
        (message "Type the char: ")
        (let ((result (apply orig-fun args)))
          (emacsvox-speak-region start (point))
          result))
    (apply orig-fun args)))

(advice-add 'sgml-name-char :around
            #'emacsvox--advice-sgml-name-char-around)

(defun emacsvox--advice-sgml-tags-invisible-after (&rest _)
  "speak"
  (when (ems-interactive-p 'sgml-tags-invisible)
    (emacsvox-icon 'button) (dtk-speak "Toggled display of tags")))

(advice-add 'sgml-tags-invisible :after
            #'emacsvox--advice-sgml-tags-invisible-after)

(provide  'emacsvox-sgml-mode)
