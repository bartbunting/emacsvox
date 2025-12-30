;;; emacsvox-rust-mode.el --- Speech-enable RUST -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable RUST-MODE An Emacs Interface to rust-mode
;; Keywords: Emacsvox,  Audio Desktop rust-mode
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNRUST-MODE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Speech-enable rust-mode

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (rust-builtin-formatting-macro-face voice-lighten)
   (rust-question-mark-face voice-smoothen)
   (rust-string-interpolation-face voice-lighten-medium)
   (rust-unsafe-face voice-animate)))

;;;  Interactive Commands: (rust-mode

(cl-loop
 for f in 
 '(
   rust-compile rust-run rust-test
   rust-run-clippy rust-promote-module-into-dir)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done))))) 


(defun ems--rust-dbg-wrap-or-unwrap-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (emacsvox-speak-line)))


(advice-add 'rust-dbg-wrap-or-unwrap :after
	    #'ems--rust-dbg-wrap-or-unwrap-after)





(defun ems--rust-format-buffer-after (&rest _)
  "speak."
  (cond
   ((buffer-live-p (get-buffer rust-rustfmt-buffername))
    (emacsvox-icon 'open-object))
   (t (emacsvox-icon 'task-done))))


(advice-add 'rust-format-buffer :after #'ems--rust-format-buffer-after)





(defun ems--rust-goto-format-problem-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))


(advice-add 'rust-goto-format-problem :after
	    #'ems--rust-goto-format-problem-after)





(defun ems--rust-enable-format-on-save-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'on) (message "Enabled format on save")))


(advice-add 'rust-enable-format-on-save :after
	    #'ems--rust-enable-format-on-save-after)





(defun ems--rust-disable-format-on-save-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'off) (message "Disabled format on save")))


(advice-add 'rust-disable-format-on-save :after
	    #'ems--rust-disable-format-on-save-after)




(cl-loop
 for f in
 '(rust-beginning-of-defun rust-end-of-defun)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defun emacsvox-rust-mode-setup ()
  "Setup additional keys etc."
  (cl-declare (special rust-mode-map))
  (when (and (bound-and-true-p rust-mode-map)
             (keymapp rust-mode-map))
    (define-key rust-mode-map (kbd "C-c C-c")'rust-compile)
    (define-key rust-mode-map (kbd "C-c C-r")'rust-run)
    (define-key rust-mode-map (kbd "C-c C-t")'rust-test)))

(emacsvox-rust-mode-setup)

;;; Interactive Commands: rustic

(cl-loop
 for f in 
 '(
   rustic-beginning-of-defun rustic-end-of-defun
   rustic-beginning-of-function rustic-end-of-string)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line))))))

(provide 'emacsvox-rust-mode)
;;;  end of file

