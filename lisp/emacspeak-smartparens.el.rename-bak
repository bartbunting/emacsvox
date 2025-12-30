;;; emacspeak-smartparens.el --- SMARTPARENS  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable SMARTPARENS An Emacs Interface to smartparens
;; Keywords: Emacspeak,  Audio Desktop smartparens
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacspeak
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
;; MERCHANTABILITY or FITNSMARTPARENS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; SMARTPARENS == Automatic insertion, wrapping and paredit-like
;; navigation with user defined pairs this module speech-enables
;; smartparens.  Insertion of a matching delimiter is indicated by a
;; short auditory icon.  Structured navigation speaks the current
;; line with the position of point aurally highlighted.

;;; Code:

;;   Required modules:
(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (sp-pair-overlay-face voice-lighten)
   (sp-show-pair-enclosing voice-bolden)
   (sp-show-pair-match-face voice-animate)
   (sp-show-pair-mismatch-face voice-monotone-extra)
   (sp-wrap-overlay-closing-pair voice-smoothen)
   (sp-wrap-overlay-face voice-smoothen)
   (sp-wrap-overlay-opening-pair voice-bolden)
   (sp-wrap-tag-overlay-face voice-bolden)))

;;;  Advice low-level helpers:


(defun ems--sp--pair-overlay-create-after (&rest _)
  "speak." (emacspeak-icon 'item))


(advice-add 'sp--pair-overlay-create :after
	    #'ems--sp--pair-overlay-create-after)





(defun ems--sp-wrap--initialize-after (&rest _)
  "speak." (emacspeak-icon 'select-object))


(advice-add 'sp-wrap--initialize :after
	    #'ems--sp-wrap--initialize-after)




;;;  Navigators And Modifiers:


(defun ems--sp-backward-delete-char-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (emacspeak-icon 'delete-object)
      (emacspeak-speak-this-char (preceding-char))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add 'sp-backward-delete-char :around
	    #'ems--sp-backward-delete-char-around)





(defun ems--sp-forward-delete-char-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (emacspeak-icon 'delete-object)
      (emacspeak-speak-char t) (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add 'sp-forward-delete-char :around
	    #'ems--sp-forward-delete-char-around)





(defun ems--sp-backward-kill-word-before (&rest _)
  "Speak word before killing it."
  (when (ems-interactive-p)
    (when dtk-stop-immediately (dtk-stop 'all))
    (let ((start (point)) (dtk-stop-immediately nil))
      (save-excursion
	(forward-word -1) (emacspeak-icon 'delete-object)
	(emacspeak-speak-region (point) start)))))


(advice-add 'sp-backward-kill-word :before
	    #'ems--sp-backward-kill-word-before)




(cl-loop
 for f in
 '(sp-forward-sexp sp-backward-sexp)
 do
 (eval
  `(defadvice ,f (around emacspeak pre act comp)
     "Speak sexp after moving."
     (if (ems-interactive-p)
         (let ((start (point))
               (end (line-end-position))
               (emacspeak-show-point t))
           ad-do-it
           (emacspeak-icon 'large-movement)
           (cond
            ((>= end (point))
             (emacspeak-speak-region start (point)))
            (t (emacspeak-speak-line))))
       ad-do-it)
     ad-return-value)))

(cl-loop
 for f in
 '(
   sp-kill-whole-line sp-kill-region sp-backward-kill-sexp
   sp-splice-sexp-killing-around sp-splice-sexp-killing-backward
   sp-splice-sexp-killing-forward sp-kill-sexp sp-kill-hybrid-sexp
   sp-copy-sexp sp--kill-or-copy-region)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacspeak-speak-current-kill)
       (emacspeak-icon 'delete-object)))))

(cl-loop
 for f in
 '(
   sp-absorb-sexp sp-emit-sexp
   sp-add-to-next-sexp sp-add-to-previous-sexp
   sp-backward-barf-sexp sp-forward-barf-sexp sp-down-sexp sp-clone-sexp
   sp-backward-up-sexp sp-select-next-thing sp-backward-symbol
   sp-beginning-of-previous-sexp sp-beginning-of-next-sexp
   sp-beginning-of-sexp sp-backward-slurp-sexp
   sp-convolute-sexp sp-comment
   sp-end-of-next-sexp sp-end-of-previous-sexp
   sp-extract-before-sexp sp-extract-after-sexp
   sp-forward-parallel-sexp sp-backward-parallel-sexp
   sp-forward-slurp-sexp sp-backward-unwrap-sexp
   sp-forward-symbol sp-mark-sexp
   sp-highlight-current-sexp sp-forward-whitespace
   sp-html-previous-tag sp-html-next-tag
   sp-next-sexp sp-previous-sexp
   sp-raise-sexp
   sp-rewrap-sexp sp-swap-enclosing-sexp
   sp-ruby-forward-sexp sp-ruby-backward-sexp
   sp-select-next-thing sp-select-previous-thing
   sp-select-next-thing-exchange sp-end-of-sexp
   sp-split-sexp sp-join-sexp
   sp-transpose-sexp
   sp-unwrap-sexp sp-backward-down-sexp
   sp-up-sexp)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (when (ems-interactive-p)
       (let ((emacspeak-show-point t))
         (emacspeak-icon 'large-movement)
         (emacspeak-speak-line))))))

(provide 'emacspeak-smartparens)
;;;  end of file

