;;; emacsvox-bookmark.el --- Speech enable bookmark -*- lexical-binding: t -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to bookmark
;; Keywords: Emacsvox, Speak, Spoken Output, bookmark
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/robertmeta/emacsvox
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

(require 'emacsvox-preamble)

;;;   Introduction 
;;; Commentary:
;; Speech enable bookmarks
;;; Code:

(require 'bookmark)

(defmacro emacsvox-bookmark--define-after-advice (target &rest body)
  "Define direct after advice for interactive Bookmark TARGET using BODY."
  (declare (indent 1))
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback after `%s'." target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target :after #',function '((name . emacsvox))))))

;;;   bookmarks

(emacsvox-bookmark--define-after-advice bookmark-set
  (emacsvox-icon 'mark-object)
  (message "Set bookmark "))

(emacsvox-bookmark--define-after-advice bookmark-yank-word
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

(emacsvox-bookmark--define-after-advice bookmark-jump
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-bookmark--define-after-advice bookmark-bmenu-list
  (emacsvox-icon 'open-object)
  (switch-to-buffer "*Bookmark List*")
  (emacsvox-speak-line))

(emacsvox-bookmark--define-after-advice bookmark-bmenu-this-window
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(dolist
    (target
     '(bookmark-bmenu-select
       bookmark-bmenu-1-window
       bookmark-bmenu-2-window
       bookmark-bmenu-switch-other-window))
  (eval
   `(emacsvox-bookmark--define-after-advice ,target
      (emacsvox-icon 'open-object)
      (emacsvox-speak-line))))

(emacsvox-bookmark--define-after-advice bookmark-bmenu-edit-annotation
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(dolist
    (target
     '(bookmark-bmenu-delete
       bookmark-bmenu-delete-backwards))
  (eval
   `(emacsvox-bookmark--define-after-advice ,target
      (emacsvox-icon 'delete-object)
      (emacsvox-speak-line))))

(dolist
    (target
     '(bookmark-bmenu-unmark
       bookmark-bmenu-backup-unmark))
  (eval
   `(emacsvox-bookmark--define-after-advice ,target
      (emacsvox-icon 'deselect-object)
      (emacsvox-speak-line))))

(emacsvox-bookmark--define-after-advice bookmark-edit-annotation-confirm
  (emacsvox-icon 'task-done)
  (emacsvox-speak-line))

(emacsvox-bookmark--define-after-advice bookmark-bmenu-show-annotation
  (emacsvox-icon 'open-object)
  (emacsvox-speak-other-window))

(emacsvox-bookmark--define-after-advice bookmark-bmenu-show-all-annotations
  (emacsvox-icon 'open-object)
  (message "Displayed all annotations in other window"))

(emacsvox-bookmark--define-after-advice bookmark-bmenu-mark
  (emacsvox-icon 'mark-object)
  (emacsvox-speak-line))

(provide 'emacsvox-bookmark)
;;;  end of file 
