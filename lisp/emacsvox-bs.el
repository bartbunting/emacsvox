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
        (when this-buffer-modified-p (tts-tone 700 100))
        (when this-buffer-read-only (tts-tone 250 100))
        (tts-speak
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

(defun emacsvox--advice-bs-mode-after (&rest _)
  "Speech-enable bs mode" (setq voice-lock-mode t))

(advice-add 'bs-mode :after #'emacsvox--advice-bs-mode-after)

(defun emacsvox--advice-bs-kill-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-kill)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-kill :after #'emacsvox--advice-bs-kill-after)

(defun emacsvox--advice-bs-abort-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-abort)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-abort :after #'emacsvox--advice-bs-abort-after)

(defun emacsvox--advice-bs-set-configuration-and-refresh-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-set-configuration-and-refresh) (emacsvox-icon 'select-object)))

(advice-add 'bs-set-configuration-and-refresh :after
            #'emacsvox--advice-bs-set-configuration-and-refresh-after)

(defun emacsvox--advice-bs-refresh-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-refresh) (emacsvox-icon 'select-object)))

(advice-add 'bs-refresh :after #'emacsvox--advice-bs-refresh-after)

(defun emacsvox--advice-bs-view-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-view)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-view :after #'emacsvox--advice-bs-view-after)

(defun emacsvox--advice-bs-select-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-select)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select :after #'emacsvox--advice-bs-select-after)

(defun emacsvox--advice-bs-select-other-window-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-select-other-window)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select-other-window :after
            #'emacsvox--advice-bs-select-other-window-after)

(defun emacsvox--advice-bs-tmp-select-other-window-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-tmp-select-other-window)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-tmp-select-other-window :after
            #'emacsvox--advice-bs-tmp-select-other-window-after)

(defun emacsvox--advice-bs-select-other-frame-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-select-other-frame)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select-other-frame :after
            #'emacsvox--advice-bs-select-other-frame-after)

(defun emacsvox--advice-bs-select-in-one-window-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-select-in-one-window)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'bs-select-in-one-window :after
            #'emacsvox--advice-bs-select-in-one-window-after)

(defun emacsvox--advice-bs-bury-buffer-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-bury-buffer) (emacsvox-icon 'close-object)))

(advice-add 'bs-bury-buffer :after #'emacsvox--advice-bs-bury-buffer-after)

(defun emacsvox--advice-bs-save-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-save) (emacsvox-icon 'save-object)))

(advice-add 'bs-save :after #'emacsvox--advice-bs-save-after)

(defun emacsvox--advice-bs-toggle-current-to-show-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-toggle-current-to-show)
    (emacsvox-icon 'button) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-toggle-current-to-show :after
            #'emacsvox--advice-bs-toggle-current-to-show-after)

(defun emacsvox--advice-bs-set-current-buffer-to-show-never-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-set-current-buffer-to-show-never)
    (emacsvox-icon 'button) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-set-current-buffer-to-show-never :after
            #'emacsvox--advice-bs-set-current-buffer-to-show-never-after)

(defun emacsvox--advice-bs-mark-current-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-mark-current)
    (emacsvox-icon 'mark-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-mark-current :after #'emacsvox--advice-bs-mark-current-after)

(defun emacsvox--advice-bs-unmark-current-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-unmark-current)
    (emacsvox-icon 'deselect-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-unmark-current :after #'emacsvox--advice-bs-unmark-current-after)

(defun emacsvox--advice-bs-delete-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-delete)
    (emacsvox-icon 'delete-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-delete :after #'emacsvox--advice-bs-delete-after)

(defun emacsvox--advice-bs-delete-backward-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-delete-backward)
    (emacsvox-icon 'delete-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-delete-backward :after #'emacsvox--advice-bs-delete-backward-after)

(defun emacsvox--advice-bs-up-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-up)
    (emacsvox-icon 'select-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-up :after #'emacsvox--advice-bs-up-after)

(defun emacsvox--advice-bs-down-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-down)
    (emacsvox-icon 'select-object) (emacsvox-bs-speak-buffer-line)))

(advice-add 'bs-down :after #'emacsvox--advice-bs-down-after)

(defun emacsvox--advice-bs-cycle-next-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-cycle-next)
    (let ((emacsvox-speak-messages nil))
      (emacsvox-icon 'select-object) (emacsvox-speak-mode-line))))

(advice-add 'bs-cycle-next :after #'emacsvox--advice-bs-cycle-next-after)

(defun emacsvox--advice-bs-cycle-previous-after (&rest _)
  "Speech-enable bs mode"
  (when (ems-interactive-p 'bs-cycle-previous)
    (let ((emacsvox-speak-messages nil))
      (emacsvox-icon 'select-object) (emacsvox-speak-mode-line))))

(advice-add 'bs-cycle-previous :after #'emacsvox--advice-bs-cycle-previous-after)

(provide 'emacsvox-bs)
;;;  end of file

