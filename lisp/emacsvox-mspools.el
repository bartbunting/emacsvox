;;; emacsvox-mspools.el --- Speech enable MSpools -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to mail spool tracker
;; Keywords: Emacsvox, Speak, Spoken Output, mspools
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

;;;   Introduction
;;; Commentary:
;; Speech-enable  mspools --a package that lets you monitor
;; multiple maildrops
;;; Code:

;;;  advice

(defun ems--mspools-show-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'mspools-show :after #'ems--mspools-show-after)

(defun ems--mspools-quit-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'mspools-quit :after #'ems--mspools-quit-after)

(defun ems--mspools-revert-buffer-after (&rest _)
  "speak" (emacsvox-icon 'select-object) (emacsvox-speak-line))

(advice-add 'mspools-revert-buffer :after
            #'ems--mspools-revert-buffer-after)

;;; Smarter Spool-Size:
;; Smarter sppol-size compute functions.
;; These show the number of messages in a spool.

(defsubst mspools-compute-size (file)
  (read (shell-command-to-string (format "grep '^From ' %s | wc -l" file))))

(defun mspools-size-folder (spool)
  "Return (SPOOL . SIZE ) iff SIZE of spool file is non-zero."
  
  (let ((size (mspools-compute-size
               (expand-file-name  spool mspools-folder-directory))))
    (unless (zerop size) (cons spool size))))

;;;  keymaps
(cl-declaim (special mspools-mode-map))
(cl-eval-when (load)
  (require 'emacsvox-keymap)
  )

(provide 'emacsvox-mspools)

;;;  end of file 

