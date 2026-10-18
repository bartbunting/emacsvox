;;; emacsvox-sage.el --- Speech-enable SAGE  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop sage
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
         (tts-speak
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

(defvar emacsvox-sage--advice nil
  "Current Sage shell targets and their native advice functions.")
(setq emacsvox-sage--advice nil)

(defun emacsvox--advice-sage-shell-help:describe-symbol-after (&rest _)
  "speak."
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-icon 'help) (emacsvox-speak-buffer)))

(push '(sage-shell-help:describe-symbol :after
        emacsvox--advice-sage-shell-help:describe-symbol-after)
      emacsvox-sage--advice)

(defun emacsvox-sage--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-sage--advice))))

(defun emacsvox-sage--help-feedback ()
  "Speak a Sage help buffer."
  (emacsvox-icon 'help)
  (emacsvox-speak-buffer))

(emacsvox-sage--register-after-group
 '(sage-shell-help:forward-history sage-shell-help:backward-history
   sage-shell:help)
 #'emacsvox-sage--help-feedback)

;;;  Advice sage-edit:

(defun emacsvox-sage--task-feedback ()
  "Announce completion of a Sage task."
  (emacsvox-icon 'task-done))

(emacsvox-sage--register-after-group
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
 #'emacsvox-sage--task-feedback)

(dolist (target '(sage-shell-edit:send-line sage-shell-edit:send-line*))
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Speak output after `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-icon 'task-done))
        (sit-for 0.1)
        (emacsvox-sage-speak-output)))
    (push (list target :after advice-function) emacsvox-sage--advice)))

;;;  sage-mode navigation:

(defun emacsvox-sage--movement-feedback ()
  "Speak after moving through Sage blocks."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-sage--register-after-group
 '(sage-shell-blocks:forward sage-shell-blocks:backward)
 #'emacsvox-sage--movement-feedback)

;;;  sage comint interaction:

(defun emacsvox--advice-sage-shell:list-outputs-after (&rest _)
  "speak."
  (when (ems-interactive-p 'sage-shell:list-outputs)
    (with-current-buffer (window-buffer (selected-window))
      (emacsvox-icon 'open-object) (emacsvox-speak-line))))

(push '(sage-shell:list-outputs :after
        emacsvox--advice-sage-shell:list-outputs-after)
      emacsvox-sage--advice)

(defun emacsvox--advice-sage-shell:delchar-or-maybe-eof-around
    (orig-fun &rest args)
  "Speak the character deleted by ORIG-FUN, which is called once."
  (when (ems-interactive-p 'sage-shell:delchar-or-maybe-eof)
    (if (= (point) (point-max))
        (message "Sending EOF to comint process")
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-char t)))
  (apply orig-fun args))

(push '(sage-shell:delchar-or-maybe-eof :around
        emacsvox--advice-sage-shell:delchar-or-maybe-eof-around)
      emacsvox-sage--advice)

(defun emacsvox--advice-sage-shell:delete-output-after (&rest _)
  "speak."
  (when (ems-interactive-p 'sage-shell:delete-output)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(push '(sage-shell:delete-output :after
        emacsvox--advice-sage-shell:delete-output-after)
      emacsvox-sage--advice)

(defun emacsvox-sage--run-feedback ()
  "Speak after starting a Sage process."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-mode-line))

(emacsvox-sage--register-after-group
 '(sage-shell:run-new-sage sage-shell:run-sage)
 #'emacsvox-sage--run-feedback)

(defun emacsvox--advice-sage-shell:copy-previous-output-to-kill-ring-after
    (&rest _)
  "speak."
  (when (ems-interactive-p 'sage-shell:copy-previous-output-to-kill-ring)
    (emacsvox-icon 'yank-object)
    (call-interactively #'emacsvox-speak-current-kill)))

(push '(sage-shell:copy-previous-output-to-kill-ring :after
        emacsvox--advice-sage-shell:copy-previous-output-to-kill-ring-after)
      emacsvox-sage--advice)

(defun emacsvox--advice-sage-shell:send-input-after (&rest _)
  "speak."
  (when (ems-interactive-p 'sage-shell:send-input)
    (sit-for 0.01) (accept-process-output)
    (emacsvox-sage-speak-output) (emacsvox-icon 'close-object)))

(push '(sage-shell:send-input :after
        emacsvox--advice-sage-shell:send-input-after)
      emacsvox-sage--advice)

;;;  sage sagetext:

(defun emacsvox-sage--sagetex-feedback ()
  "Speak after completing a SageTeX task."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-mode-line))

(emacsvox-sage--register-after-group
 '(sage-shell-sagetex:compile-current-file
   sage-shell-sagetex:compile-file
   sage-shell-sagetex:error-mode
   sage-shell-sagetex:load-current-file
   sage-shell-sagetex:load-file
   sage-shell-sagetex:run-latex-and-load-current-file
   sage-shell-sagetex:run-latex-and-load-file
   sage-shell-sagetex:send-environment)
 #'emacsvox-sage--sagetex-feedback)

(defun emacsvox-sage--install-advice ()
  "Install advice for Sage shell features loaded so far."
  (dolist (entry emacsvox-sage--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(sage-shell-mode sage-shell-blocks))
  (eval `(with-eval-after-load ',feature
           (emacsvox-sage--install-advice))))

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

;;; emacsvox-sage.el ends here
