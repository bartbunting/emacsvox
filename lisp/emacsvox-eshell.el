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
;; Location https://github.com/tvraman/emacsvox
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

;;  required modules

(cl-declaim  (optimize  (safety 0) (speed 3)))
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

(defun emacsvox-eshell-speak-output  ()
  "Speak eshell output."
  (cl-declare (special eshell-last-input-end eshell-last-output-end
                       eshell-last-output-start))
  (emacsvox-speak-region eshell-last-input-end eshell-last-output-end))

(add-hook 
 'eshell-output-filter-functions
 'emacsvox-eshell-speak-output
 'at-end)

;;;   Advice top-level EShell


(defun ems--eshell-after (&rest _)
  "Announce switching to shell mode.\nProvide an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (dtk-set-punctuations 'all)
    (or dtk-split-caps (dtk-toggle-split-caps))
    (emacsvox-pronounce-refresh-pronunciations)
    (emacsvox-speak-line)))


(advice-add 'eshell :after #'ems--eshell-after)




;;;  advice em-hist

(cl-loop
 for f in
 '(
   eshell-next-input eshell-previous-input
   eshell-next-matching-input eshell-previous-matching-input
   eshell-next-matching-input-from-input
   eshell-previous-matching-input-from-input)
 do
 (eval
  `(defadvice ,f (after  emacsvox pre act comp)
     "Speak selected command."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (save-excursion
         (beginning-of-line)
         (eshell-skip-prompt)
         (emacsvox-speak-line 1))))))

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

(cl-loop for f in
         '(
           eshell-next-prompt eshell-previous-prompt
           eshell-forward-matching-input  eshell-backward-matching-input)
         do
         (eval
          `(defadvice ,f (after  emacsvox pre act comp)
             "Speak selected command."
             (when (ems-interactive-p)
               (let ((emacsvox-speak-messages nil))
                 (emacsvox-icon 'select-object)
                 (emacsvox-speak-line 1))))))

;;;   advice esh-arg

(cl-loop for f in
         '(
           eshell-insert-buffer-name
           eshell-insert-process
           eshell-insert-envvar)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "Speak output."
             (when (ems-interactive-p)
               (emacsvox-icon 'select-object)
               (emacsvox-speak-line)))))


(defun ems--eshell-insert-process-after (&rest _)
  "Speak output."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))


(advice-add 'eshell-insert-process :after
	    #'ems--eshell-insert-process-after)




;;;  advice esh-mode


(defun ems--eshell-delchar-or-maybe-eof-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (cond
       ((= (point) (point-max))
	(message "Sending EOF to comint process"))
       (t (dtk-tone 500 100 'force) (emacsvox-speak-char t)))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add 'eshell-delchar-or-maybe-eof :around
	    #'ems--eshell-delchar-or-maybe-eof-around)





(defun ems--eshell-delete-backward-char-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone 500 100 'force)
      (emacsvox-speak-this-char (preceding-char))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add 'eshell-delete-backward-char :around
	    #'ems--eshell-delete-backward-char-around)





(defun ems--eshell-show-output-after (&rest _)
  "Speak output."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-region (point) (mark)))))


(advice-add 'eshell-show-output :after #'ems--eshell-show-output-after)




(defun ems--eshell-mark-output-after (&rest _)
  "Speak output."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'mark-object) (emacsvox-speak-line))))


(advice-add 'eshell-mark-output :after #'ems--eshell-mark-output-after)




(defun ems--eshell-kill-output-after (&rest _)
  "Produce auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (message "Flushed output")))


(advice-add 'eshell-kill-output :after #'ems--eshell-kill-output-after)





(defun ems--eshell-kill-input-before (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))


(advice-add 'eshell-kill-input :before #'ems--eshell-kill-input-before)





(defun ems--eshell-toggle-after (&rest _)
  "Provide spoken context feedback."
  (when (ems-interactive-p)
    (cond
     ((eq major-mode 'eshell-mode) (emacsvox-setup-programming-mode)
      (emacsvox-speak-line))
     (t (emacsvox-speak-mode-line)))
    (emacsvox-icon 'select-object)))


(advice-add 'eshell-toggle :after #'ems--eshell-toggle-after)




(defun ems--eshell-toggle-cd-after (&rest _)
  "Provide spoken context feedback."
  (when (ems-interactive-p)
    (cond ((eq major-mode 'eshell-mode) (emacsvox-speak-line))
	  (t (emacsvox-speak-mode-line)))
    (emacsvox-icon 'select-object)))


(advice-add 'eshell-toggle-cd :after #'ems--eshell-toggle-cd-after)




;;; Additional Commands To Enable: 

(cl-loop
 for f in
 '(eshell-forward-argument eshell-backward-argument eshell-bol)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "provide auditory feedback."
     (when
         (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line)
         (emacsvox-icon 'large-movement))))))

(cl-loop
 for f in
 '(eshell-pcomplete eshell-complete-lisp-symbol)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Say what you completed."
     (ems-with-messages-silenced
      (let ((prior (save-excursion (skip-syntax-backward "^ >") (point))))
        ad-do-it
        (if (> (point) prior)
            (tts-with-punctuations
             'all
             (dtk-speak
              (buffer-substring prior (point))))
          (emacsvox-speak-completions-if-available))
        ad-return-value)))))


(defun ems--eshell-copy-old-input-after (&rest _)
  "Speak what was inserted."
  (when (ems-interactive-p)
    (let ((start (save-excursion (eshell-bol) (point))))
      (emacsvox-icon 'yank-object)
      (emacsvox-speak-region start (point)))))


(advice-add 'eshell-copy-old-input :after
	    #'ems--eshell-copy-old-input-after)




(defun ems--eshell-get-next-from-history-after (&rest _)
  "Speak what was inserted."
  (when (ems-interactive-p)
    (let ((start (save-excursion (eshell-bol) (point))))
      (emacsvox-icon 'yank-object)
      (emacsvox-speak-region start (point)))))


(advice-add 'eshell-get-next-from-history :after
	    #'ems--eshell-get-next-from-history-after)




(provide 'emacsvox-eshell)
;;;  end of file

