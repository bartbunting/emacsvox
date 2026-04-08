;;; emacsvox-bs.el --- speech-enable bs -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable bs
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

(require 'emacsvox-preamble)
(require 'bs)

;;; Commentary:

;; speech-enable bs.el -- an alternative to Emacs' default  list-buffers

;;; Code:

;;;  helpers 

(defun emacsvox-bs-speak-buffer-line ()
  "Speak information about this buffer"
  (interactive)
  
  (unless (eq major-mode 'bs-mode)
    (error "This command can only be used in buffer menus"))
  (let((buffer (bs--current-buffer)))
    (cond
     ((get-buffer buffer)
      (let (
            (with (propertize "with size " 'personality voice-smoothen))
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
                                        ;format and speak the line
        (when this-buffer-modified-p (dtk-tone 700 100))
        (when this-buffer-read-only (dtk-tone 250 100))
        (dtk-speak
         (concat 
          name " "
          (format-mode-line mode-name)
          (if (or file this-buffer-directory)
              (format " visiting %s "
                      (or file this-buffer-directory))
            "")
          with
          (format " %s "this-buffer-size)))))
     (t(emacsvox-icon 'warn-user)
       (emacsvox-speak-line)))))

;;;  speech enable interactive commands 

(defun ems--bs-mode-after (&rest _)
  "Speech-enable bs mode" (setq voice-lock-mode t))

(advice-add 'bs-mode :after #'ems--bs-mode-after)

(defun ems--bs-kill-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-kill :after #'ems--bs-kill-after)

(defun ems--bs-abort-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-abort :after #'ems--bs-abort-after)

(defun ems--bs-set-configuration-and-refresh-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p) (emacsvox-icon 'select-object)))

(advice-add 'bs-set-configuration-and-refresh :after
            #'ems--bs-set-configuration-and-refresh-after)

(defun ems--bs-refresh-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p) (emacsvox-icon 'select-object)))

(advice-add 'bs-refresh :after #'ems--bs-refresh-after)

(defun ems--bs-view-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-view :after #'ems--bs-view-after)

(defun ems--bs-select-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select :after #'ems--bs-select-after)

(defun ems--bs-select-other-window-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select-other-window :after
            #'ems--bs-select-other-window-after)

(defun ems--bs-tmp-select-other-window-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-tmp-select-other-window :after
            #'ems--bs-tmp-select-other-window-after)

(defun ems--bs-select-other-frame-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select-other-frame :after
            #'ems--bs-select-other-frame-after)

(defun ems--bs-select-in-one-window-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select-in-one-window :after
            #'ems--bs-select-in-one-window-after)

(defun ems--bs-bury-buffer-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p) (emacsvox-icon 'close-object)))

(advice-add 'bs-bury-buffer :after #'ems--bs-bury-buffer-after)

(defun ems--bs-save-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p) (emacsvox-icon 'save-object)))

(advice-add 'bs-save :after #'ems--bs-save-after)

(defun ems--bs-toggle-current-to-show-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-toggle-current-to-show :after
            #'ems--bs-toggle-current-to-show-after)

(defun ems--bs-set-current-buffer-to-show-never-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-set-current-buffer-to-show-never :after
            #'ems--bs-set-current-buffer-to-show-never-after)

(defun ems--bs-mark-current-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-mark-current :after #'ems--bs-mark-current-after)

(defun ems--bs-unmark-current-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-unmark-current :after #'ems--bs-unmark-current-after)

(defun ems--bs-delete-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-delete :after #'ems--bs-delete-after)

(defun ems--bs-delete-backward-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-delete-backward :after #'ems--bs-delete-backward-after)

(defun ems--bs-up-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-up :after #'ems--bs-up-after)

(defun ems--bs-down-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-down :after #'ems--bs-down-after)

(defun ems--bs-cycle-next-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (let ((emacsvox-speak-messages nil))
      (emacsvox-icon 'select-object) (emacsvox-speak-mode-line))))

(advice-add 'bs-cycle-next :after #'ems--bs-cycle-next-after)

(defun ems--bs-cycle-previous-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p)
    (let ((emacsvox-speak-messages nil))
      (emacsvox-icon 'select-object) (emacsvox-speak-mode-line))))

(advice-add 'bs-cycle-previous :after #'ems--bs-cycle-previous-after)

(provide 'emacsvox-bs)
;;;  end of file

