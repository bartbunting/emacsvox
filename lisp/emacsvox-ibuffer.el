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
;; Location https://github.com/robertmeta/emacsvox
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
(require 'emacsvox-preamble)
(require 'ibuffer)
(require 'ibuf-ext)

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

(cl-loop
 for target in
 '(ibuffer ibuffer-other-window ibuffer-list-buffers ibuffer-customize)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after opening an Ibuffer-related display."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-update-after (&rest _)
  "Cue after an interactive Ibuffer refresh."
  (when (ems-interactive-p 'ibuffer-update)
    (emacsvox-icon 'modified-object)))

(advice-add
 'ibuffer-update :after #'emacsvox--advice-ibuffer-update-after
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-bury-buffer-around
    (original &rest arguments)
  "Call ORIGINAL once, then report the buried buffer when interactive."
  (let ((buffer (ibuffer-current-buffer t))
        (interactive-p (ems-interactive-p 'ibuffer-bury-buffer)))
    (let ((result (apply original arguments)))
      (when interactive-p
        (emacsvox-icon 'select-object)
        (message "Buried buffer %s" buffer))
      result)))

(advice-add
 'ibuffer-bury-buffer :around
 #'emacsvox--advice-ibuffer-bury-buffer-around
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-quit-window-around
    (original &rest arguments)
  "Call ORIGINAL and report an interactive quit originating in Ibuffer."
  (let ((ibuffer-p (derived-mode-p 'ibuffer-mode))
        (interactive-p (ems-interactive-p 'quit-window)))
    (let ((result (apply original arguments)))
      (when (and ibuffer-p interactive-p)
        (emacsvox-icon 'close-object)
        (emacsvox-speak-mode-line))
      result)))

(advice-add
 'quit-window :around #'emacsvox--advice-ibuffer-quit-window-around
 '((name . emacsvox-ibuffer)))

(cl-loop
 for target in
 '(ibuffer-backward-line ibuffer-forward-line
   ibuffer-backward-filter-group ibuffer-forward-filter-group
   ibuffer-backwards-next-marked ibuffer-forward-next-marked)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and summarize after interactive Ibuffer navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-ibuffer-summarize-line)
         (emacsvox-icon 'select-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(ibuffer-visit-buffer ibuffer-visit-buffer-1-window
   ibuffer-visit-buffer-other-window ibuffer-visit-buffer-other-frame)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively visiting an Ibuffer entry."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-visit-buffer-other-window-noselect-after
    (&rest _)
  "Report opening an Ibuffer entry without selecting its window."
  (when (ems-interactive-p 'ibuffer-visit-buffer-other-window-noselect)
    (emacsvox-icon 'select-object)
    (dtk-speak "Opened buffer in other window.")))

(advice-add
 'ibuffer-visit-buffer-other-window-noselect :after
 #'emacsvox--advice-ibuffer-visit-buffer-other-window-noselect-after
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-diff-with-file-after (&rest _)
  "Report an interactive Ibuffer file comparison."
  (when (ems-interactive-p 'ibuffer-diff-with-file)
    (message "Displayed differences in other window.")
    (emacsvox-icon 'task-done)))

(advice-add
 'ibuffer-diff-with-file :after
 #'emacsvox--advice-ibuffer-diff-with-file-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(ibuffer-do-view ibuffer-do-view-horizontally
   ibuffer-do-view-other-frame)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively viewing marked buffers."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-do-save-after (&rest _)
  "Report interactively saving marked buffers."
  (when (ems-interactive-p 'ibuffer-do-save)
    (message "Saving marked buffers.")
    (emacsvox-icon 'save-object)))

(advice-add
 'ibuffer-do-save :after #'emacsvox--advice-ibuffer-do-save-after
 '((name . emacsvox)))

(cl-loop
 for (target icon) in
 '((ibuffer-mark-forward mark-object)
   (ibuffer-mark-for-delete mark-object)
   (ibuffer-mark-for-delete-backwards mark-object)
   (ibuffer-unmark-forward deselect-object)
   (ibuffer-unmark-backward deselect-object)
   (ibuffer-unmark-all deselect-object))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively changing an Ibuffer mark."
       (when (ems-interactive-p ',target)
         (emacsvox-icon ',icon)
         (emacsvox-ibuffer-speak-buffer-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-toggle-marks-after (&rest _)
  "Cue after interactively toggling Ibuffer marks."
  (when (ems-interactive-p 'ibuffer-toggle-marks)
    (emacsvox-icon 'select-object)))

(advice-add
 'ibuffer-toggle-marks :after
 #'emacsvox--advice-ibuffer-toggle-marks-after
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-interactive-filter-by-mode-after (&rest _)
  "Report the qualifiers after interactively filtering by mode."
  (when (ems-interactive-p 'ibuffer-interactive-filter-by-mode)
    (emacsvox-icon 'modified-object)
    (dtk-speak
     (concat "Filtered by " (format "%s" ibuffer-filtering-qualifiers)))))

(advice-add
 'ibuffer-interactive-filter-by-mode :after
 #'emacsvox--advice-ibuffer-interactive-filter-by-mode-after
 '((name . emacsvox)))

(cl-loop
 for (target announcement) in
 '((ibuffer-recompile-formats "Recompiled formats")
   (ibuffer-switch-format "Switched formats"))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and report an interactive Ibuffer format change."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)
         (dtk-speak ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-toggle-filter-group-after (&rest _)
  "Report the group toggled interactively at point."
  (when (ems-interactive-p 'ibuffer-toggle-filter-group)
    (let ((name
           (get-text-property (point) 'ibuffer-filter-group-name)))
      (emacsvox-icon 'modified-object)
      (dtk-speak (concat "Toggled group " (format "%s" name))))))

(advice-add
 'ibuffer-toggle-filter-group :after
 #'emacsvox--advice-ibuffer-toggle-filter-group-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(ibuffer-do-shell-command-pipe-replace
   ibuffer-do-shell-command-pipe
   ibuffer-do-shell-command-file
   ibuffer-do-rename-uniquely
   ibuffer-do-replace-regexp
   ibuffer-do-kill-lines)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue completion of an interactive Ibuffer operation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for (target announcement) in
 '((ibuffer-filters-to-filter-group "Group added.")
   (ibuffer-set-filter-groups-by-mode "Filtered by major mode.")
   (ibuffer-clear-filter-groups "Cleared all filter groups."))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and report an interactive Ibuffer filter-group change."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)
         (dtk-speak ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-pop-filter-group-around
    (original &rest arguments)
  "Call ORIGINAL once, then report the popped filter group."
  (let ((name (caar ibuffer-filter-groups))
        (interactive-p (ems-interactive-p 'ibuffer-pop-filter-group)))
    (let ((result (apply original arguments)))
      (when interactive-p
        (emacsvox-icon 'task-done)
        (dtk-speak (format "Popped group %s" name)))
      result)))

(advice-add
 'ibuffer-pop-filter-group :around
 #'emacsvox--advice-ibuffer-pop-filter-group-around
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-jump-to-filter-group-after (&rest _)
  "Cue and speak after an interactive filter-group jump."
  (when (ems-interactive-p 'ibuffer-jump-to-filter-group)
    (emacsvox-icon 'large-movement)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add
 'ibuffer-jump-to-filter-group :after
 #'emacsvox--advice-ibuffer-jump-to-filter-group-after
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-kill-filter-group-after (name)
  "Report interactively killing the filter group NAME."
  (when (ems-interactive-p 'ibuffer-kill-filter-group)
    (emacsvox-icon 'delete-object)
    (dtk-speak (format "Killed %s group." name))))

(advice-add
 'ibuffer-kill-filter-group :after
 #'emacsvox--advice-ibuffer-kill-filter-group-after
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-yank-filter-group-around
    (original &rest arguments)
  "Call ORIGINAL once and report the yanked filter group."
  (let ((name (caar ibuffer-filter-group-kill-ring))
        (interactive-p (ems-interactive-p 'ibuffer-yank-filter-group)))
    (when interactive-p
      (emacsvox-icon 'yank-object))
    (let ((result (apply original arguments)))
      (when interactive-p
        (dtk-speak (format "Yanked %s group." name)))
      result)))

(advice-add
 'ibuffer-yank-filter-group :around
 #'emacsvox--advice-ibuffer-yank-filter-group-around
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-filter-disable-after (&rest _)
  "Report interactively disabling all Ibuffer filters."
  (when (ems-interactive-p 'ibuffer-filter-disable)
    (emacsvox-icon 'task-done)
    (dtk-speak "Disabled all filters.")))

(advice-add
 'ibuffer-filter-disable :after
 #'emacsvox--advice-ibuffer-filter-disable-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(ibuffer-filter-by-mode ibuffer-filter-by-used-mode
   ibuffer-filter-by-name ibuffer-filter-by-filename
   ibuffer-filter-by-size-gt ibuffer-filter-by-size-lt
   ibuffer-filter-by-content ibuffer-filter-by-predicate
   ibuffer-toggle-sorting-mode ibuffer-invert-sorting)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue an interactive Ibuffer filtering or sorting change."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for (target announcement) in
 '((ibuffer-do-sort-by-major-mode "Sorted by major mode.")
   (ibuffer-do-sort-by-alphabetic "Sorted alphabetically.")
   (ibuffer-do-sort-by-size "Sorted by size."))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and report an interactive Ibuffer sort."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)
         (dtk-speak ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-bs-show-after (&rest _)
  "Cue and speak after interactively showing an Ibuffer BS display."
  (when (ems-interactive-p 'ibuffer-bs-show)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add
 'ibuffer-bs-show :after #'emacsvox--advice-ibuffer-bs-show-after
 '((name . emacsvox)))

(cl-loop
 for (target announcement) in
 '((ibuffer-bs-toggle-all "Toggled show all.")
   (ibuffer-add-to-tmp-hide "Buffer hidden.")
   (ibuffer-add-to-tmp-show "Buffer added."))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and report an interactive Ibuffer BS visibility change."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'task-done)
         (dtk-speak ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-jump-to-buffer-after (&rest _)
  "Cue and speak after interactively jumping to an Ibuffer entry."
  (when (ems-interactive-p 'ibuffer-jump-to-buffer)
    (emacsvox-icon 'large-movement)
    (emacsvox-ibuffer-speak-buffer-line)))

(advice-add
 'ibuffer-jump-to-buffer :after
 #'emacsvox--advice-ibuffer-jump-to-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-ibuffer-copy-filename-as-kill-after (&rest _)
  "Report how many filenames were copied interactively."
  (when (ems-interactive-p 'ibuffer-copy-filename-as-kill)
    (emacsvox-icon 'delete-object)
    (dtk-speak
     (format "copied %s filenames." (ibuffer-count-marked-lines)))))

(advice-add
 'ibuffer-copy-filename-as-kill :after
 #'emacsvox--advice-ibuffer-copy-filename-as-kill-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(ibuffer-mark-by-name-regexp
   ibuffer-mark-by-mode-regexp
   ibuffer-mark-by-file-name-regexp
   ibuffer-mark-by-mode
   ibuffer-mark-modified-buffers
   ibuffer-mark-unsaved-buffers
   ibuffer-mark-dissociated-buffers
   ibuffer-mark-help-buffers
   ibuffer-mark-compressed-file-buffers
   ibuffer-mark-old-buffers
   ibuffer-mark-special-buffers
   ibuffer-mark-read-only-buffers
   ibuffer-mark-dired-buffers)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue after interactively marking matching Ibuffer entries."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'mark-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-ibuffer-pop-filter-after (&rest _)
  "Cue and speak after interactively popping an Ibuffer filter."
  (when (ems-interactive-p 'ibuffer-pop-filter)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-line)))

(advice-add
 'ibuffer-pop-filter :after
 #'emacsvox--advice-ibuffer-pop-filter-after
 '((name . emacsvox)))

(provide 'emacsvox-ibuffer)
;;;  end of file
