;;; emacsvox-rust-mode.el --- Speech-enable RUST -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop rust-mode
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
;; Speech-enable rust-mode

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (rust-builtin-formatting-macro-face voice-lighten)
   (rust-question-mark-face voice-smoothen)
   (rust-string-interpolation-face voice-lighten-medium)
   (rust-unsafe-face voice-animate)))

;;;  Interactive Commands: (rust-mode

(defconst emacsvox-rust-mode--task-targets
  '(rust-compile
    rust-run
    rust-test
    rust-run-clippy
    rust-promote-module-into-dir)
  "Rust Mode commands that dispatch tasks.")

(cl-loop
 for target in emacsvox-rust-mode--task-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'task-done))))) 

(defun emacsvox--advice-rust-dbg-wrap-or-unwrap-after (&rest _)
  "speak."
  (when (ems-interactive-p 'rust-dbg-wrap-or-unwrap)
    (emacsvox-icon 'task-done) (emacsvox-speak-line)))

(defun emacsvox--advice-rust-format-buffer-after (&rest _)
  "speak."
  (cond
   ((buffer-live-p (get-buffer rust-rustfmt-buffername))
    (emacsvox-icon 'open-object))
   (t (emacsvox-icon 'task-done))))

(defun emacsvox--advice-rust-goto-format-problem-after (&rest _)
  "speak."
  (when (ems-interactive-p 'rust-goto-format-problem)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'large-movement))))

(defun emacsvox--advice-rust-enable-format-on-save-after (&rest _)
  "speak."
  (when (ems-interactive-p 'rust-enable-format-on-save)
    (emacsvox-icon 'on) (message "Enabled format on save")))

(defun emacsvox--advice-rust-disable-format-on-save-after (&rest _)
  "speak."
  (when (ems-interactive-p 'rust-disable-format-on-save)
    (emacsvox-icon 'off) (message "Disabled format on save")))

(defconst emacsvox-rust-mode--navigation-targets
  '(rust-beginning-of-defun rust-end-of-defun)
  "Rust Mode definition navigation commands.")

(cl-loop
 for target in emacsvox-rust-mode--navigation-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defun emacsvox-rust-mode-setup ()
  "Setup additional keys etc."
  
  (when (and (bound-and-true-p rust-mode-map)
             (keymapp rust-mode-map))
    (define-key rust-mode-map (kbd "C-c C-c")'rust-compile)
    (define-key rust-mode-map (kbd "C-c C-r")'rust-run)
    (define-key rust-mode-map (kbd "C-c C-t")'rust-test)))

;;; Interactive Commands: rustic

(defconst emacsvox-rust-mode--rustic-targets
  '(rustic-beginning-of-defun
    rustic-end-of-defun
    rustic-beginning-of-function)
  "Current Rustic navigation commands.")

(cl-loop
 for target in emacsvox-rust-mode--rustic-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (let ((emacsvox-show-point t))
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line))))))

(defconst emacsvox-rust-mode--advice-targets
  (append
   emacsvox-rust-mode--task-targets
   '(rust-dbg-wrap-or-unwrap
     rust-format-buffer
     rust-goto-format-problem
     rust-enable-format-on-save
     rust-disable-format-on-save)
   emacsvox-rust-mode--navigation-targets
   emacsvox-rust-mode--rustic-targets)
  "Current Rust Mode and Rustic targets receiving native advice.")

(defun emacsvox-rust-mode--install-advice ()
  "Install advice for currently loaded Rust packages."
  (dolist (target emacsvox-rust-mode--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (when (featurep 'rust-mode)
    (emacsvox-rust-mode-setup)))

(dolist (feature '(rust-mode rustic))
  (eval-after-load feature #'emacsvox-rust-mode--install-advice))

(provide 'emacsvox-rust-mode)

;;; emacsvox-rust-mode.el ends here
