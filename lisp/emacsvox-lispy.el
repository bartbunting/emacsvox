;;; emacsvox-lispy.el --- Speech-enable LISPY  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable LISPY An Emacs Interface to lispy
;; Keywords: Emacsvox,  Audio Desktop lispy
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
;; MERCHANTABILITY or FITNLISPY FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; LISPY == smart Navigation Of Lisp code This module speech-enables
;; lispy.
;; @subsection Overview
;; Lispy editing keeps delimiters
;; balanced and Lispy navigators reliably place point on either the
;; opening or closing delimiter of the current s-expression. Emacsvox
;; leverages this fact in the type of spoken feedback that is
;; produced. All navigation commands produce the following:
;; @itemize
;; @item Speak the current s-expression when at the front of a sexp.
;; @item Speak the current line with option
;; @code{emacsvox-show-point} turned on when at the end of an
;; s-expression. 
;;  @item Produce auditory icon @code{left} or
;; @code{right} to indicate point being at the beginning or end of
;; current line. 
;; @item Indicate with an auditory icon if point did
;; not move.
;;   @end itemize

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'lispy "lispy" 'no-error)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (lispy-command-name-face voice-bolden)
   (lispy-cursor-face voice-animate)
   (lispy-face-hint voice-smoothen)
   (lispy-face-key-nosel voice-monotone-extra)
   (lispy-face-key-sel voice-brighten)
   (lispy-face-opt-nosel voice-monotone-extra)
   (lispy-face-opt-sel voice-lighten)
   (lispy-face-req-nosel voice-monotone-extra)
   (lispy-face-req-sel voice-brighten-extra)
   (lispy-face-rst-nosel voice-monotone-extra)
   (lispy-face-rst-sel voice-lighten-extra)
   (lispy-test-face voice-annotate)))

;;;  Setup:

