;;; emacsvox-journalctl.el --- JOURNALCTL  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop journalctl
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
;;; JOURNALCTL ==  SystemD Journal From emacs
;; See https://github.com/SebastianMeisel/journalctl-mode 

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (journalctl-error-face voice-animate)
   (journalctl-finished-face voice-lighten)
   (journalctl-host-face voice-smoothen)
   (journalctl-process-face voice-brighten)
   (journalctl-starting-face voice-lighten)
   (journalctl-timestamp-face voice-bolden)
   (journalctl-warning-face voice-animate)))

;;;  Interactive Commands:

(defvar emacsvox-journalctl--advice nil
  "Current journalctl-mode targets and their native advice functions.")
(setq emacsvox-journalctl--advice nil)

(defun emacsvox-journalctl--register-after-group (targets feedback)
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
            emacsvox-journalctl--advice))))

(defun emacsvox-journalctl--open-feedback ()
  "Speak a newly opened journal."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-journalctl--register-after-group
 '(journalctl)
 #'emacsvox-journalctl--open-feedback)

(defun emacsvox-journalctl--scroll-feedback ()
  "Speak after moving through journal output."
  (emacsvox-icon 'scroll)
  (emacsvox-speak-line))

(emacsvox-journalctl--register-after-group
 '(journalctl-scroll-up journalctl-scroll-down
   journalctl-previous-chunk journalctl-next-chunk)
 #'emacsvox-journalctl--scroll-feedback)

(defun emacsvox--advice-journalctl-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'journalctl-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(push '(journalctl-quit :after emacsvox--advice-journalctl-quit-after)
      emacsvox-journalctl--advice)

(defun emacsvox-journalctl--install-advice ()
  "Install native advice after journalctl-mode loads."
  (dolist (entry emacsvox-journalctl--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'journalctl-mode
  (emacsvox-journalctl--install-advice))

(provide 'emacsvox-journalctl)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-journalctl.el ends here
