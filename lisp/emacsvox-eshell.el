;;; emacsvox-eshell.el --- Speech-enable EShell -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   Speech-enable EShell
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EShell is a shell implemented entirely in Emacs Lisp.
;; It is part of emacs 21 --and can also be used under
;; Emacs 20.
;; This module speech-enables EShell
;;; Code:

;;; Forward variable declarations:

(defvar eshell-last-input-end)
(defvar eshell-last-output-end)
(defvar eshell-last-output-start)
(defvar eat-terminal)
(defvar emacsvox-eat--eshell-output-owned-p)
(declare-function eat-term-live-p "eat" (object))

;;  required modules

(require 'emacsvox-preamble)
(require 'esh-arg)

;;;   setup various EShell hooks

;; Play an auditory icon as you display the prompt
(defun emacsvox-eshell-prompt-function ()
  "Play auditory icon for prompt."
  
  (cond
   ((= 0 eshell-last-command-status)
    (emacsvox-icon 'item))
   (t (emacsvox-icon 'warn-user))))

(add-hook 'eshell-after-prompt-hook 'emacsvox-eshell-prompt-function)

;; Speak command output

(defun emacsvox-eshell--eat-owns-output-p ()
  "Return non-nil while EAT owns output in this Eshell.
Ownership lasts through EAT terminal cleanup until the next Eshell prompt, so
the final generic output-filter pass cannot repeat already presented text."
  (or (bound-and-true-p emacsvox-eat--eshell-output-owned-p)
      (and (boundp 'eat-terminal)
           eat-terminal
           (fboundp 'eat-term-live-p)
           (eat-term-live-p eat-terminal))))

(defun emacsvox-eshell-speak-output ()
  "Speak eshell output."
  ;; EAT replaces Eshell's output-filter list while it owns a subprocess, but
  ;; retain an explicit guard in case a user adds this function buffer-locally.
  ;; The EAT screen observer owns that rendered output transaction.
  (unless (emacsvox-eshell--eat-owns-output-p)
    (emacsvox-speak-region eshell-last-input-end eshell-last-output-end)))

(add-hook 
 'eshell-output-filter-functions
 'emacsvox-eshell-speak-output
 'at-end)

;;;   Advice top-level EShell

(defun emacsvox--advice-eshell-after (&rest _)
  "Announce switching to shell mode.\nProvide an auditory icon if possible."
  (when (ems-interactive-p 'eshell)
    (emacsvox-icon 'open-object)
    (tts-apply-punctuation-mode-policy)
    (or tts-split-caps (tts-toggle-split-caps))
    (emacsvox-pronounce-refresh-pronunciations)
    (emacsvox-speak-line)))

(advice-add
 'eshell :after #'emacsvox--advice-eshell-after
 '((name . emacsvox)))

;;;  advice em-hist

(with-eval-after-load 'em-hist
  (cl-loop
   for target in
   '(
     eshell-next-input eshell-previous-input
     eshell-next-matching-input eshell-previous-matching-input
     eshell-next-matching-input-from-input
     eshell-previous-matching-input-from-input)
   for function =
   (intern (format "emacsvox--advice-%s-after" target))
   do
   (eval
    `(progn
       (defun ,function (&rest _)
         "Cue and speak after interactive Eshell input-history movement."
         (when (ems-interactive-p ',target)
           (emacsvox-icon 'select-object)
           (save-excursion
             (beginning-of-line)
             (eshell-skip-prompt)
             (emacsvox-speak-line 1))))
       (advice-add
        ',target :after #',function '((name . emacsvox)))))))

;;;   advice em-ls

(defgroup emacsvox-eshell nil
  "EShell on the Emacsvox Audio Desktop."
  :group 'emacsvox
  :group 'eshell
  :prefix "emacsvox-eshell-")

(defvar emacsvox-eshell-ls-use-personalities t
  "Indicates if ls in eshell uses different voice
personalities.")

;;;  voices

(voice-setup-add-map 
 '(
   (eshell-ls-archive voice-monotone)
   (eshell-ls-backup voice-monotone-extra)
   (eshell-ls-clutter voice-smoothen)
   (eshell-ls-directory voice-bolden-extra)
   (eshell-ls-executable voice-animate)
   (eshell-ls-missing voice-lighten)
   (eshell-ls-product voice-animate)
   (eshell-ls-readonly voice-monotone)
   (eshell-ls-special voice-brighten)
   (eshell-ls-symlink voice-smoothen)
   (eshell-ls-unreadable voice-animate-extra)
   (eshell-prompt voice-bolden-and-animate)))

;;;  Advice em-prompt

(with-eval-after-load 'em-prompt
  (cl-loop
   for target in
   '(
     eshell-next-prompt eshell-previous-prompt
     eshell-forward-matching-input eshell-backward-matching-input)
   for function =
   (intern (format "emacsvox--advice-%s-after" target))
   do
   (eval
    `(progn
       (defun ,function (&rest _)
         "Cue and speak after interactive Eshell prompt movement."
         (when (ems-interactive-p ',target)
           (let ((emacsvox-speak-messages nil))
             (emacsvox-icon 'select-object)
             (emacsvox-speak-line 1))))
       (advice-add
        ',target :after #',function '((name . emacsvox)))))))

;;;   advice esh-arg

(cl-loop
 for target in
 '(eshell-insert-buffer-name eshell-insert-process eshell-insert-envvar)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Eshell argument insertion."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  advice esh-mode

(defun emacsvox--advice-eshell-delchar-or-maybe-eof-before (&rest _)
  "Speak character you're deleting."
  (when (ems-interactive-p 'eshell-delchar-or-maybe-eof)
    (cond
     ((= (point) (point-max))
      (message "Sending EOF to comint process"))
     (t
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-char t)))))

(defun emacsvox--advice-eshell-delete-backward-char-before (&rest _)
  "Speak character you're deleting."
  (when (ems-interactive-p 'eshell-delete-backward-char)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-this-char (preceding-char))))

(with-eval-after-load 'em-rebind
  (advice-add
   'eshell-delchar-or-maybe-eof :before
   #'emacsvox--advice-eshell-delchar-or-maybe-eof-before
   '((name . emacsvox)))
  (advice-add
   'eshell-delete-backward-char :before
   #'emacsvox--advice-eshell-delete-backward-char-before
   '((name . emacsvox))))

(defun emacsvox--advice-eshell-show-output-after (&rest _)
  "Speak output."
  (when (ems-interactive-p 'eshell-show-output)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-region (point) (mark)))))

(advice-add
 'eshell-show-output :after
 #'emacsvox--advice-eshell-show-output-after
 '((name . emacsvox)))

(defun emacsvox--advice-eshell-mark-output-after (&rest _)
  "Speak output."
  (when (ems-interactive-p 'eshell-mark-output)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'mark-object)
      (emacsvox-speak-line))))

(advice-add
 'eshell-mark-output :after
 #'emacsvox--advice-eshell-mark-output-after
 '((name . emacsvox)))

(defun emacsvox--advice-eshell-delete-output-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p 'eshell-delete-output)
    (emacsvox-icon 'delete-object)
    (message "Flushed output")))

(advice-add
 'eshell-delete-output :after
 #'emacsvox--advice-eshell-delete-output-after
 '((name . emacsvox)))

(defun emacsvox--advice-eshell-kill-input-before (&rest _)
  "Speak."
  (when (ems-interactive-p 'eshell-kill-input)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-line)))

(advice-add
 'eshell-kill-input :before
 #'emacsvox--advice-eshell-kill-input-before
 '((name . emacsvox)))

(defun emacsvox--advice-eshell-toggle-after (&rest _)
  "Provide spoken context feedback."
  (when (ems-interactive-p 'eshell-toggle)
    (cond
     ((eq major-mode 'eshell-mode)
      (emacsvox-setup-programming-mode)
      (emacsvox-speak-line))
     (t (emacsvox-speak-mode-line)))
    (emacsvox-icon 'select-object)))

(defun emacsvox--advice-eshell-toggle-cd-after (&rest _)
  "Provide spoken context feedback."
  (when (ems-interactive-p 'eshell-toggle-cd)
    (cond
     ((eq major-mode 'eshell-mode) (emacsvox-speak-line))
     (t (emacsvox-speak-mode-line)))
    (emacsvox-icon 'select-object)))

(with-eval-after-load 'eshell-toggle
  (advice-add
   'eshell-toggle :after
   #'emacsvox--advice-eshell-toggle-after
   '((name . emacsvox)))
  (advice-add
   'eshell-toggle-cd :after
   #'emacsvox--advice-eshell-toggle-cd-after
   '((name . emacsvox))))

;;; Additional Commands To Enable: 

(cl-loop
 for target in
 '(eshell-forward-argument eshell-backward-argument)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak and cue after interactive Eshell argument movement."
       (when (ems-interactive-p ',target)
         (let ((emacsvox-show-point t))
           (emacsvox-speak-line)
           (emacsvox-icon 'large-movement))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-eshell-complete-lisp-symbol-around
    (original &rest arguments)
  "Say what ORIGINAL completed with ARGUMENTS."
  (ems-with-messages-silenced
   (let ((interactive-p
          (ems-interactive-p 'eshell-complete-lisp-symbol))
         (prior (save-excursion (skip-syntax-backward "^ >") (point))))
     (let ((result (apply original arguments)))
       (when interactive-p
         (if (> (point) prior)
             (tts-with-punctuations
              'all
              (tts-speak (buffer-substring prior (point))))
           (emacsvox-speak-completions-if-available)))
       result))))

(with-eval-after-load 'em-cmpl
  (advice-add
   'eshell-complete-lisp-symbol :around
   #'emacsvox--advice-eshell-complete-lisp-symbol-around
   '((name . emacsvox))))

(defun emacsvox--advice-eshell-copy-old-input-after (&rest _)
  "Speak what was inserted."
  (when (ems-interactive-p 'eshell-copy-old-input)
    (let ((start (save-excursion (beginning-of-line) (point))))
      (emacsvox-icon 'yank-object)
      (emacsvox-speak-region start (point)))))

(advice-add
 'eshell-copy-old-input :after
 #'emacsvox--advice-eshell-copy-old-input-after
 '((name . emacsvox)))

(defun emacsvox--advice-eshell-get-next-from-history-after (&rest _)
  "Speak what was inserted."
  (when (ems-interactive-p 'eshell-get-next-from-history)
    (let ((start (save-excursion (beginning-of-line) (point))))
      (emacsvox-icon 'yank-object)
      (emacsvox-speak-region start (point)))))

(with-eval-after-load 'em-hist
  (advice-add
   'eshell-get-next-from-history :after
   #'emacsvox--advice-eshell-get-next-from-history-after
   '((name . emacsvox))))

(provide 'emacsvox-eshell)
;;;  end of file
