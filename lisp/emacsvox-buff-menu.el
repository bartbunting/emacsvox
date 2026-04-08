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
;; Location https://github.com/tvraman/emacsvox
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

(defun ems--list-buffers-after (&rest _)
  "Select the window displaying buffer-menu,\nand set up additional Emacsvox bindings."
  
  (when (ems-interactive-p)
    (select-window ad-return-value) (tabulated-list-next-column 3)
    (define-key Buffer-menu-mode-map ","
                'emacsvox-list-buffers-speak-name)
    (define-key Buffer-menu-mode-map "l"
                'emacsvox-list-buffers-speak-buffer-line)
    (define-key Buffer-menu-mode-map "n"
                'emacsvox-list-buffers-next-line)
    (define-key Buffer-menu-mode-map "p"
                'emacsvox-list-buffers-previous-line)
    (emacsvox-list-buffers-speak-buffer-line)
    (emacsvox-icon 'open-object)))

(advice-add 'list-buffers :after #'ems--list-buffers-after)

(defun ems--buffer-menu-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (message "Displayed list of buffers in other window")))

(advice-add 'buffer-menu :after #'ems--buffer-menu-after)

;;;   buffer manipulation commands 

(defun ems--Buffer-menu-bury-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-bury :after #'ems--Buffer-menu-bury-after)

(defun ems--Buffer-menu-delete-backwards-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-delete-backwards :after
            #'ems--Buffer-menu-delete-backwards-after)

(defun ems--Buffer-menu-delete-after (&rest _)
  "Provide spoken and auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-delete :after #'ems--Buffer-menu-delete-after)

(defun ems--Buffer-menu-mark-after (&rest _)
  "Provide spoken and auditory feedback."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-mark :after #'ems--Buffer-menu-mark-after)

(defun ems--Buffer-menu-quit-after (&rest _)
  "Speak the modeline of the newly visible buffer."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'Buffer-menu-quit :after #'ems--Buffer-menu-quit-after)

(defun ems--Buffer-menu-save-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'save-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-save :after #'ems--Buffer-menu-save-after)

(defun ems--Buffer-menu-select-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'Buffer-menu-select :after #'ems--Buffer-menu-select-after)

(defun ems--Buffer-menu-unmark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-unmark :after #'ems--Buffer-menu-unmark-after)

(defun ems--Buffer-menu-backup-unmark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-backup-unmark :after
            #'ems--Buffer-menu-backup-unmark-after)

(defun ems--Buffer-menu-execute-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'Buffer-menu-execute :after
            #'ems--Buffer-menu-execute-after)

(defun ems--Buffer-menu-toggle-read-only-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-list-buffers-speak-buffer-line)))

(advice-add 'Buffer-menu-toggle-read-only :after
            #'ems--Buffer-menu-toggle-read-only-after)

(defun ems--Buffer-menu-not-modified-after (&rest _)
  "speak "
  (when (ems-interactive-p)
    (emacsvox-list-buffers-speak-buffer-line)
    (if (ad-get-arg 0) (emacsvox-icon 'modified-object)
      (emacsvox-icon 'unmodified-object))))

(advice-add 'Buffer-menu-not-modified :after
            #'ems--Buffer-menu-not-modified-after)

(defun ems--Buffer-menu-visit-tags-table-before (&rest _)
  "speak"
  (when (ems-interactive-p)
    (message "Visiting tags table on current line")))

(advice-add 'Buffer-menu-visit-tags-table :before
            #'ems--Buffer-menu-visit-tags-table-before)

;;;   display buffers 

(defun ems--Buffer-menu-1-window-after (&rest _)
  "Announce the newly selected buffer."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'select-object)))

(advice-add 'Buffer-menu-1-window :after
            #'ems--Buffer-menu-1-window-after)

(defun ems--Buffer-menu-2-window-after (&rest _)
  "Announce the newly selected buffer."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'select-object)))

(advice-add 'Buffer-menu-2-window :after
            #'ems--Buffer-menu-2-window-after)

(defun ems--Buffer-menu-this-window-after (&rest _)
  "Announce the newly selected buffer."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'select-object)))

(advice-add 'Buffer-menu-this-window :after
            #'ems--Buffer-menu-this-window-after)

(defun ems--Buffer-menu-other-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'Buffer-menu-other-window :after
            #'ems--Buffer-menu-other-window-after)

(provide 'emacsvox-buff-menu)
;;;  end of file 

