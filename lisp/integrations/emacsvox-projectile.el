;;; emacsvox-projectile.el --- PROJECTILE  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop projectile
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

;; PROJECTILE ==  @samp{M-x package-install projectile}.
;; Project management in Emacs.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Emacsvox Helpers:

(defun emacsvox-projectile-file-action ()
  "speak for file open actions."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

;;;  Speech-enable Interactive Commands:

(defvar emacsvox-projectile--advice nil
  "Current Projectile targets and their native advice functions.")
(setq emacsvox-projectile--advice nil)

(defun emacsvox--advice-projectile-vc-after (&rest _)
  "speak."
  (when (ems-interactive-p 'projectile-vc)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(push '(projectile-vc :after emacsvox--advice-projectile-vc-after)
      emacsvox-projectile--advice)

(defun emacsvox-projectile--register-after-group (targets feedback)
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
            emacsvox-projectile--advice))))

(defun emacsvox-projectile--task-feedback ()
  "Speak after completing a Projectile task."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-line))

(emacsvox-projectile--register-after-group
 '(projectile-ag projectile-cleanup-known-projects
   projectile-clear-known-projects projectile-compile-project
   projectile-run-async-shell-command-in-root
   projectile-run-command-in-root projectile-run-project
   projectile-run-shell-command-in-root projectile-test-project
   projectile-ibuffer)
 #'emacsvox-projectile--task-feedback)
(add-hook 'projectile-find-file-hook 'emacsvox-projectile-file-action)

(defun emacsvox--advice-projectile-edit-dir-locals-after (&rest _)
  "speak."
  (when (ems-interactive-p 'projectile-edit-dir-locals)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(push '(projectile-edit-dir-locals :after
        emacsvox--advice-projectile-edit-dir-locals-after)
      emacsvox-projectile--advice)

(defun emacsvox-projectile--shell-feedback ()
  "Speak a newly opened Projectile shell."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))

(emacsvox-projectile--register-after-group
 '(projectile-run-shell projectile-run-eshell projectile-run-term)
 #'emacsvox-projectile--shell-feedback)

(defun emacsvox-projectile--install-advice ()
  "Install native advice after Projectile loads."
  (dolist (entry emacsvox-projectile--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'projectile
  (emacsvox-projectile--install-advice))

(provide 'emacsvox-projectile)

;;; emacsvox-projectile.el ends here
