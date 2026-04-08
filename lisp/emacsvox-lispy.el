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

(cl-loop ;;; Navigators:
 for f in
 '(
   lispy-goto-symbol lispy-splice lispy-view
   lispy-stringify lispy-ace-paren lispy-ace-symbol lispy-teleport
   lispy-ace-char lispy-ace-subword lispy-move-up lispy-move-down lispy-undo
   lispy-right-nostring lispy-left lispy-right lispy-up lispy-down lispy-back
   lispy-different lispy-backward lispy-forward lispy-flow
   lispy-to-defun lispy-beginning-of-defun)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "speak.
Speak sexp when at the beginning of a sexp.
Speak line if at end of sexp.
Indicate  no movement if we did not move."
     (cond
      ((ems-interactive-p)
       (let ((emacsvox-show-point t)
             (orig (point)))
         ad-do-it
         (cond
          ((eq orig (point))
           (dtk-notify "Did not move")
           (emacsvox-icon 'tick-tick))
          ((= ?\) (char-syntax (preceding-char)))
           (emacsvox-icon 'select-object)
           (emacsvox-speak-line))
          (t (emacsvox-icon 'select-object)
             (emacsvox-speak-sexp)))))
      (t ad-do-it))
     ad-return-value)))

(defun ems--lispy-move-beginning-of-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'left)))

(advice-add 'lispy-move-beginning-of-line :after
            #'ems--lispy-move-beginning-of-line-after)

(defun ems--lispy-move-beginning-of-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'right)))

(advice-add 'lispy-move-beginning-of-line :after
            #'ems--lispy-move-beginning-of-line-after)

;;; Advice Insertions:

(defun ems--lispy-clone-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-sexp) (emacsvox-icon 'yank-object)))

(advice-add 'lispy-clone :after #'ems--lispy-clone-after)

(defun ems--lispy-comment-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (cond
     ((use-region-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))))

(advice-add 'lispy-comment :after #'ems--lispy-comment-after)

(defun ems--lispy-backtick-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))))

(advice-add 'lispy-backtick :after #'ems--lispy-backtick-after)

(defun ems--lispy-tick-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (cond
     ((region-active-p)
      (emacsvox-speak-region (region-beginning) (region-end)))
     (t (emacsvox-speak-line)))))

(advice-add 'lispy-tick :after #'ems--lispy-tick-after)

(cl-loop
 for f in
 '(lispy-at lispy-colon lispy-hash lispy-hat)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-this-char (preceding-char))))))

(cl-loop
 for f in
 '(lispy-parens lispy-braces lispy-brackets)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'item)
       (save-excursion
         (forward-char 1)
         (emacsvox-speak-sexp))))))

;;;  Slurp and barf:

(cl-loop
 for f in
 '(
   lispy-barf lispy-slurp lispy-join lispy-split
   lispy-quotes lispy-alt-multiline
   lispy-out-forward-newline lispy-parens-down lispy-meta-return)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak line with show-point turned on."
     (when (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-icon 'select-object)
         (emacsvox-speak-line))))))

;;; Advice Marking:

(cl-loop
 for f in
 '(lispy-mark-list lispy-mark)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'mark-object)
       (emacsvox-speak-region (region-beginning) (region-end))))))

(defun ems--lispy-mark-symbol-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-speak-region (region-beginning) (region-end))))

(advice-add 'lispy-mark-symbol :after #'ems--lispy-mark-symbol-after)

;;; Advice WhiteSpace Manipulation:

(defun ems--lispy-fill-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'fill-object) (emacsvox-speak-line)))

(advice-add 'lispy-fill :after #'ems--lispy-fill-after)

(cl-loop
 for f in
 '(lispy-newline-and-indent lispy-newline-and-indent-plain)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line))))))

(defun ems--lispy-tab-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'fill-object)
    (when (buffer-modified-p) (emacsvox-icon 'modified-object))
    (emacsvox-speak-line)))

(advice-add 'lispy-tab :after #'ems--lispy-tab-after)

;;; Advice Kill/Yank:

(defun ems--lispy-new-copy-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message "region containing %s chars copied to kill ring "
             (length (current-kill 0)))))

(advice-add 'lispy-new-copy :after #'ems--lispy-new-copy-after)

(cl-loop
 for f in
 '(lispy-kill lispy-kill-word lispy-backward-kill-word
              lispy-kill-sentence lispy-kill-at-point)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'delete-object)
       (dtk-speak (current-kill 0 nil))))))

(defun ems--lispy-yank-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object)
    (emacsvox-speak-region (region-beginning) (region-end))))

(advice-add 'lispy-yank :after #'ems--lispy-yank-after)

(defun ems--lispy-delete-backward-around (orig-fun &rest args)
  "speak."
  (cond
   ((ems-interactive-p) (emacsvox-icon 'delete-object)
    (emacsvox-speak-this-char (preceding-char)) ad-do-it)
   (t ad-do-it)))

(advice-add 'lispy-delete-backward :around
            #'ems--lispy-delete-backward-around)

(defun ems--lispy-delete-around (orig-fun &rest args)
  "speak."
  (cond
   ((ems-interactive-p) (dtk-tone-deletion) (emacsvox-speak-char t)
    ad-do-it)
   (t ad-do-it)))

(advice-add 'lispy-delete :around #'ems--lispy-delete-around)

;;; Advice Help:

(defun ems--lispy-describe-inline-after (&rest _)
  "speak."
  (when
      (and (ems-interactive-p)
           (buffer-live-p (get-buffer "*lispy-help*"))
           (window-live-p (get-buffer-window "*lispy-help*")))
    (with-current-buffer "*lispy-help*"
      (emacsvox-icon 'help) (emacsvox-speak-buffer))))

(advice-add 'lispy-describe-inline :after
            #'ems--lispy-describe-inline-after)

(defun ems--lispy--show-before (&rest _)
  "speak." (emacsvox-icon 'help) (dtk-speak (ad-get-arg 0)))

(advice-add 'lispy--show :before #'ems--lispy--show-before)

;;; Advice Outliner:

(defun ems--lispy-narrow-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (message "Narrowed editing region to %s lines"
             (count-lines (region-beginning) (region-end)))))

(advice-add 'lispy-narrow :after #'ems--lispy-narrow-after)

(defun ems--lispy-widen-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "You can now edit the entire buffer ")))

(advice-add 'lispy-widen :after #'ems--lispy-widen-after)

(cl-loop
 for f in
 '(lispy-outline-next lispy-outline-prev lispy-shifttab)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line))))))

(provide 'emacsvox-lispy)
;;;  end of file

