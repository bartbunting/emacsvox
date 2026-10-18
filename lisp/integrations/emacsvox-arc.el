;;; emacsvox-arc.el --- Speech enable archive-mode -*- lexical-binding: t; -*-

;; Copyright (c) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Speak, Spoken Output, archive
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Auditory interface to archive mode
;; This lets Emacs manipulate package files such as .zip and .jar files.
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'arc-mode)

;;;  Helpers

(defun emacsvox-archive-speak-line ()
  "Speak line in archive mode intelligently"
  (end-of-line)
  (cond
   ((null (char-after (1+ (point))))
    (emacsvox-speak-line))
   (t (skip-syntax-backward "^ ")  
      (emacsvox-speak-line 1))))

;;;  fix interactive commands that need fixing 

;;;  Advice

(defun emacsvox--advice-archive-mark-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-mark)
    (emacsvox-icon 'mark-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-mark :after
            #'emacsvox--advice-archive-mark-after)

(defun emacsvox--advice-archive-next-line-after (&rest _)
  "Speak"
  (when (ems-interactive-p 'archive-next-line)
    (emacsvox-archive-speak-line)))

(advice-add 'archive-next-line :after
            #'emacsvox--advice-archive-next-line-after)

(defun emacsvox--advice-archive-previous-line-after (&rest _)
  "Speak"
  (when (ems-interactive-p 'archive-previous-line)
    (emacsvox-archive-speak-line)))

(advice-add 'archive-previous-line :after
            #'emacsvox--advice-archive-previous-line-after)

(defun emacsvox--advice-archive-flag-deleted-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-flag-deleted)
    (emacsvox-icon 'delete-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-flag-deleted :after
            #'emacsvox--advice-archive-flag-deleted-after)

(defun emacsvox--advice-archive-unflag-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-unflag)
    (emacsvox-icon 'yank-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-unflag :after
            #'emacsvox--advice-archive-unflag-after)

(defun emacsvox--advice-archive-unflag-backwards-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-unflag-backwards)
    (emacsvox-icon 'yank-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-unflag-backwards :after
            #'emacsvox--advice-archive-unflag-backwards-after)

(defun emacsvox--advice-archive-extract-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-extract)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'archive-extract :after
            #'emacsvox--advice-archive-extract-after)

(defun emacsvox--advice-archive-extract-other-window-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-extract-other-window)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'archive-extract-other-window :after
            #'emacsvox--advice-archive-extract-other-window-after)

(defun emacsvox--advice-archive-view-after (&rest _)
  "speak"
  (when (ems-interactive-p 'archive-view)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'archive-view :after
            #'emacsvox--advice-archive-view-after)

;;;  interactive commands

(defvar emacsvox-arc-header-list-format nil
  "Field names in the header line")

(defun emacsvox-arc-get-header-line-format ()
  "Return  header line format vector, after
first initializing it if necessary."
  
  (unless emacsvox-arc-header-list-format
    (let ((line nil)
          (fields nil))
      (save-excursion
        (goto-char (point-min))
        (setq line (ems--this-line)))
      (setq fields (split-string line))
      (cl-loop for f in fields 
               and i from 0
               do
               (setq emacsvox-arc-header-list-format
                     (cons
                      (list f i)
                      emacsvox-arc-header-list-format)))))
  emacsvox-arc-header-list-format)
(defun emacsvox-arc-get-field-index (field)
  (let ((marked-p
         (save-excursion
           (beginning-of-line)
           (= ?\  (following-char))))
        (pos (cadr (assoc field (emacsvox-arc-get-header-line-format)))))
    (if marked-p (1- pos) pos)))

(defun emacsvox-arc-speak-file-name ()
  "Speak the name of the file on current line"
  (interactive)
  (unless (eq major-mode 'archive-mode)
    (error "This command should be called only in archive mode"))
  (let ((entry (archive-get-descr 'no-error)))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t
      (message "File: %s"
               (nth  (emacsvox-arc-get-field-index "File")
                     (split-string (ems--this-line))))))))

(defun emacsvox-arc-speak-file-size ()
  "Speak the size of the file on current line"
  (interactive)
  (unless (eq major-mode 'archive-mode)
    (error "This command should be called only in archive mode"))
  (let ((entry (archive-get-descr 'no-error)))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t
      (message "Size: %s"
               (nth  (emacsvox-arc-get-field-index "Length")
                     (split-string (ems--this-line))))))))

(defun emacsvox-arc-speak-file-modification-time ()
  "Speak modification time of the file on current line"
  (interactive)
  (unless (eq major-mode 'archive-mode)
    (error "This command should be called only in archive mode"))
  (let ((entry (archive-get-descr 'no-error)))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t
      (let* ((fields (split-string (ems--this-line)))
             (date (nth  (emacsvox-arc-get-field-index "Date")
                         fields))
             (time (nth  (emacsvox-arc-get-field-index "Time")
                         fields)))
        (message "Modified on %s at %s"
                 date time))))))

(defun emacsvox-arc-speak-file-permissions()
  "Speak permissions of file current entry "
  (interactive)
  (unless (eq major-mode 'archive-mode)
    (error "This command should be called only in archive mode"))
  (let ((entry (archive-get-descr 'no-error))
        (mode nil))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t
      (setq mode
            (file-modes-number-to-symbolic
             (aref entry 3)))
      (message  "Permissions  %s "
                mode)))))
(defun emacsvox-arc-setup-keys ()
  "Setup emacsvox keys for arc mode"
  
  (define-key archive-mode-map "." 'emacsvox-arc-speak-file-name)
  (define-key archive-mode-map "c" 'emacsvox-arc-speak-file-modification-time)
  (define-key archive-mode-map "z" 'emacsvox-arc-speak-file-size)
  (define-key archive-mode-map "/"
              'emacsvox-arc-speak-file-permissions)
  )

(cl-eval-when (load)
  (emacsvox-arc-setup-keys))

(provide 'emacsvox-arc)

;;; emacsvox-arc.el ends here
