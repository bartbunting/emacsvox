;;; emacsvox-clojure.el --- Speech-enable CLOJURE -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable CLOJURE-mode
;; Keywords: Emacsvox,  Audio Desktop clojure
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
;; MERCHANTABILITY or FITNCLOJURE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; CLOJURE-mode: Specialized mode for Clojure programming.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (clojure-interop-method-face  voice-lighten)
   (clojure-character-face voice-bolden-medium)
   (clojure-keyword-face voice-animate)))

;;;  Speech-enable Editing:

(defvar emacsvox-clojure--advice nil
  "Current Clojure Mode targets and their native advice functions.")

(defun emacsvox-clojure--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function)
            emacsvox-clojure--advice))))

(defun emacsvox-clojure--button-feedback ()
  "Speak an edited Clojure form."
  (emacsvox-icon 'button)
  (emacsvox-speak-line))
(emacsvox-clojure--register-after-group
 '(clojure-toggle-keyword-string clojure-cycle-not clojure-cycle-when)
 #'emacsvox-clojure--button-feedback)

(defun emacsvox-clojure--view-feedback ()
  "Speak a Clojure reference view."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-buffer))
(emacsvox-clojure--register-after-group
 '(clojure-view-cheatsheet
   clojure-view-guide
   clojure-view-reference-section
   clojure-view-style-guide)
 #'emacsvox-clojure--view-feedback)

(defun emacsvox-clojure--movement-feedback ()
  "Speak after logical Clojure movement."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))
(emacsvox-clojure--register-after-group
 '(clojure-forward-logical-sexp clojure-backward-logical-sexp)
 #'emacsvox-clojure--movement-feedback)

(defun emacsvox-clojure--align-feedback ()
  "Confirm alignment of a Clojure form."
  (emacsvox-icon 'fill-object))
(emacsvox-clojure--register-after-group
 '(clojure-align) #'emacsvox-clojure--align-feedback)

(defun emacsvox-clojure--insert-feedback ()
  "Speak an inserted Clojure namespace form."
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))
(emacsvox-clojure--register-after-group
 '(clojure-insert-ns-form-at-point clojure-insert-ns-form)
 #'emacsvox-clojure--insert-feedback)

(defun emacsvox-clojure--line-feedback ()
  "Speak the current Clojure form."
  (emacsvox-speak-line))
(emacsvox-clojure--register-after-group
 '(clojure-cycle-if
   clojure-cycle-privacy
   clojure-introduce-let
   clojure-move-to-let
   clojure-let-backward-slurp-sexp
   clojure-let-forward-slurp-sexp
   clojure-thread
   clojure-thread-first-all
   clojure-thread-last-all
   clojure-unwind
   clojure-unwind-all)
 #'emacsvox-clojure--line-feedback)

;;;  Speech-Enable Refactoring:

(defun emacsvox-clojure--collection-feedback ()
  "Speak the converted Clojure collection at point."
  (let ((begin (point)))
    (forward-sexp)
    (tts-speak (buffer-substring begin (point)))))
(emacsvox-clojure--register-after-group
 '(clojure-convert-collection-to-list
   clojure-convert-collection-to-map
   clojure-convert-collection-to-quoted-list
   clojure-convert-collection-to-set
   clojure-convert-collection-to-vector)
 #'emacsvox-clojure--collection-feedback)

(defun emacsvox-clojure--install-advice ()
  "Install advice after the optional Clojure Mode package loads."
  (dolist (entry emacsvox-clojure--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'clojure-mode
  (emacsvox-clojure--install-advice))

(provide 'emacsvox-clojure)
;;;  end of file
