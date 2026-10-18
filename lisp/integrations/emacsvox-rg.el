;;; emacsvox-rg.el --- Speech-enable RG  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop rg
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
;; RG ==  Emacs front-end to ripgrep (rg).

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'rg "rg" 'no-error)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (rg-context-face voice-bolden)
   (rg-error-face voice-animate)
   (rg-file-tag-face voice-smoothen)
   (rg-filename-face voice-annotate)
   (rg-info-face voice-monotone-extra)
   (rg-line-number-face voice-lighten)
   (rg-literal-face voice-monotone)
   (rg-match-face voice-lighten)
   (rg-match-position-face voice-lighten)
   (rg-regexp-face voice-monotone)
   (rg-toggle-off-face voice-smoothen)
   (rg-toggle-on-face voice-brighten)
   (rg-warning-face voice-animate)
   ))

;;;  Interactive Commands:

(defvar emacsvox-rg--advice nil
  "Current rg targets and their native advice functions.")
(setq emacsvox-rg--advice nil)

(defun emacsvox-rg--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-rg--advice))))

(defun emacsvox-rg--task-feedback ()
  "Announce completion of an rg search task."
  (emacsvox-icon 'task-done))

(emacsvox-rg--register-after-group
 '(rg rg-dwim rg-project rg-rerun-change-dir rg-rerun-change-regexp
   rg-rerun-change-files rg-rerun-toggle-ignore rg-rerun-toggle-case)
 #'emacsvox-rg--task-feedback)

(defun emacsvox-rg--file-feedback ()
  "Speak the selected rg file."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-rg--register-after-group
 '(rg-next-file rg-prev-file)
 #'emacsvox-rg--file-feedback)

(defun emacsvox-rg--save-feedback ()
  "Speak after saving an rg search."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(emacsvox-rg--register-after-group
 '(rg-save-search-as-name rg-save-search)
 #'emacsvox-rg--save-feedback)

(defun emacsvox-rg--install-advice ()
  "Install native advice after rg loads."
  (dolist (entry emacsvox-rg--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'rg
  (emacsvox-rg--install-advice))

(provide 'emacsvox-rg)

;;; emacsvox-rg.el ends here
