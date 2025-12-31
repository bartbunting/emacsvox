;;; emacsvox-ibuffer.el --- speech-enable ibuffer -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable ibuffer
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;  required modules
(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;; Commentary:

;; speech-enable ibuffer.el
;; this is an alternative to buffer-menu
;;; Code:

;;;  helpers 

(defun emacsvox-ibuffer-speak-buffer-line ()
  "Speak information about this buffer"
  (interactive)
  
  (unless (eq major-mode 'ibuffer-mode)
    (error "This command can only be used in buffer menus"))
  (emacsvox-speak-line))

;;;  summarizers

(defun emacsvox-ibuffer-summarize-line ()
  "Summarize current line."
  (emacsvox-speak-line))

;;;  speech enable interactive commands 

(defun ems--ibuffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer :after #'ems--ibuffer-after)

(defun ems--ibuffer-other-window-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-other-window :after
            #'ems--ibuffer-other-window-after)

(defun ems--ibuffer-list-buffers-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-list-buffers :after
            #'ems--ibuffer-list-buffers-after)

(defun ems--ibuffer-update-after (&rest _)
  "speak."
  (when (ems-interactive-p) (emacsvox-icon 'modified-object)))

(advice-add 'ibuffer-update :after #'ems--ibuffer-update-after)

(defun ems--ibuffer-customize-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-customize :after #'ems--ibuffer-customize-after)

(defun ems--ibuffer-bury-buffer-around (orig-fun &rest args)
  "speak."
  (let ((buf (ibuffer-current-buffer t)))
    (when (ems-interactive-p)
      (apply orig-fun args) (emacsvox-icon 'select-object)
      (message "Buried buffer %s" buf))))

(advice-add 'ibuffer-bury-buffer :around
            #'ems--ibuffer-bury-buffer-around)

(defun ems--ibuffer-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-quit :after #'ems--ibuffer-quit-after)

(defun ems--ibuffer-backward-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ibuffer-summarize-line) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-backward-line :after
            #'ems--ibuffer-backward-line-after)

(defun ems--ibuffer-forward-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ibuffer-summarize-line) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-forward-line :after
            #'ems--ibuffer-forward-line-after)

(defun ems--ibuffer-backward-filter-group-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ibuffer-summarize-line) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-backward-filter-group :after
            #'ems--ibuffer-backward-filter-group-after)

(defun ems--ibuffer-forward-filter-group-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ibuffer-summarize-line) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-forward-filter-group :after
            #'ems--ibuffer-forward-filter-group-after)

(defun ems--ibuffer-backwards-next-marked-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ibuffer-summarize-line) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-backwards-next-marked :after
            #'ems--ibuffer-backwards-next-marked-after)

(defun ems--ibuffer-forward-next-marked-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ibuffer-summarize-line) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-forward-next-marked :after
            #'ems--ibuffer-forward-next-marked-after)

(defun ems--ibuffer-visit-buffer-after (&rest _)
  "Provide spoken status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-visit-buffer :after
            #'ems--ibuffer-visit-buffer-after)

(defun ems--ibuffer-visit-buffer-1-window-after (&rest _)
  "Provide spoken status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-visit-buffer-1-window :after
            #'ems--ibuffer-visit-buffer-1-window-after)

(defun ems--ibuffer-visit-buffer-other-window-after (&rest _)
  "Provide spoken status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-visit-buffer-other-window :after
            #'ems--ibuffer-visit-buffer-other-window-after)

(defun ems--ibuffer-visit-buffer-other-window-noselect-after (&rest _)
  "Provide spoken status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (dtk-speak "Opened buffer in other window.")))

(advice-add 'ibuffer-visit-buffer-other-window-noselect :after
            #'ems--ibuffer-visit-buffer-other-window-noselect-after)

(defun ems--ibuffer-visit-buffer-other-frame-after (&rest _)
  "Provide spoken status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-visit-buffer-other-frame :after
            #'ems--ibuffer-visit-buffer-other-frame-after)

(defun ems--ibuffer-diff-with-file-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (message "Displayed differences in other window.")
    (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-diff-with-file :after
            #'ems--ibuffer-diff-with-file-after)

(defun ems--ibuffer-limit-disable-after (&rest _)
  "Speak status information."
  (when (ems-interactive-p) (message "Disabled limiting.")))

(advice-add 'ibuffer-limit-disable :after
            #'ems--ibuffer-limit-disable-after)

(defun ems--ibuffer-do-view-after (&rest _)
  "Speak status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-do-view :after #'ems--ibuffer-do-view-after)

(defun ems--ibuffer-do-view-horizontally-after (&rest _)
  "Speak status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-do-view-horizontally :after
            #'ems--ibuffer-do-view-horizontally-after)

(defun ems--ibuffer-do-view-other-frame-after (&rest _)
  "Speak status information."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-do-view-other-frame :after
            #'ems--ibuffer-do-view-other-frame-after)

(defun ems--ibuffer-do-save-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Saving marked buffers.") (emacsvox-icon 'save-object)))

(advice-add 'ibuffer-do-save :after #'ems--ibuffer-do-save-after)

(defun ems--ibuffer-occur-goto-occurence-after (&rest _)
  "Speak line that becomes current."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'ibuffer-occur-goto-occurence :after
            #'ems--ibuffer-occur-goto-occurence-after)

(defun ems--ibuffer-occur-display-occurence-after (&rest _)
  "Speak line that becomes current."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-occur-display-occurence :after
            #'ems--ibuffer-occur-display-occurence-after)

(defun ems--ibuffer-mark-forward-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-mark-forward :after
            #'ems--ibuffer-mark-forward-after)

(defun ems--ibuffer-unmark-forward-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-unmark-forward :after
            #'ems--ibuffer-unmark-forward-after)

(defun ems--ibuffer-unmark-backward-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-unmark-backward :after
            #'ems--ibuffer-unmark-backward-after)

(defun ems--ibuffer-unmark-all-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-unmark-all :after #'ems--ibuffer-unmark-all-after)

(defun ems--ibuffer-toggle-marks-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'select-object)))

(advice-add 'ibuffer-toggle-marks :after
            #'ems--ibuffer-toggle-marks-after)

(defun ems--ibuffer-mark-for-delete-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-mark-for-delete :after
            #'ems--ibuffer-mark-for-delete-after)

(defun ems--ibuffer-mark-for-delete-backwards-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-mark-for-delete-backwards :after
            #'ems--ibuffer-mark-for-delete-backwards-after)

(defun ems--ibuffer-interactive-filter-by-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'modified-object)
    (dtk-speak
     (concat "Filtered by " (format "%s" ibuffer-filtering-qualifiers)))))

(advice-add 'ibuffer-interactive-filter-by-mode :after
            #'ems--ibuffer-interactive-filter-by-mode-after)

(defun ems--ibuffer-recompile-formats-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Recompiled formats")))

(advice-add 'ibuffer-recompile-formats :after
            #'ems--ibuffer-recompile-formats-after)

(defun ems--ibuffer-switch-format-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Switched formats")))

(advice-add 'ibuffer-switch-format :after
            #'ems--ibuffer-switch-format-after)

(defun ems--ibuffer-toggle-filter-group-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (let
        ((name (get-text-property (point) 'ibuffer-filter-group-name)))
      (emacsvox-icon 'modified-object)
      (dtk-speak (concat "Toggled group " (format "%s" name))))))

(advice-add 'ibuffer-toggle-filter-group :after
            #'ems--ibuffer-toggle-filter-group-after)

(defun ems--ibuffer-do-shell-command-pipe-replace-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-do-shell-command-pipe-replace :after
            #'ems--ibuffer-do-shell-command-pipe-replace-after)

(defun ems--ibuffer-do-shell-command-pipe-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-do-shell-command-pipe :after
            #'ems--ibuffer-do-shell-command-pipe-after)

(defun ems--ibuffer-do-shell-command-file-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-do-shell-command-file :after
            #'ems--ibuffer-do-shell-command-file-after)

(defun ems--ibuffer-do-rename-uniquely-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-do-rename-uniquely :after
            #'ems--ibuffer-do-rename-uniquely-after)

(defun ems--ibuffer-do-replace-regexp-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-do-replace-regexp :after
            #'ems--ibuffer-do-replace-regexp-after)

(defun ems--ibuffer-filters-to-filter-group-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Group added.")))

(advice-add 'ibuffer-filters-to-filter-group :after
            #'ems--ibuffer-filters-to-filter-group-after)

(defun ems--ibuffer-set-filter-groups-by-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Filtered by major mode.")))

(advice-add 'ibuffer-set-filter-groups-by-mode :after
            #'ems--ibuffer-set-filter-groups-by-mode-after)

(defun ems--ibuffer-pop-filter-group-around (orig-fun &rest args)
  "speak."
  (when (ems-interactive-p)
    (let ((name (car (car ibuffer-filter-groups))))
      (apply orig-fun args) (emacsvox-icon 'task-done)
      (dtk-speak (concat "Popped group " (format "%s" name))))))

(advice-add 'ibuffer-pop-filter-group :around
            #'ems--ibuffer-pop-filter-group-around)

(defun ems--ibuffer-clear-filter-groups-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (dtk-speak "Cleared all filter groups.")))

(advice-add 'ibuffer-clear-filter-groups :after
            #'ems--ibuffer-clear-filter-groups-after)

(defun ems--ibuffer-jump-to-filter-group-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-jump-to-filter-group :after
            #'ems--ibuffer-jump-to-filter-group-after)

(defun ems--ibuffer-kill-filter-group-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (dtk-speak (format "Killed %s group." name))))

(advice-add 'ibuffer-kill-filter-group :after
            #'ems--ibuffer-kill-filter-group-after)

(defun ems--ibuffer-yank-filter-group-around (orig-fun &rest args)
  "speak"
  (when (ems-interactive-p)
    (let ((name (car (car ibuffer-filter-group-kill-ring))))
      (emacsvox-icon 'yank-object) (apply orig-fun args)
      (dtk-speak (format "Yanked %s group." name)))))

(advice-add 'ibuffer-yank-filter-group :around
            #'ems--ibuffer-yank-filter-group-around)

(defun ems--ibuffer-filter-disable-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Disabled all filters.")))

(advice-add 'ibuffer-filter-disable :after
            #'ems--ibuffer-filter-disable-after)

(defun ems--ibuffer-filter-by-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-mode :after
            #'ems--ibuffer-filter-by-mode-after)

(defun ems--ibuffer-filter-by-used-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-used-mode :after
            #'ems--ibuffer-filter-by-used-mode-after)

(defun ems--ibuffer-filter-by-name-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-name :after
            #'ems--ibuffer-filter-by-name-after)

(defun ems--ibuffer-filter-by-filename-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-filename :after
            #'ems--ibuffer-filter-by-filename-after)

(defun ems--ibuffer-filter-by-size-gt-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-size-gt :after
            #'ems--ibuffer-filter-by-size-gt-after)

(defun ems--ibuffer-filter-by-size-lt-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-size-lt :after
            #'ems--ibuffer-filter-by-size-lt-after)

(defun ems--ibuffer-filter-by-content-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-content :after
            #'ems--ibuffer-filter-by-content-after)

(defun ems--ibuffer-filter-by-predicate-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-predicate :after
            #'ems--ibuffer-filter-by-predicate-after)

(defun ems--ibuffer-filter-by-predicate-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-filter-by-predicate :after
            #'ems--ibuffer-filter-by-predicate-after)

(defun ems--ibuffer-toggle-sorting-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-toggle-sorting-mode :after
            #'ems--ibuffer-toggle-sorting-mode-after)

(defun ems--ibuffer-toggle-sorting-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-toggle-sorting-mode :after
            #'ems--ibuffer-toggle-sorting-mode-after)

(defun ems--ibuffer-invert-sorting-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-invert-sorting :after
            #'ems--ibuffer-invert-sorting-after)

(defun ems--ibuffer-do-sort-by-major-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Sorted by major mode.")))

(advice-add 'ibuffer-do-sort-by-major-mode :after
            #'ems--ibuffer-do-sort-by-major-mode-after)

(defun ems--ibuffer-do-sort-by-alphabetic-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Sorted alphabetically.")))

(advice-add 'ibuffer-do-sort-by-alphabetic :after
            #'ems--ibuffer-do-sort-by-alphabetic-after)

(defun ems--ibuffer-do-sort-by-size-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Sorted by size.")))

(advice-add 'ibuffer-do-sort-by-size :after
            #'ems--ibuffer-do-sort-by-size-after)

(defun ems--ibuffer-bs-show-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'ibuffer-bs-show :after #'ems--ibuffer-bs-show-after)

(defun ems--ibuffer-bs-toggle-all-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Toggled show all.")))

(advice-add 'ibuffer-bs-toggle-all :after
            #'ems--ibuffer-bs-toggle-all-after)

(defun ems--ibuffer-add-to-tmp-hide-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Buffer hidden.")))

(advice-add 'ibuffer-add-to-tmp-hide :after
            #'ems--ibuffer-add-to-tmp-hide-after)

(defun ems--ibuffer-add-to-tmp-show-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Buffer added.")))

(advice-add 'ibuffer-add-to-tmp-show :after
            #'ems--ibuffer-add-to-tmp-show-after)

(defun ems--ibuffer-do-kill-lines-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'ibuffer-do-kill-lines :after
            #'ems--ibuffer-do-kill-lines-after)

(defun ems--ibuffer-jump-to-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add 'ibuffer-jump-to-buffer :after
            #'ems--ibuffer-jump-to-buffer-after)

(defun ems--ibuffer-copy-filename-as-kill-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Buffer added.")))

(advice-add 'ibuffer-copy-filename-as-kill :after
            #'ems--ibuffer-copy-filename-as-kill-after)

(defun ems--ibuffer-copy-filename-as-kill-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (dtk-speak
     (format "copied %s filenames." (ibuffer-count-marked-lines)))))

(advice-add 'ibuffer-copy-filename-as-kill :after
            #'ems--ibuffer-copy-filename-as-kill-after)

(defun ems--ibuffer-mark-by-name-regexp-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-by-name-regexp :after
            #'ems--ibuffer-mark-by-name-regexp-after)

(defun ems--ibuffer-mark-by-mode-regexp-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-by-mode-regexp :after
            #'ems--ibuffer-mark-by-mode-regexp-after)

(defun ems--ibuffer-mark-by-file-name-regexp-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-by-file-name-regexp :after
            #'ems--ibuffer-mark-by-file-name-regexp-after)

(defun ems--ibuffer-mark-by-mode-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-by-mode :after
            #'ems--ibuffer-mark-by-mode-after)

(defun ems--ibuffer-mark-modified-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-modified-buffers :after
            #'ems--ibuffer-mark-modified-buffers-after)

(defun ems--ibuffer-mark-unsaved-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-unsaved-buffers :after
            #'ems--ibuffer-mark-unsaved-buffers-after)

(defun ems--ibuffer-mark-dissociated-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-dissociated-buffers :after
            #'ems--ibuffer-mark-dissociated-buffers-after)

(defun ems--ibuffer-mark-help-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-help-buffers :after
            #'ems--ibuffer-mark-help-buffers-after)

(defun ems--ibuffer-mark-compressed-file-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-compressed-file-buffers :after
            #'ems--ibuffer-mark-compressed-file-buffers-after)

(defun ems--ibuffer-mark-old-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-old-buffers :after
            #'ems--ibuffer-mark-old-buffers-after)

(defun ems--ibuffer-mark-special-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-special-buffers :after
            #'ems--ibuffer-mark-special-buffers-after)

(defun ems--ibuffer-mark-read-only-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-read-only-buffers :after
            #'ems--ibuffer-mark-read-only-buffers-after)

(defun ems--ibuffer-mark-dired-buffers-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'mark-object)))

(advice-add 'ibuffer-mark-dired-buffers :after
            #'ems--ibuffer-mark-dired-buffers-after)

(defun ems--ibuffer-pop-filter-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'ibuffer-pop-filter :after #'ems--ibuffer-pop-filter-after)

(provide 'emacsvox-ibuffer)
;;;  end of file

