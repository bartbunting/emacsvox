;;; emacsvox-bs.el --- speech-enable bs -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
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

;; speech-enable bs.el -- an alternative to Emacs' default  list-buffers

;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'bs)

;;;  Helpers:

(defun emacsvox-bs--buffer-facts (modified read-only)
  "Return semantic facts for a buffer with MODIFIED and READ-ONLY state."
  (let ((states
         (delq
          nil
          (list
           (and modified 'modified)
           (and read-only 'read-only)))))
    (append
     '(:role buffer-entry)
     (when states (list :states states)))))

(defun emacsvox-bs--submit
    (content facts occasion &optional icon)
  "Submit BS CONTENT under FACTS and OCCASION with optional legacy ICON."
  (let ((actions
         (when icon
           (list (emacsvox-aural-compatibility-icon icon)))))
    (if (and (stringp content) (> (length content) 0))
        (emacsvox-aural-submit
         content
         :facts facts
         :module 'bs
         :occasion occasion
         :compatibility-actions actions)
      (emacsvox-aural-submit-actions
       :facts facts
       :module 'bs
       :occasion occasion
       :compatibility-actions actions))))

(defun emacsvox-bs--buffer-summary ()
  "Return a concise voice-preserving summary of the selected buffer."
  (concat
   (propertize (buffer-name) 'personality voice-lighten-medium)
   ", "
   (propertize
    (downcase
     (or
      (and (stringp mode-name) mode-name)
      (and (listp mode-name) (cl-find-if #'stringp mode-name))
      (replace-regexp-in-string
       "-mode\\'" "" (symbol-name major-mode))))
    'personality voice-animate)))

(defun emacsvox-bs--submit-current-buffer (icon)
  "Submit the selected buffer summary with leading compatibility ICON."
  (emacsvox-bs--submit
   (emacsvox-bs--buffer-summary)
   (emacsvox-bs--buffer-facts
    (buffer-modified-p) buffer-read-only)
   'state-change icon))

(defun emacsvox-bs--submit-action (icon)
  "Submit an action-only BS presentation with compatibility ICON."
  (emacsvox-bs--submit
   nil '(:role buffer-entry) 'state-change icon))

(defun emacsvox-bs-speak-buffer-line (&optional icon)
  "Speak information about the BS buffer row at point.
Optional ICON precedes the row in the same native transaction."
  (interactive)
  (unless (eq major-mode 'bs-mode)
    (error "This command can only be used in buffer menus"))
  (let ((buffer (bs--current-buffer)))
    (cond
     ((get-buffer buffer)
      (let ((with (propertize "with size " 'personality voice-smoothen))
            (name (buffer-name buffer))
            (file (buffer-file-name buffer))
            this-buffer-read-only this-buffer-modified-p
            this-buffer-size
            this-buffer-directory)
        (save-current-buffer
          (set-buffer buffer)
          (setq this-buffer-read-only buffer-read-only)
          (setq this-buffer-modified-p (buffer-modified-p))
          (setq this-buffer-size (buffer-size))
          (or file
              ;; No visited file.  Check local value of
              ;; list-buffers-directory.
              (if (and (boundp 'list-buffers-directory)
                       list-buffers-directory)
                  (setq this-buffer-directory list-buffers-directory))))
        (emacsvox-bs--submit
         (concat 
          name " "
          (format-mode-line mode-name)
          (if (or file this-buffer-directory)
              (format " visiting %s "
                      (or file this-buffer-directory))
            "")
          with
          (format " %s " this-buffer-size))
         (emacsvox-bs--buffer-facts
          this-buffer-modified-p this-buffer-read-only)
         'navigation icon)))
     (t
      (emacsvox-bs--submit
       (buffer-substring
        (line-beginning-position) (line-end-position))
       '(:role buffer-entry) 'inspection 'warn-user)))))

;;;  speech enable interactive commands 

(defun emacsvox--advice-bs-mode-after (&rest _)
  "Enable legacy voices and native aural context in BS mode."
  (setq voice-lock-mode t)
  (setq-local emacsvox-aural-module 'bs))

(advice-add 'bs-mode :after #'emacsvox--advice-bs-mode-after)

(defun emacsvox--advice-bs-kill-after (&rest _)
  "Present the buffer selected after leaving BS."
  (when (ems-interactive-p 'bs-kill)
    (emacsvox-bs--submit-current-buffer 'close-object)))

(advice-add 'bs-kill :after #'emacsvox--advice-bs-kill-after)

(defun emacsvox--advice-bs-abort-after (&rest _)
  "Present the buffer restored after aborting BS."
  (when (ems-interactive-p 'bs-abort)
    (emacsvox-bs--submit-current-buffer 'close-object)))

(advice-add 'bs-abort :after #'emacsvox--advice-bs-abort-after)

(defun emacsvox--advice-bs-set-configuration-and-refresh-after (&rest _)
  "Confirm an interactive BS configuration refresh."
  (when (ems-interactive-p 'bs-set-configuration-and-refresh)
    (emacsvox-bs--submit-action 'select-object)))

(advice-add 'bs-set-configuration-and-refresh :after
            #'emacsvox--advice-bs-set-configuration-and-refresh-after)

(defun emacsvox--advice-bs-refresh-after (&rest _)
  "Confirm an interactive BS refresh."
  (when (ems-interactive-p 'bs-refresh)
    (emacsvox-bs--submit-action 'select-object)))

(advice-add 'bs-refresh :after #'emacsvox--advice-bs-refresh-after)

(defun emacsvox--advice-bs-view-after (&rest _)
  "Present the buffer opened from BS."
  (when (ems-interactive-p 'bs-view)
    (emacsvox-bs--submit-current-buffer 'open-object)))

(advice-add 'bs-view :after #'emacsvox--advice-bs-view-after)

(defun emacsvox--advice-bs-select-after (&rest _)
  "Present the buffer selected from BS."
  (when (ems-interactive-p 'bs-select)
    (emacsvox-bs--submit-current-buffer 'open-object)))

(advice-add 'bs-select :after #'emacsvox--advice-bs-select-after)

(defun emacsvox--advice-bs-select-other-window-after (&rest _)
  "Present the buffer selected in another window."
  (when (ems-interactive-p 'bs-select-other-window)
    (emacsvox-bs--submit-current-buffer 'open-object)))

(advice-add 'bs-select-other-window :after
            #'emacsvox--advice-bs-select-other-window-after)

(defun emacsvox--advice-bs-tmp-select-other-window-after (&rest _)
  "Present the buffer temporarily selected in another window."
  (when (ems-interactive-p 'bs-tmp-select-other-window)
    (emacsvox-bs--submit-current-buffer 'open-object)))

(advice-add 'bs-tmp-select-other-window :after
            #'emacsvox--advice-bs-tmp-select-other-window-after)

(defun emacsvox--advice-bs-select-other-frame-after (&rest _)
  "Present the buffer selected in another frame."
  (when (ems-interactive-p 'bs-select-other-frame)
    (emacsvox-bs--submit-current-buffer 'open-object)))

(advice-add 'bs-select-other-frame :after
            #'emacsvox--advice-bs-select-other-frame-after)

(defun emacsvox--advice-bs-select-in-one-window-after (&rest _)
  "Present the buffer selected in one window."
  (when (ems-interactive-p 'bs-select-in-one-window)
    (emacsvox-bs--submit-current-buffer 'open-object)))

(advice-add 'bs-select-in-one-window :after
            #'emacsvox--advice-bs-select-in-one-window-after)

(defun emacsvox--advice-bs-bury-buffer-after (&rest _)
  "Confirm burying the selected buffer."
  (when (ems-interactive-p 'bs-bury-buffer)
    (emacsvox-bs--submit-action 'close-object)))

(advice-add 'bs-bury-buffer :after #'emacsvox--advice-bs-bury-buffer-after)

(defun emacsvox--advice-bs-save-after (&rest _)
  "Confirm saving the selected buffer."
  (when (ems-interactive-p 'bs-save)
    (emacsvox-bs--submit-action 'save-object)))

(advice-add 'bs-save :after #'emacsvox--advice-bs-save-after)

(defun emacsvox--advice-bs-toggle-current-to-show-after (&rest _)
  "Confirm changing the selected buffer's visibility."
  (when (ems-interactive-p 'bs-toggle-current-to-show)
    (emacsvox-bs-speak-buffer-line 'button)))

(advice-add 'bs-toggle-current-to-show :after
            #'emacsvox--advice-bs-toggle-current-to-show-after)

(defun emacsvox--advice-bs-set-current-buffer-to-show-never-after (&rest _)
  "Confirm changing the selected buffer's visibility."
  (when (ems-interactive-p 'bs-set-current-buffer-to-show-never)
    (emacsvox-bs-speak-buffer-line 'button)))

(advice-add 'bs-set-current-buffer-to-show-never :after
            #'emacsvox--advice-bs-set-current-buffer-to-show-never-after)

(defun emacsvox--advice-bs-mark-current-after (&rest _)
  "Present the row selected after marking."
  (when (ems-interactive-p 'bs-mark-current)
    (emacsvox-bs-speak-buffer-line 'mark-object)))

(advice-add 'bs-mark-current :after #'emacsvox--advice-bs-mark-current-after)

(defun emacsvox--advice-bs-unmark-current-after (&rest _)
  "Present the row selected after unmarking."
  (when (ems-interactive-p 'bs-unmark-current)
    (emacsvox-bs-speak-buffer-line 'deselect-object)))

(advice-add 'bs-unmark-current :after #'emacsvox--advice-bs-unmark-current-after)

(defun emacsvox--advice-bs-delete-after (&rest _)
  "Present the row selected after deleting a buffer."
  (when (ems-interactive-p 'bs-delete)
    (emacsvox-bs-speak-buffer-line 'delete-object)))

(advice-add 'bs-delete :after #'emacsvox--advice-bs-delete-after)

(defun emacsvox--advice-bs-delete-backward-after (&rest _)
  "Present the row selected after deleting backward."
  (when (ems-interactive-p 'bs-delete-backward)
    (emacsvox-bs-speak-buffer-line 'delete-object)))

(advice-add 'bs-delete-backward :after #'emacsvox--advice-bs-delete-backward-after)

(defun emacsvox--advice-bs-up-after (&rest _)
  "Present the selected row after moving up."
  (when (ems-interactive-p 'bs-up)
    (emacsvox-bs-speak-buffer-line 'select-object)))

(advice-add 'bs-up :after #'emacsvox--advice-bs-up-after)

(defun emacsvox--advice-bs-down-after (&rest _)
  "Present the selected row after moving down."
  (when (ems-interactive-p 'bs-down)
    (emacsvox-bs-speak-buffer-line 'select-object)))

(advice-add 'bs-down :after #'emacsvox--advice-bs-down-after)

(defun emacsvox--advice-bs-cycle-next-after (&rest _)
  "Present the buffer selected by cycling forward."
  (when (ems-interactive-p 'bs-cycle-next)
    (let ((emacsvox-speak-messages nil))
      (emacsvox-bs--submit-current-buffer 'select-object))))

(advice-add 'bs-cycle-next :after #'emacsvox--advice-bs-cycle-next-after)

(defun emacsvox--advice-bs-cycle-previous-after (&rest _)
  "Present the buffer selected by cycling backward."
  (when (ems-interactive-p 'bs-cycle-previous)
    (let ((emacsvox-speak-messages nil))
      (emacsvox-bs--submit-current-buffer 'select-object))))

(advice-add 'bs-cycle-previous :after #'emacsvox--advice-bs-cycle-previous-after)

(provide 'emacsvox-bs)

;;; emacsvox-bs.el ends here
