;;; emacsvox-ruby.el --- Speech enable Ruby Mode  -*- lexical-binding: t; -*- 

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs Ruby
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Provide additional advice to Ruby mode 

;;; Code:

;;  required modules 

(require 'emacsvox-preamble)
(require 'ruby-mode)

;;;  Advice navigation:

(defmacro emacsvox-ruby--define-after-advice
    (targets docstring &rest body)
  "Define native after advice for TARGETS using DOCSTRING and BODY."
  (declare (indent 2) (debug (sexp stringp body)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,docstring
                 (when (ems-interactive-p ',target)
                   ,@body))
               (when (fboundp ',target)
                 (advice-add ',target :after #',function)))))
        targets)))

(emacsvox-ruby--define-after-advice
    (ruby-beginning-of-defun
     ruby-end-of-defun
     ruby-beginning-of-block
     ruby-end-of-block
     ruby-forward-sexp
     ruby-backward-sexp)
    "Speak the Ruby navigation destination."
  (emacsvox-speak-line)
  (emacsvox-icon 'paragraph))

;;;  Advice insertion and electric:

(defun emacsvox--advice-ruby-indent-line-after (&rest _)
  "Speak an interactively indented Ruby line."
  (when (ems-interactive-p 'ruby-indent-line)
    (emacsvox-speak-line)))

(advice-add 'ruby-indent-line :after
            #'emacsvox--advice-ruby-indent-line-after)

(defun emacsvox--advice-ruby-indent-exp-after (&rest _)
  "Speak an interactively indented Ruby expression."
  (when (ems-interactive-p 'ruby-indent-exp)
    (emacsvox-speak-line) (emacsvox-icon 'fill-object)))

(advice-add 'ruby-indent-exp :after
            #'emacsvox--advice-ruby-indent-exp-after)

;;;  Advice inferior ruby:

;; Inferior Ruby is supplied by the external inf-ruby package.  Do not create
;; placeholder functions when it is absent; install its advice if it is loaded.
(defconst emacsvox-ruby--inferior-targets
  '(ruby-run
    switch-to-ruby
    ruby-send-region-and-go
    ruby-send-block-and-go
    ruby-send-definition-and-go)
  "Commands supplied by the optional inf-ruby package.")

(defmacro emacsvox-ruby--define-inferior-feedback (targets)
  "Define feedback functions for the inf-ruby commands in TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(defun ,function (&rest _)
               "Announce the inferior Ruby destination."
               (when (ems-interactive-p ',target)
                 (emacsvox-icon 'select-object)
                 (emacsvox-speak-line)))))
        targets)))

(emacsvox-ruby--define-inferior-feedback
    (ruby-run
     switch-to-ruby
     ruby-send-region-and-go
     ruby-send-block-and-go
     ruby-send-definition-and-go))

(defun emacsvox-ruby--install-inferior-advice ()
  "Attach speech feedback to available inf-ruby commands."
  (dolist (target emacsvox-ruby--inferior-targets)
    (when (fboundp target)
      (advice-add
       target :after
       (intern (format "emacsvox--advice-%s-after" target))))))

(with-eval-after-load 'inf-ruby
  (emacsvox-ruby--install-inferior-advice))

(provide  'emacsvox-ruby)

;;; emacsvox-ruby.el ends here
