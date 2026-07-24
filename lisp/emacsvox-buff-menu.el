;;; emacsvox-buff-menu.el --- Speech enable buff -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to buff-menu
;; Keywords: Emacsvox, Speak, Spoken Output, buff-menu
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

;;;   Introduction 
;;; Commentary:
;; Speech-enable buffer-menus.
;;; Code:

;;   Required modules:

;;; Code:

(require 'emacsvox-preamble)

;;;  voice personalities
(voice-setup-add-map
 '(
   (buffer-menu-buffer voice-bolden)
   ))

;;;   list buffers 

(defun emacsvox-list-buffers-speak-name ()
  "Speak the name of the buffer on this line"
  (interactive)
  (cond
   ((eq major-mode 'Buffer-menu-mode)
    (let*((buffer (Buffer-menu-buffer t)))
      (if (get-buffer buffer)
          (dtk-speak (buffer-name  buffer))
        (error "No valid buffer on this line"))))
   (t (error "This command can be used only in buffer menus"))))

(defun emacsvox-list-buffers-speak-buffer-line ()
  "Speak information about this buffer"
  (interactive)
  
  (unless (eq major-mode 'Buffer-menu-mode)
    (error "This command can be used only in buffer menus"))
  (let((buffer (Buffer-menu-buffer t)))
    (cond
     ((get-buffer buffer)
      (when dtk-stop-immediately (dtk-stop))
      (let ((name (buffer-name buffer))
            (file (buffer-file-name buffer))
            this-buffer-read-only
            this-buffer-modified-p
            this-buffer-size
            this-buffer-mode-name
            this-buffer-directory
            (dtk-stop-immediately nil))
        (save-current-buffer
          (set-buffer buffer)
          (setq this-buffer-read-only buffer-read-only)
          (setq this-buffer-modified-p (buffer-modified-p))
          (setq this-buffer-size (buffer-size))
          (setq this-buffer-mode-name mode-name)
          (or file
              ;; No visited file.  Check local value of
              ;; list-buffers-directory.
              (if (and (boundp 'list-buffers-directory)
                       list-buffers-directory)
                  (setq this-buffer-directory list-buffers-directory))))
                                        ;format and speak the line
        (when this-buffer-modified-p (emacsvox-icon 'modified-object))
        (when this-buffer-read-only
          (emacsvox-icon 'unmodified-object))
        (dtk-speak
         (format  "%s a %s  buffer  %s with size  %s"
                  name this-buffer-mode-name
                  (if (or file this-buffer-directory)
                      (format "visiting %s"
                              (or file this-buffer-directory))
                    "")
                  this-buffer-size))))
     (t(emacsvox-icon 'warn-user)
       (emacsvox-speak-line)))))

(defun emacsvox-list-buffers-next-line (count)
  "Speech enabled buffer menu navigation"
  (interactive "p")
  (forward-line count)
  (emacsvox-list-buffers-speak-buffer-line))

(defun emacsvox-list-buffers-previous-line (count)
  "Speech enabled buffer menu navigation"
  (interactive "p")
  (forward-line  (* -1 count))
  (emacsvox-list-buffers-speak-buffer-line))

(defun emacsvox--advice-list-buffers-filter-return (window)
  "Select the window displaying buffer-menu,\nand set up additional Emacsvox bindings."
  
  (when (ems-interactive-p 'list-buffers)
    (select-window window)
    (tabulated-list-next-column 3)
    (define-key Buffer-menu-mode-map ","
                'emacsvox-list-buffers-speak-name)
    (define-key Buffer-menu-mode-map "l"
                'emacsvox-list-buffers-speak-buffer-line)
    (define-key Buffer-menu-mode-map "n"
                'emacsvox-list-buffers-next-line)
    (define-key Buffer-menu-mode-map "p"
                'emacsvox-list-buffers-previous-line)
    (emacsvox-list-buffers-speak-buffer-line)
    (emacsvox-icon 'open-object))
  window)

(advice-add
 'list-buffers :filter-return
 #'emacsvox--advice-list-buffers-filter-return
 '((name . emacsvox--advice-list-buffers-filter-return)))

(defmacro emacsvox-buff-menu--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive Buffer Menu TARGET."
  (declare (indent 2))
  (let ((function
         (intern (format "emacsvox--advice-%s-%s"
                         target
                         (substring (symbol-name where) 1)))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback %s `%s'." where target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target ,where #',function
        '((name . ,function))))))

(emacsvox-buff-menu--define-advice buffer-menu :after
  (emacsvox-icon 'task-done)
  (message "Displayed list of buffers in other window"))

;;;   buffer manipulation commands 

(dolist
    (spec
     '((Buffer-menu-bury select-object)
       (Buffer-menu-delete-backwards delete-object)
       (Buffer-menu-delete delete-object)
       (Buffer-menu-mark mark-object)
       (Buffer-menu-save save-object)
       (Buffer-menu-unmark deselect-object)
       (Buffer-menu-backup-unmark deselect-object)))
  (eval
   `(emacsvox-buff-menu--define-advice ,(car spec) :after
      (emacsvox-icon ',(cadr spec))
      (emacsvox-list-buffers-speak-buffer-line))))

(emacsvox-buff-menu--define-advice Buffer-menu-select :after
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(emacsvox-buff-menu--define-advice Buffer-menu-execute :after
  (emacsvox-icon 'task-done))

(emacsvox-buff-menu--define-advice Buffer-menu-toggle-read-only :after
  (emacsvox-list-buffers-speak-buffer-line))

(defun emacsvox--advice-Buffer-menu-not-modified-after
    (arg &rest _)
  "Report whether `Buffer-menu-not-modified' marked the buffer modified."
  (when (ems-interactive-p 'Buffer-menu-not-modified)
    (emacsvox-list-buffers-speak-buffer-line)
    (emacsvox-icon
     (if arg 'modified-object 'unmodified-object))))

(advice-add
 'Buffer-menu-not-modified :after
 #'emacsvox--advice-Buffer-menu-not-modified-after
 '((name . emacsvox--advice-Buffer-menu-not-modified-after)))

(emacsvox-buff-menu--define-advice Buffer-menu-visit-tags-table :before
  (message "Visiting tags table on current line"))

(defun emacsvox--advice-buffer-menu-quit-window-around
    (original &rest arguments)
  "Call ORIGINAL and report an interactive quit from Buffer Menu."
  (let ((buffer-menu-p (eq major-mode 'Buffer-menu-mode))
        (interactive-p (ems-interactive-p 'quit-window)))
    (let ((result (apply original arguments)))
      (when (and buffer-menu-p interactive-p)
        (emacsvox-icon 'close-object)
        (emacsvox-speak-mode-line))
      result)))

(advice-add
 'quit-window :around
 #'emacsvox--advice-buffer-menu-quit-window-around
 '((name . emacsvox-buffer-menu)))

;;;   display buffers 

(dolist
    (target
     '(Buffer-menu-1-window
       Buffer-menu-2-window
       Buffer-menu-this-window))
  (eval
   `(emacsvox-buff-menu--define-advice ,target :after
      (emacsvox-speak-mode-line)
      (emacsvox-icon 'select-object))))

(emacsvox-buff-menu--define-advice Buffer-menu-other-window :after
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(provide 'emacsvox-buff-menu)
;;;  end of file 
