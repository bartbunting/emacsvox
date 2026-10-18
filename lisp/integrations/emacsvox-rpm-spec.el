;;; emacsvox-rpm-spec.el --- Speech enable rpm spec -*- lexical-binding: t; -*-

;; Copyright (c) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, rpm-spec streaming media
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
;; speech-enable rpm-spec-mode --part of Emacs 21 on RH 7.3
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)

;;;  Advice insertion commands:

(defvar emacsvox-rpm-spec-insertion-commands
  '(rpm-insert-file 
    rpm-insert-config 
    rpm-insert-doc 
    rpm-insert-ghost 
    rpm-insert-dir 
    rpm-insert-docdir 
    rpm-insert 
    rpm-insert-n
    rpm-insert-tag
    rpm-insert-packager)
  "List of rpm-spec insertion commands to speech-enable.")

(defvar emacsvox-rpm-spec--advice nil
  "Current rpm-spec targets and their native advice functions.")
(setq emacsvox-rpm-spec--advice nil)

(defun emacsvox-rpm-spec--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback ',target))))
      (push (list target :after advice-function)
            emacsvox-rpm-spec--advice))))

(defun emacsvox-rpm-spec--insertion-feedback (target)
  "Announce the RPM entry inserted by TARGET."
  (message "Inserted %s entry"
           (car (last (split-string (symbol-name target) "-")))))

(emacsvox-rpm-spec--register-after-group
 emacsvox-rpm-spec-insertion-commands
 #'emacsvox-rpm-spec--insertion-feedback)

;;;  Advice navigation 
(defvar emacsvox-rpm-spec-navigation-commands
  '(rpm-backward-section rpm-beginning-of-section 
                         rpm-forward-section 
                         rpm-end-of-section 
                         rpm-goto-section)
  "Navigation commands in rpm-spec to speech-enable.")
(defun emacsvox-rpm-spec--navigation-feedback (_target)
  "Speak after navigating an RPM spec."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-rpm-spec--register-after-group
 emacsvox-rpm-spec-navigation-commands
 #'emacsvox-rpm-spec--navigation-feedback)

;;;  Advice build commands 

(defvar emacsvox-rpm-spec-build-commands
  '(rpm-build-prepare rpm-list-check rpm-build-compile
    rpm-build-install rpm-build-binary rpm-build-source rpm-build-all)
  "Build commands from rpm-spec that are speech-enabled.")

(defun emacsvox-rpm-spec--build-feedback (target)
  "Announce the RPM build launched by TARGET."
  (emacsvox-icon 'task-done)
  (message "Launched build %s"
           (car (last (split-string (symbol-name target) "-")))))

(emacsvox-rpm-spec--register-after-group
 emacsvox-rpm-spec-build-commands
 #'emacsvox-rpm-spec--build-feedback)

;;;  advice toggles 
(defvar emacsvox-rpm-spec-toggle-commands
  '(rpm-toggle-short-circuit 
    rpm-toggle-rmsource 
    rpm-toggle-clean 
    rpm-toggle-nobuild
    rpm-toggle-sign-gpg 
    rpm-toggle-add-attr)
  "Toggle commands from rpm-spec that are speech-enabled.")

(defun emacsvox-rpm-spec--toggle-feedback (target)
  "Play the state of the RPM option toggled by TARGET."
  (let ((switch
         (intern
          (replace-regexp-in-string
           "toggle" "spec" (symbol-name target)))))
    (emacsvox-icon
     (if (and (boundp switch) (symbol-value switch)) 'on 'off))))

(emacsvox-rpm-spec--register-after-group
 emacsvox-rpm-spec-toggle-commands
 #'emacsvox-rpm-spec--toggle-feedback)

(defun emacsvox-rpm-spec--install-advice ()
  "Install native advice after rpm-spec-mode loads."
  (dolist (entry emacsvox-rpm-spec--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'rpm-spec-mode
  (emacsvox-rpm-spec--install-advice))

;;;  voice locking 

(voice-setup-add-map
 '(
   (rpm-spec-macro-face voice-bolden)
   (rpm-spec-tag-face voice-smoothen)
   (rpm-spec-package-face voice-animate)
   (rpm-spec-dir-face voice-lighten)
   (rpm-spec-doc-face voice-smoothen-extra)
   (rpm-spec-ghost-face voice-smoothen-medium)
   ))

(provide 'emacsvox-rpm-spec)

;;; emacsvox-rpm-spec.el ends here
