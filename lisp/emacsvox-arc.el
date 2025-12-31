;;; emacsvox-arc.el --- Speech enable archive-mode -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to archive mode
;; Keywords: Emacsvox, Speak, Spoken Output, archive
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

;;   Required modules:
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'arc-mode)

;;;   Introduction 
;;; Commentary:
;; Auditory interface to archive mode
;; This lets Emacs manipulate package files such as .zip and .jar files.
;;; Code:

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

(defun ems--archive-mark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-mark :after #'ems--archive-mark-after)

(defun ems--archive-next-line-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-archive-speak-line)))

(advice-add 'archive-next-line :after #'ems--archive-next-line-after)

(defun ems--archive-previous-line-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-archive-speak-line)))

(advice-add 'archive-previous-line :after
            #'ems--archive-previous-line-after)

(defun ems--archive-flag-deleted-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-flag-deleted :after
            #'ems--archive-flag-deleted-after)

(defun ems--archive-unflag-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-unflag :after #'ems--archive-unflag-after)

(defun ems--archive-unflag-backwards-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-archive-speak-line)))

(advice-add 'archive-unflag-backwards :after
            #'ems--archive-unflag-backwards-after)

(defun ems--archive-extract-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'archive-extract :after #'ems--archive-extract-after)

(defun ems--archive-extract-other-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'archive-extract-other-window :after
            #'ems--archive-extract-other-window-after)

(defun ems--archive-view-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'archive-view :after #'ems--archive-view-after)

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
;;;  end of file 

