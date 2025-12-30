;;; emacspeak-bookmark.el --- Speech enable bookmark -*- lexical-binding: t -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to bookmark
;; Keywords: Emacspeak, Speak, Spoken Output, bookmark
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacspeak
;; 

;;;   Copyright:

;; Copyright (c) 1995 -- 2024, T. V. Raman
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

;;   Required modules:

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;;   Introduction 
;;; Commentary:
;; Speech enable bookmarks
;;; Code:

;;;   bookmarks

(defun ems--bookmark-set-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (emacspeak-icon 'mark-object) (message "Set bookmark ")))


(advice-add 'bookmark-set :after #'ems--bookmark-set-after)





(defun ems--bookmark-yank-word-after (&rest _)
  "Speak what has been yanked so far"
  (when (ems-interactive-p)
    (emacspeak-icon 'yank-object) (emacspeak-speak-line)))


(advice-add 'bookmark-yank-word :after #'ems--bookmark-yank-word-after)





(defun ems--bookmark-insert-current-bookmark-after (&rest _)
  "Speak what has been yanked so far"
  (when (ems-interactive-p)
    (emacspeak-icon 'yank-object) (emacspeak-speak-line)))


(advice-add 'bookmark-insert-current-bookmark :after
	    #'ems--bookmark-insert-current-bookmark-after)





(defun ems--bookmark-insert-current-file-name-after (&rest _)
  "Speak what has been yanked so far"
  (when (ems-interactive-p)
    (emacspeak-icon 'yank-object) (emacspeak-speak-line)))


(advice-add 'bookmark-insert-current-file-name :after
	    #'ems--bookmark-insert-current-file-name-after)





(defun ems--bookmark-jump-after (&rest _)
  "Announce what happened."
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement) (emacspeak-speak-line)))


(advice-add 'bookmark-jump :after #'ems--bookmark-jump-after)





(defun ems--bookmark-bmenu-list-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (switch-to-buffer "*Bookmark List*")
    (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-list :after
	    #'ems--bookmark-bmenu-list-after)





(defun ems--bookmark-bmenu-this-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-speak-line) (emacspeak-icon 'open-object)))


(advice-add 'bookmark-bmenu-this-window :after
	    #'ems--bookmark-bmenu-this-window-after)




(defun ems--bookmark-bmenu-select-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-select :after
	    #'ems--bookmark-bmenu-select-after)




(defun ems--bookmark-bmenu-delete-backwards-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'delete-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-delete-backwards :after
	    #'ems--bookmark-bmenu-delete-backwards-after)





(defun ems--bookmark-bmenu-1-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-1-window :after
	    #'ems--bookmark-bmenu-1-window-after)





(defun ems--bookmark-bmenu-2-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-2-window :after
	    #'ems--bookmark-bmenu-2-window-after)





(defun ems--bookmark-bmenu-switch-other-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-switch-other-window :after
	    #'ems--bookmark-bmenu-switch-other-window-after)





(defun ems--bookmark-bmenu-edit-annotation-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-mode-line)))


(advice-add 'bookmark-bmenu-edit-annotation :after
	    #'ems--bookmark-bmenu-edit-annotation-after)





(defun ems--bookmark-bmenu-delete-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'delete-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-delete :after
	    #'ems--bookmark-bmenu-delete-after)





(defun ems--bookmark-bmenu-unmark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'deselect-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-unmark :after
	    #'ems--bookmark-bmenu-unmark-after)





(defun ems--bookmark-bmenu-edit-annotation-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-mode-line)))


(advice-add 'bookmark-bmenu-edit-annotation :after
	    #'ems--bookmark-bmenu-edit-annotation-after)




(defun ems--bookmark-send-edited-annotation-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'task-done) (emacspeak-speak-line)))


(advice-add 'bookmark-send-edited-annotation :after
	    #'ems--bookmark-send-edited-annotation-after)





(defun ems--bookmark-bmenu-show-annotation-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-other-window)))


(advice-add 'bookmark-bmenu-show-annotation :after
	    #'ems--bookmark-bmenu-show-annotation-after)





(defun ems--bookmark-bmenu-show-all-annotations-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object)
    (message "Displayed all annotations in other window")))


(advice-add 'bookmark-bmenu-show-all-annotations :after
	    #'ems--bookmark-bmenu-show-all-annotations-after)





(defun ems--bookmark-bmenu-mark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'mark-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-mark :after
	    #'ems--bookmark-bmenu-mark-after)





(defun ems--bookmark-bmenu-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (emacspeak-speak-mode-line)))


(advice-add 'bookmark-bmenu-quit :after
	    #'ems--bookmark-bmenu-quit-after)





(defun ems--bookmark-bmenu-backup-unmark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'deselect-object) (emacspeak-speak-line)))


(advice-add 'bookmark-bmenu-backup-unmark :after
	    #'ems--bookmark-bmenu-backup-unmark-after)




(provide 'emacspeak-bookmark)
;;;  end of file 

