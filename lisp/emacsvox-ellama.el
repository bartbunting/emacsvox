;;; emacsvox-ellama.el --- Speech-enable ELLAMA  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Keywords: Emacsvox,  Audio Desktop ellama
;;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;; ELLAMA ==  Emacs LLM Interaction.
;; ellama uses package llm, and this module speech-enables ellama.

;;; Code:

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:
;; Speech-enable output handlers:

(defun emacsvox--advice-ellama-chat-done-after (text &rest _)
  "Speak completed Ellama response TEXT."
  (emacsvox-icon 'item)
  (tts-speak text))

(defconst emacsvox-ellama--request-targets
  '(
   ellama-ask-about
   ellama-ask-line
   ellama-ask-selection
   ellama-change
   ellama-chat
   ellama-code-add
   ellama-code-complete
   ellama-code-edit
   ellama-code-improve
   ellama-code-review
   ellama-complete
   ellama-define-word
   ellama-improve-conciseness
   ellama-improve-grammar
   ellama-improve-wording
   ellama-make-format
   ellama-make-list
   ellama-make-table
   ellama-summarize
   ellama-summarize-webpage
   ellama-translate)
  "Current Ellama commands that submit an LLM request.")

(cl-loop
 for target in emacsvox-ellama--request-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Report the LLM request submitted by `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (tts-speak "Calling LLM")))))

(defconst emacsvox-ellama--removed-targets
  '(ellama-add-code ellama-ask ellama-ask-interactive
    ellama-change-code ellama-complete-code ellama-enhance-code
    ellama-enhance-grammar-spelling ellama-enhance-wording
    ellama-make-concise ellama-render)
  "Obsolete Ellama command names removed during migration.")

(defconst emacsvox-ellama--advice-targets
  (cons 'ellama-chat-done emacsvox-ellama--request-targets)
  "Current Ellama targets that receive native after advice.")

(defun emacsvox-ellama--install-advice ()
  "Install native advice after the optional Ellama package loads."
  (dolist (target emacsvox-ellama--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'ellama
  (emacsvox-ellama--install-advice))

(provide 'emacsvox-ellama)
;;;  end of file
