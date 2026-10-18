;;; emacsvox-tar.el --- Speech enable Tar Mode -*- lexical-binding: t; -*-

;; Copyright (c) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Speak, Spoken Output, tar
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
;; Auditory interface to tar mode
;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)
(require 'tar-mode)

;;;  Helpers

(defun emacsvox-tar-speak-line ()
  "Speak line in tar mode intelligently"
  (cond
   ((= (following-char) 0)
    (message "No file on this line"))
   (t (emacsvox-speak-line))))

;;;  Advice

(defun emacsvox--advice-tar-next-line-after (&rest _)
  "Speak."
  (when (ems-interactive-p 'tar-next-line)
    (emacsvox-tar-speak-line)))

(advice-add 'tar-next-line :after
            #'emacsvox--advice-tar-next-line-after)

(defun emacsvox--advice-tar-previous-line-after (&rest _)
  "Speak."
  (when (ems-interactive-p 'tar-previous-line)
    (emacsvox-tar-speak-line)))

(advice-add 'tar-previous-line :after
            #'emacsvox--advice-tar-previous-line-after)

(defun emacsvox--advice-tar-flag-deleted-after (&rest _)
  "speak"
  (when (ems-interactive-p 'tar-flag-deleted)
    (emacsvox-icon 'delete-object) (emacsvox-tar-speak-line)))

(advice-add 'tar-flag-deleted :after
            #'emacsvox--advice-tar-flag-deleted-after)

(defun emacsvox--advice-tar-unflag-after (&rest _)
  "speak"
  (when (ems-interactive-p 'tar-unflag)
    (emacsvox-icon 'yank-object) (emacsvox-tar-speak-line)))

(advice-add 'tar-unflag :after
            #'emacsvox--advice-tar-unflag-after)

(defun emacsvox--advice-tar-unflag-backwards-after (&rest _)
  "speak"
  (when (ems-interactive-p 'tar-unflag-backwards)
    (emacsvox-icon 'yank-object) (emacsvox-tar-speak-line)))

(advice-add 'tar-unflag-backwards :after
            #'emacsvox--advice-tar-unflag-backwards-after)

(defun emacsvox--advice-tar-extract-after (&rest _)
  "speak"
  (when (ems-interactive-p 'tar-extract)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'tar-extract :after
            #'emacsvox--advice-tar-extract-after)

(defun emacsvox--advice-tar-extract-other-window-after (&rest _)
  "speak"
  (when (ems-interactive-p 'tar-extract-other-window)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'tar-extract-other-window :after
            #'emacsvox--advice-tar-extract-other-window-after)

(defun emacsvox--advice-tar-view-after (&rest _)
  "speak"
  (when (ems-interactive-p 'tar-view)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'tar-view :after
            #'emacsvox--advice-tar-view-after)

;;;  additional interactive commands

(defsubst ems--tar-mode-to-string (mode)
  "Convert mode to speakable string."
  (format
   "%c%c%c%c%c%c%c%c%c"
   (if (zerop (logand 256 mode)) ?- ?r)
   (if (zerop (logand 128 mode)) ?- ?w)
   (if (zerop (logand  64 mode)) ?- ?x)
   (if (zerop (logand  32 mode)) ?- ?r)
   (if (zerop (logand  16 mode)) ?- ?w)
   (if (zerop (logand   8 mode)) ?- ?x)
   (if (zerop (logand   4 mode)) ?- ?r)
   (if (zerop (logand   2 mode)) ?- ?w)
   (if (zerop (logand   1 mode)) ?- ?x)))

(defun emacsvox-tar-speak-file-permissions()
  "Speak permissions of file current entry "
  (interactive)
  (unless (eq major-mode 'tar-mode)
    (error "This command should be called only in tar mode"))
  (let ((entry (tar-current-descriptor))
        (mode nil)
        (string nil))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t
      (setq mode
            (tar-header-mode  entry))
      (setq string (ems--tar-mode-to-string mode))
      (if (zerop (logand 1024 mode)) nil (aset string  2 ?s))
      (if (zerop (logand 2048 mode)) nil (aset string  5 ?s))
      (message  "Permissions  %s "
                string)))))

(defun emacsvox-tar-speak-file-size()
  "Speak size of file current entry "
  (interactive)
  (unless (eq major-mode 'tar-mode)
    (error "This command should be called only in tar mode"))
  (let ((entry (tar-current-descriptor)))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t (message  "File size %s "
                  (tar-header-size entry))))))

(defun emacsvox-tar-speak-file-date()
  "Speak date of file current entry "
  (interactive)
  
  (unless (eq major-mode 'tar-mode)
    (error "This command should be called only in tar mode"))
  (let ((entry (tar-current-descriptor)))
    (cond
     ((null entry)
      (message "No file on this line"))
     (t (message  "Modified on  %s "
                  (format-time-string
                   emacsvox-speak-time-format
                   (tar-header-date entry)))))))

(defun emacsvox-tar-setup-keys ()
  "Setup emacsvox keys for tar mode"
  
  (define-key tar-mode-map "z" 'emacsvox-tar-speak-file-size)
  (define-key tar-mode-map "/" 'emacsvox-tar-speak-file-permissions)
  (define-key tar-mode-map "c" 'emacsvox-tar-speak-file-date)
  )

(cl-eval-when (load)
  (emacsvox-tar-setup-keys))

(provide 'emacsvox-tar)

;;; emacsvox-tar.el ends here
