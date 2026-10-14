;;; emacsvox-settings-workflows.el --- Linked editing workflows -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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
;; Link focused menus to existing editors, retaining their persistence semantics.
;;; Code:
(require 'emacsvox-aural-menu)

(defun emacsvox-settings-workflows--open (feature command suffix &optional at-item)
  "Open COMMAND from FEATURE, returning to SUFFIX; optionally use captured AT-ITEM."
  (require feature)
  (let (opened)
    (emacsvox-aural-menu--open-browser
     (lambda ()
       (if at-item (emacsvox-aural-menu--call-at-item command)
         (call-interactively command))
       (setq opened (window-buffer (selected-window)))) suffix)
    (with-current-buffer opened
      (when (derived-mode-p 'emacsvox-aural-feedback-details-mode)
        (emacsvox-aural-feedback-outline-mode 1)
        (setq-local emacsvox-aural-ui--help-return-function
                    emacsvox-aural-ui--return-function)))))
(defun emacsvox-settings-workflows--change ()
  "Open a retained feedback draft for the captured source item."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-change-feedback
   #'emacsvox-aural-change-feedback 'emacsvox-settings-workflows--change t))
(defun emacsvox-settings-workflows--voice ()
  "Choose a voice mapping for the captured item in a preview draft."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-change-feedback
   #'emacsvox-aural-change-feedback--remap-at-point 'emacsvox-settings-workflows--voice t))
(defun emacsvox-settings-workflows--cue ()
  "Prepare a cue override for the captured item, choosing its scope explicitly."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-tools
   #'emacsvox-aural-remap-earcon-at-point 'emacsvox-settings-workflows--cue t))
(defun emacsvox-settings-workflows--explain ()
  "Explain the effective feedback for the captured item."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-explanation
   #'emacsvox-explain-aural-presentation 'emacsvox-settings-workflows--explain t))
(defun emacsvox-settings-workflows--recent ()
  "Review retained feedback and edit the selected frozen record."
  (interactive)
  (emacsvox-settings-workflows--open 'emacsvox-aural-recent-feedback
   #'emacsvox-aural-list-recent-feedback 'emacsvox-settings-workflows--recent))

;;;###autoload
(transient-define-prefix emacsvox-settings-feedback ()
  "Explain and edit current or recent feedback, preserving source context."
  ["Captured item"
   ("x" "Explain effective feedback" emacsvox-settings-workflows--explain :transient transient--do-suspend)
   ("c" "Change voice, cue, or tone (preview draft)" emacsvox-settings-workflows--change :transient transient--do-suspend)
   ("v" "Choose a voice for this item" emacsvox-settings-workflows--voice :transient transient--do-suspend)
   ("e" "Remap a cue with explicit scope" emacsvox-settings-workflows--cue :transient transient--do-suspend)]
  ["Recent feedback"
   ("h" "Review, replay, and edit retained feedback" emacsvox-settings-workflows--recent :transient transient--do-suspend)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-settings-feedback nil nil :scope (emacsvox-aural-menu--context)))

(provide 'emacsvox-settings-workflows)
;;; emacsvox-settings-workflows.el ends here
