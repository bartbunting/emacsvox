;;; emacsvox-sage.el --- Speech-enable SAGE  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable SAGE An Emacs Interface to sage
;; Keywords: Emacsvox,  Audio Desktop sage
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
;; MERCHANTABILITY or FITNSAGE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Speech-enable @code{sage-shell-mode}.
;; This is a major mode for interacting with @code{sage},
;;  @url{http://www.sagemath.org/}
;; An Open-source  Mathematical Software System.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Forward Decls:
(declare-function sage-shell:delete-output "sage-shell-mode" nil)
(declare-function sage-shell:-send-input-one-line "sage-shell-mode" (line))
(declare-function  sage-shell-help:describe-symbol "emacsvox-sage" t)
(declare-function sage-shell-edit:process-alist "sage-shell-mode" nil)
(declare-function sage-shell:last-output-beg-end "sage-shell-mode" nil)

;;;  Helpers:

(defun emacsvox-sage-get-output ()
  "Return most recent Sage output"
  (interactive)
  (with-current-buffer
      (process-buffer (car (cl-first  (sage-shell-edit:process-alist))))
    (string-trim  (apply #'buffer-substring (sage-shell:last-output-beg-end)))))

(defun emacsvox-sage-speak-output ()
  "Speak last output from Sage."
  (interactive)
  (cl-assert
   (memq  major-mode '(sage-shell-mode sage-shell:sage-mode))
   t "Not in a Sage buffer")
  (cl-flet
      ((say-it ()
         (dtk-speak
          (apply #'buffer-substring (sage-shell:last-output-beg-end)))))
    (cond
     ((eq major-mode 'sage-shell-mode) (say-it))
     ((eq major-mode 'sage-shell:sage-mode)
      (cl-assert   (sage-shell-edit:process-alist) t "No running Sage.")
      ;; Take the first one for now:
      (with-current-buffer
          (process-buffer (car (cl-first  (sage-shell-edit:process-alist))))
        (say-it))))))

(defun emacsvox-sage-get-output-as-latex ()
  "Return most recent Sage output as LaTeX markup."
  (interactive)
  (cl-assert (eq major-mode 'sage-shell:sage-mode) t "Not in a sage buffer")
  (cl-assert   (sage-shell-edit:process-alist) t "No running Sage.")
  (let ((orig (emacsvox-sage-get-output))
        (result nil))
    (with-current-buffer
        (process-buffer (car (cl-first  (sage-shell-edit:process-alist))))
      (sage-shell:-send-input-one-line (format "latex(%s)" orig))
      (sit-for .1)
      (setq result (emacsvox-sage-get-output))
      (sage-shell:delete-output)
      result)))

;;;  Advice Help:

(defun ems--sage-shell-help:describe-symbol-after (&rest _)
  "speak."
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-icon 'help) (emacsvox-speak-buffer)))

(advice-add 'sage-shell-help:describe-symbol :after
            #'ems--sage-shell-help:describe-symbol-after)

(cl-loop
 for f in
 '(
   sage-shell-help:forward-history sage-shell-help:backward-history
   sage-shell:help)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'help)
       (emacsvox-speak-buffer)))))

(emacsvox-icon 'help)

;;;  Advice sage-edit:

(cl-loop
 for f in
 '(
   sage-shell-blocks:send-current
   sage-shell-edit:load-current-file
   sage-shell-edit:load-current-file-and-go
   sage-shell-edit:load-file
   sage-shell-edit:load-file-and-go
   sage-shell-edit:pop-to-process-buffer
   sage-shell-edit:send--buffer
   sage-shell-edit:send--buffer-and-go
   sage-shell-edit:send-buffer
   sage-shell-edit:send-buffer-and-go
   sage-shell-edit:send-defun
   sage-shell-edit:send-defun-and-go
   sage-shell-edit:send-line-and-go
   sage-shell-edit:send-region
   sage-shell-edit:send-region-and-go)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)))))

(cl-loop
 for f in
 '(sage-shell-edit:send-line sage-shell-edit:send-line*)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done))
     (sit-for 0.1)
     (emacsvox-sage-speak-output))))

;;;  sage-mode navigation:

(cl-loop
 for f in
 '(sage-shell-blocks:forward sage-shell-blocks:backward)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

;;;  sage comint interaction:

(defun ems--sage-shell:list-outputs-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (with-current-buffer (window-buffer (selected-window))
      (emacsvox-icon 'open-object) (emacsvox-speak-line))))

(advice-add 'sage-shell:list-outputs :after
            #'ems--sage-shell:list-outputs-after)

(defun ems--sage-shell:delchar-or-maybe-eof-around
    (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (cond
       ((= (point) (point-max))
        (message "Sending EOF to comint process"))
       (t (dtk-tone-deletion) (emacsvox-speak-char t)))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))

(advice-add 'sage-shell:delchar-or-maybe-eof :around
            #'ems--sage-shell:delchar-or-maybe-eof-around)

(defun ems--sage-shell:delete-output-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add 'sage-shell:delete-output :after
            #'ems--sage-shell:delete-output-after)

(cl-loop
 for f in
 '(sage-shell:run-new-sage sage-shell:run-sage)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-mode-line)))))

(defun ems--sage-shell:copy-previous-output-to-kill-ring-after
    (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object)
    (call-interactively #'emacsvox-speak-current-kill)))

(advice-add 'sage-shell:copy-previous-output-to-kill-ring :after
            #'ems--sage-shell:copy-previous-output-to-kill-ring-after)

(defun ems--sage-shell:send-input-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (sit-for 0.01) (accept-process-output)
    (emacsvox-sage-speak-output) (emacsvox-icon 'close-object)))

(advice-add 'sage-shell:send-input :after
            #'ems--sage-shell:send-input-after)

;;;  sage sagetext:

(cl-loop
 for f in
 '(sage-shell-sagetex:compile-current-file
   sage-shell-sagetex:compile-file
   sage-shell-sagetex:error-mode
   sage-shell-sagetex:load-current-file
   sage-shell-sagetex:load-file
   sage-shell-sagetex:run-latex-and-load-current-file
   sage-shell-sagetex:run-latex-and-load-file
   sage-shell-sagetex:send-environment)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-mode-line)))))

;;;  Additional Interactive Commands:

(defun emacsvox-sage-describe-symbol (s)
  "Describe Sage symbol at point."
  (interactive
   (list
    (read-from-minibuffer
     "Sage Symbol: "
     (format "%s" (symbol-at-point)))))
  (cl-assert (eq  major-mode  'sage-shell:sage-mode) t "Not in a Sage buffer")
  (cl-assert   (sage-shell-edit:process-alist) t "No running Sage.")
  ;; Take the first one for now:
  (with-current-buffer
      (process-buffer (car (cl-first  (sage-shell-edit:process-alist))))
    (sage-shell-help:describe-symbol s)))

;;;  Keybindings:
(cl-declaim (special sage-shell:sage-mode-map))
(when (and (bound-and-true-p sage-shell:sage-mode-map))
  (cl-loop
   for b in
   '(
     ("C-c h" emacsvox-sage-describe-symbol)
     ("C-C SPC" emacsvox-sage-speak-output)
     ("C-C m" emacsvox-maths-enter-guess))
   do
   (emacsvox-keymap-update sage-shell:sage-mode-map b)))

(provide 'emacsvox-sage)
;;;  end of file

