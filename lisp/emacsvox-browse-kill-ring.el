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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  speech-enable interactive commands

(defun ems--browse-kill-ring-undo-other-window-after (&rest _)
  "speak."
  (when (ems-interactive-p) (emacsvox-icon 'unmodified-object)))

(advice-add 'browse-kill-ring-undo-other-window :after
            #'ems--browse-kill-ring-undo-other-window-after)

(defun ems--browse-kill-ring-insert-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'yank-object)))

(advice-add 'browse-kill-ring-insert :after
            #'ems--browse-kill-ring-insert-after)

(defun ems--browse-kill-ring-insert-and-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-line)
    (emacsvox-icon 'close-object)))

(advice-add 'browse-kill-ring-insert-and-quit :after
            #'ems--browse-kill-ring-insert-and-quit-after)

(defun ems--browse-kill-ring-delete-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'delete-object)))

(advice-add 'browse-kill-ring-delete :after
            #'ems--browse-kill-ring-delete-after)

(defun ems--browse-kill-ring-forward-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'browse-kill-ring-forward :after
            #'ems--browse-kill-ring-forward-after)

(defun ems--browse-kill-ring-previous-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'browse-kill-ring-previous :after
            #'ems--browse-kill-ring-previous-after)

(defun ems--browse-kill-ring-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'browse-kill-ring-quit :after
            #'ems--browse-kill-ring-quit-after)

(defun ems--browse-kill-ring-edit-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'open-object)))

(advice-add 'browse-kill-ring-edit :after
            #'ems--browse-kill-ring-edit-after)

(defun ems--browse-kill-ring-edit-finish-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))

(advice-add 'browse-kill-ring-edit-finish :after
            #'ems--browse-kill-ring-edit-finish-after)

(defun ems--browse-kill-ring-occur-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'open-object)))

(advice-add 'browse-kill-ring-occur :after
            #'ems--browse-kill-ring-occur-after)

(defun ems--browse-kill-ring-update-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'browse-kill-ring-update :after
            #'ems--browse-kill-ring-update-after)

(defun ems--browse-kill-ring-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'browse-kill-ring :after #'ems--browse-kill-ring-after)

;;;  add keybinding on emacsvox desktop
(cl-eval-when (load)
  (define-key emacsvox-keymap "\C-k" 'browse-kill-ring))

(provide 'emacsvox-browse-kill-ring)
;;;  end of file

(defun ems--browse-kill-ring-search-forward-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'browse-kill-ring-search-forward :after
            #'ems--browse-kill-ring-search-forward-after)

(defun ems--browse-kill-ring-search-backward-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'browse-kill-ring-search-backward :after
            #'ems--browse-kill-ring-search-backward-after)

