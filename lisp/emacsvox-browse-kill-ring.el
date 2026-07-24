;;; emacsvox-browse-kill-ring.el --- kill-ring -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for BROWSE-KILL-RING
;; Keywords: Emacsvox, browse-kill-ring
;;;   LCD Archive entry:
;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4074 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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


;;; Commentary:
;; Browse the kill ring using 
;; browse-kill-ring.el - interactively insert items from kill-ring 
;;; Code:

;;  required modules

;;; Code:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  speech-enable interactive commands

(defun emacsvox--advice-browse-kill-ring-undo-other-window-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-undo-other-window)
    (emacsvox-icon 'unmodified-object)))

(defun emacsvox--advice-browse-kill-ring-insert-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-insert)
    (emacsvox-icon 'yank-object)))

(defun emacsvox--advice-browse-kill-ring-insert-and-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-insert-and-quit)
    (emacsvox-icon 'yank-object) (emacsvox-speak-line)
    (emacsvox-icon 'close-object)))

(defun emacsvox--advice-browse-kill-ring-delete-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-delete)
    (emacsvox-icon 'delete-object)))

(defun emacsvox--advice-browse-kill-ring-forward-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-forward)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(defun emacsvox--advice-browse-kill-ring-previous-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-previous)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(defun emacsvox--advice-browse-kill-ring-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-browse-kill-ring-edit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-edit)
    (emacsvox-icon 'open-object)))

(defun emacsvox--advice-browse-kill-ring-edit-finish-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-edit-finish)
    (emacsvox-icon 'close-object)))

(defun emacsvox--advice-browse-kill-ring-occur-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-occur)
    (emacsvox-icon 'open-object)))

(defun emacsvox--advice-browse-kill-ring-update-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-update)
    (emacsvox-icon 'task-done)))

(defun emacsvox--advice-browse-kill-ring-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-browse-kill-ring-search-forward-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-search-forward)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(defun emacsvox--advice-browse-kill-ring-search-backward-after (&rest _)
  "speak."
  (when (ems-interactive-p 'browse-kill-ring-search-backward)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(defconst emacsvox-browse-kill-ring--advice
  '((browse-kill-ring-undo-other-window
     emacsvox--advice-browse-kill-ring-undo-other-window-after)
    (browse-kill-ring-insert
     emacsvox--advice-browse-kill-ring-insert-after)
    (browse-kill-ring-insert-and-quit
     emacsvox--advice-browse-kill-ring-insert-and-quit-after)
    (browse-kill-ring-delete
     emacsvox--advice-browse-kill-ring-delete-after)
    (browse-kill-ring-forward
     emacsvox--advice-browse-kill-ring-forward-after)
    (browse-kill-ring-previous
     emacsvox--advice-browse-kill-ring-previous-after)
    (browse-kill-ring-quit
     emacsvox--advice-browse-kill-ring-quit-after)
    (browse-kill-ring-edit
     emacsvox--advice-browse-kill-ring-edit-after)
    (browse-kill-ring-edit-finish
     emacsvox--advice-browse-kill-ring-edit-finish-after)
    (browse-kill-ring-occur
     emacsvox--advice-browse-kill-ring-occur-after)
    (browse-kill-ring-update
     emacsvox--advice-browse-kill-ring-update-after)
    (browse-kill-ring emacsvox--advice-browse-kill-ring-after)
    (browse-kill-ring-search-forward
     emacsvox--advice-browse-kill-ring-search-forward-after)
    (browse-kill-ring-search-backward
     emacsvox--advice-browse-kill-ring-search-backward-after))
  "Browse Kill Ring targets and their native advice functions.")

(defun emacsvox-browse-kill-ring--install-advice ()
  "Install Browse Kill Ring advice after the optional package loads."
  (dolist (entry emacsvox-browse-kill-ring--advice)
    (pcase-let ((`(,target ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'browse-kill-ring
  (emacsvox-browse-kill-ring--install-advice))

;;;  add keybinding on emacsvox desktop
(cl-eval-when (load)
  (define-key emacsvox-keymap "\C-k" 'browse-kill-ring))

(provide 'emacsvox-browse-kill-ring)
;;;  end of file