(defun emacsvox-lispy-setup ()
  "Setup emacsvox for use with lispy"
  
  (when (bound-and-true-p lispy-mode-map)
    (define-key lispy-mode-map (kbd "C-e") 'emacsvox-keymap)))

(emacsvox-lispy-setup)

;;;  Advice Navigation:

(defvar emacsvox-lispy--advice nil
  "Current Lispy targets and their native advice functions.")
(setq emacsvox-lispy--advice nil)

(defun emacsvox-lispy--navigation-around (target orig-fun &rest args)
  "Call ORIG-FUN once and report movement for Lispy TARGET."
  (let ((origin (point))
        (result (apply orig-fun args)))
    (when (ems-interactive-p target)
      (let ((emacsvox-show-point t))
        (cond
         ((eq origin (point))
          (tts-notify "Did not move")
          (emacsvox-icon 'tick-tick))
         ((= ?\) (char-syntax (preceding-char)))
          (emacsvox-icon 'select-object)
          (emacsvox-speak-line))
         (t
          (emacsvox-icon 'select-object)
          (emacsvox-speak-sexp)))))
    result))

(dolist
    (target
     '(lispy-goto-symbol lispy-splice lispy-view lispy-stringify
       lispy-ace-paren lispy-ace-symbol lispy-teleport lispy-ace-char
       lispy-ace-subword lispy-move-up lispy-move-down lispy-undo
       lispy-right-nostring lispy-left lispy-right lispy-up lispy-down
       lispy-back lispy-different lispy-backward lispy-forward lispy-flow
       lispy-to-defun lispy-beginning-of-defun))
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-around" target))))
    (eval
     `(defun ,advice-function (orig-fun &rest args)
        ,(format "Provide movement feedback around `%s'." target)
        (apply #'emacsvox-lispy--navigation-around
               ',target orig-fun args)))
    (push (list target :around advice-function) emacsvox-lispy--advice)))

(defun emacsvox--advice-lispy-move-beginning-of-line-after (&rest _)
  "Speak after moving to the beginning of a Lispy line."
  (when (ems-interactive-p 'lispy-move-beginning-of-line)
    (emacsvox-speak-line)
    (emacsvox-icon 'left)))

(push '(lispy-move-beginning-of-line :after
        emacsvox--advice-lispy-move-beginning-of-line-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-move-end-of-line-after (&rest _)
  "Speak after moving to the end of a Lispy line."
  (when (ems-interactive-p 'lispy-move-end-of-line)
    (emacsvox-speak-line)
    (emacsvox-icon 'right)))

(push '(lispy-move-end-of-line :after
        emacsvox--advice-lispy-move-end-of-line-after)
      emacsvox-lispy--advice)

;;; Advice Insertions:

(defun emacsvox--advice-lispy-clone-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-clone)
    (emacsvox-speak-sexp) (emacsvox-icon 'yank-object)))

(push '(lispy-clone :after emacsvox--advice-lispy-clone-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-comment-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-comment)
    (emacsvox-icon 'select-object)
    (cond
     ((use-region-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))))

(push '(lispy-comment :after emacsvox--advice-lispy-comment-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-backtick-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-backtick)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))))

(push '(lispy-backtick :after emacsvox--advice-lispy-backtick-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-tick-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-tick)
    (cond
     ((region-active-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))))

(push '(lispy-tick :after emacsvox--advice-lispy-tick-after)
      emacsvox-lispy--advice)

(defun emacsvox-lispy--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-lispy--advice))))

(defun emacsvox-lispy--insert-char-feedback ()
  "Speak the character inserted by Lispy."
  (emacsvox-speak-this-char (preceding-char)))

(emacsvox-lispy--register-after-group
 '(lispy-at lispy-colon lispy-hash lispy-hat)
 #'emacsvox-lispy--insert-char-feedback)

(defun emacsvox-lispy--insert-pair-feedback ()
  "Speak the paired expression inserted by Lispy."
  (emacsvox-icon 'item)
  (save-excursion
    (forward-char 1)
    (emacsvox-speak-sexp)))

(emacsvox-lispy--register-after-group
 '(lispy-parens lispy-braces lispy-brackets)
 #'emacsvox-lispy--insert-pair-feedback)

;;;  Slurp and barf:

(defun emacsvox-lispy--structure-feedback ()
  "Speak the line after a Lispy structure edit."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'select-object)
    (emacsvox-speak-line)))

(emacsvox-lispy--register-after-group
 '(lispy-barf lispy-slurp lispy-join lispy-split lispy-quotes
   lispy-alt-multiline lispy-out-forward-newline lispy-parens-down
   lispy-meta-return)
 #'emacsvox-lispy--structure-feedback)

;;; Advice Marking:

(defun emacsvox-lispy--mark-feedback ()
  "Speak the region marked by Lispy."
  (emacsvox-icon 'mark-object)
  (emacsvox-speak-region (region-beginning) (region-end)))

(emacsvox-lispy--register-after-group
 '(lispy-mark-list lispy-mark lispy-mark-symbol)
 #'emacsvox-lispy--mark-feedback)

;;; Advice WhiteSpace Manipulation:

(defun emacsvox--advice-lispy-fill-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-fill)
    (emacsvox-icon 'fill-object) (emacsvox-speak-line)))

(push '(lispy-fill :after emacsvox--advice-lispy-fill-after)
      emacsvox-lispy--advice)

(defun emacsvox-lispy--newline-feedback ()
  "Speak the new Lispy line."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)))

(emacsvox-lispy--register-after-group
 '(lispy-newline-and-indent lispy-newline-and-indent-plain)
 #'emacsvox-lispy--newline-feedback)

(defun emacsvox--advice-lispy-tab-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-tab)
    (emacsvox-icon 'fill-object)
    (when (buffer-modified-p) (emacsvox-icon 'modified-object))
    (emacsvox-speak-line)))

(push '(lispy-tab :after emacsvox--advice-lispy-tab-after)
      emacsvox-lispy--advice)

;;; Advice Kill/Yank:

(defun emacsvox--advice-lispy-new-copy-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-new-copy)
    (emacsvox-icon 'mark-object)
    (message "region containing %s chars copied to kill ring "
             (length (current-kill 0)))))

(push '(lispy-new-copy :after emacsvox--advice-lispy-new-copy-after)
      emacsvox-lispy--advice)

(defun emacsvox-lispy--kill-feedback ()
  "Speak text killed by Lispy."
  (emacsvox-icon 'delete-object)
  (tts-speak (current-kill 0 nil)))

(emacsvox-lispy--register-after-group
 '(lispy-kill lispy-kill-word lispy-backward-kill-word
   lispy-kill-sentence lispy-kill-at-point)
 #'emacsvox-lispy--kill-feedback)

(defun emacsvox--advice-lispy-yank-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-yank)
    (emacsvox-icon 'yank-object)
    (emacsvox-speak-region (region-beginning) (region-end))))

(push '(lispy-yank :after emacsvox--advice-lispy-yank-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-delete-backward-around (orig-fun &rest args)
  "Speak the character deleted by ORIG-FUN, which is called once."
  (when (ems-interactive-p 'lispy-delete-backward)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-this-char (preceding-char)))
  (apply orig-fun args))

(push '(lispy-delete-backward :around
        emacsvox--advice-lispy-delete-backward-around)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-delete-around (orig-fun &rest args)
  "Speak the character deleted by ORIG-FUN, which is called once."
  (when (ems-interactive-p 'lispy-delete)
    (tts-tone-deletion)
    (emacsvox-speak-char t))
  (apply orig-fun args))

(push '(lispy-delete :around emacsvox--advice-lispy-delete-around)
      emacsvox-lispy--advice)

;;; Advice Help:

(defun emacsvox--advice-lispy-describe-inline-after (&rest _)
  "speak."
  (when
      (and (ems-interactive-p 'lispy-describe-inline)
           (buffer-live-p (get-buffer "*lispy-help*"))
           (window-live-p (get-buffer-window "*lispy-help*")))
    (with-current-buffer "*lispy-help*"
      (emacsvox-icon 'help) (emacsvox-speak-buffer))))

(push '(lispy-describe-inline :after
        emacsvox--advice-lispy-describe-inline-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy--show-before (string)
  "Speak STRING before Lispy displays it."
  (emacsvox-icon 'help)
  (tts-speak string))

(push '(lispy--show :before emacsvox--advice-lispy--show-before)
      emacsvox-lispy--advice)

;;; Advice Outliner:

(defun emacsvox--advice-lispy-narrow-after (&rest _)
  "speak."
  (when (ems-interactive-p 'lispy-narrow)
    (emacsvox-icon 'mark-object)
    (message "Narrowed editing region to %s lines"
             (count-lines (region-beginning) (region-end)))))

(push '(lispy-narrow :after emacsvox--advice-lispy-narrow-after)
      emacsvox-lispy--advice)

(defun emacsvox--advice-lispy-widen-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p 'lispy-widen)
    (emacsvox-icon 'open-object)
    (message "You can now edit the entire buffer ")))

(push '(lispy-widen :after emacsvox--advice-lispy-widen-after)
      emacsvox-lispy--advice)

(defun emacsvox-lispy--outline-feedback ()
  "Speak after moving through a Lispy outline."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)))

(emacsvox-lispy--register-after-group
 '(lispy-outline-next lispy-outline-prev lispy-shifttab)
 #'emacsvox-lispy--outline-feedback)

(defun emacsvox-lispy--install-advice ()
  "Install native advice after Lispy loads."
  (dolist (entry emacsvox-lispy--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'lispy
  (emacsvox-lispy--install-advice))

(provide 'emacsvox-lispy)
;;;  end of file
