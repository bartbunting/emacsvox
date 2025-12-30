;;; emacsvox-tar.el --- Speech enable Tar Mode -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: Auditory interface to tar mode
;; Keywords: Emacsvox, Speak, Spoken Output, tar
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
(require 'tar-mode)

;;;   Introduction
;;; Commentary:
;; Auditory interface to tar mode
;;; Code:

;;;  Helpers

(defun emacsvox-tar-speak-line ()
  "Speak line in tar mode intelligently"
  (cond
   ((= (following-char) 0)
    (message "No file on this line"))
   (t (emacsvox-speak-line))))

;;;  Advice

(defun ems--tar-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))


(advice-add 'tar-quit :after #'ems--tar-quit-after)





(defun ems--tar-next-line-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-tar-speak-line)))


(advice-add 'tar-next-line :after #'ems--tar-next-line-after)





(defun ems--tar-previous-line-after (&rest _)
  "Speak" (when (ems-interactive-p) (emacsvox-tar-speak-line)))


(advice-add 'tar-previous-line :after #'ems--tar-previous-line-after)





(defun ems--tar-flag-deleted-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-tar-speak-line)))


(advice-add 'tar-flag-deleted :after #'ems--tar-flag-deleted-after)





(defun ems--tar-unflag-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-tar-speak-line)))


(advice-add 'tar-unflag :after #'ems--tar-unflag-after)




(defun ems--tar-unflag-backwards-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-tar-speak-line)))


(advice-add 'tar-unflag-backwards :after
	    #'ems--tar-unflag-backwards-after)





(defun ems--tar-extract-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))


(advice-add 'tar-extract :after #'ems--tar-extract-after)





(defun ems--tar-extract-other-window-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))


(advice-add 'tar-extract-other-window :after
	    #'ems--tar-extract-other-window-after)





(defun ems--tar-view-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))


(advice-add 'tar-view :after #'ems--tar-view-after)




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
  (cl-declare (special emacsvox-speak-time-format))
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
  (cl-declare (special tar-mode-map))
  (define-key tar-mode-map "z" 'emacsvox-tar-speak-file-size)
  (define-key tar-mode-map "/" 'emacsvox-tar-speak-file-permissions)
  (define-key tar-mode-map "c" 'emacsvox-tar-speak-file-date)
  )

(cl-eval-when (load)
  (emacsvox-tar-setup-keys))

(provide 'emacsvox-tar)
;;;  end of file

