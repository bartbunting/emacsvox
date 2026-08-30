;;; emacsvox-smartparens.el --- SMARTPARENS  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop smartparens
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

;; SMARTPARENS == Automatic insertion, wrapping and paredit-like
;; navigation with user defined pairs this module speech-enables
;; smartparens.  Insertion of a matching delimiter is indicated by a
;; short auditory icon.  Structured navigation speaks the current
;; line with the position of point aurally highlighted.

;;; Code:

;;   Required modules:
(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

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

(defvar emacsvox-smartparens--advice nil
  "Current Smartparens targets and their native advice functions.")
(setq emacsvox-smartparens--advice nil)

(defun emacsvox--advice-sp--pair-overlay-create-after (&rest _)
  "speak." (emacsvox-icon 'item))

(push '(sp--pair-overlay-create :after
        emacsvox--advice-sp--pair-overlay-create-after)
      emacsvox-smartparens--advice)

(defun emacsvox--advice-sp-wrap--initialize-after (&rest _)
  "speak." (emacsvox-icon 'select-object))

(push '(sp-wrap--initialize :after
        emacsvox--advice-sp-wrap--initialize-after)
      emacsvox-smartparens--advice)

;;;  Navigators And Modifiers:

(defun emacsvox--advice-sp-backward-delete-char-around (orig-fun &rest args)
  "Speak the character deleted by ORIG-FUN, which is called once."
  (when (ems-interactive-p 'sp-backward-delete-char)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-this-char (preceding-char)))
  (apply orig-fun args))

(push '(sp-backward-delete-char :around
        emacsvox--advice-sp-backward-delete-char-around)
      emacsvox-smartparens--advice)

(defun emacsvox--advice-sp-backward-kill-word-before (&rest _)
  "Speak word before killing it."
  (when (ems-interactive-p 'sp-backward-kill-word)
    (when tts-stop-immediately (tts-stop 'all))
    (let ((start (point)) (tts-stop-immediately nil))
      (save-excursion
        (forward-word -1) (emacsvox-icon 'delete-object)
        (emacsvox-speak-region (point) start)))))

(push '(sp-backward-kill-word :before
        emacsvox--advice-sp-backward-kill-word-before)
      emacsvox-smartparens--advice)

(defun emacsvox-smartparens--movement-around (target orig-fun &rest args)
  "Call ORIG-FUN once and speak movement by Smartparens TARGET."
  (let ((start (point))
        (end (line-end-position))
        (result (apply orig-fun args)))
    (when (ems-interactive-p target)
      (let ((emacsvox-show-point t))
        (emacsvox-icon 'large-movement)
        (if (>= end (point))
            (emacsvox-speak-region start (point))
          (emacsvox-speak-line))))
    result))

(dolist (target '(sp-forward-sexp sp-backward-sexp))
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-around" target))))
    (eval
     `(defun ,advice-function (orig-fun &rest args)
        ,(format "Speak movement performed by `%s'." target)
        (apply #'emacsvox-smartparens--movement-around
               ',target orig-fun args)))
    (push (list target :around advice-function)
          emacsvox-smartparens--advice)))

(defun emacsvox-smartparens--register-after-group (targets feedback)
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
            emacsvox-smartparens--advice))))

(defun emacsvox-smartparens--kill-feedback ()
  "Speak text killed by Smartparens."
  (emacsvox-speak-current-kill)
  (emacsvox-icon 'delete-object))

(emacsvox-smartparens--register-after-group
 '(
   sp-kill-whole-line sp-kill-region sp-backward-kill-sexp
   sp-splice-sexp-killing-around sp-splice-sexp-killing-backward
   sp-splice-sexp-killing-forward sp-kill-sexp sp-kill-hybrid-sexp
   sp-copy-sexp sp--kill-or-copy-region)
 #'emacsvox-smartparens--kill-feedback)

(defun emacsvox-smartparens--edit-feedback ()
  "Speak after a structural Smartparens edit."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(emacsvox-smartparens--register-after-group
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
 #'emacsvox-smartparens--edit-feedback)

(defun emacsvox-smartparens--install-advice ()
  "Install advice for Smartparens features loaded so far."
  (dolist (entry emacsvox-smartparens--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(smartparens smartparens-html smartparens-ruby))
  (eval `(with-eval-after-load ',feature
           (emacsvox-smartparens--install-advice))))

(provide 'emacsvox-smartparens)

;;; emacsvox-smartparens.el ends here
