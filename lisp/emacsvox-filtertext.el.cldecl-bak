;;; emacsvox-filtertext.el --- filter text  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   Implement text filters 
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;; Commentary:
;; It is often useful  to view the results of filtering
;; large amounts of text.;;; Typically you do this with
;; various combinations of grep and friends.
;; When doing so it requires explicit effort to not destroy
;; the original text being filtered.
;; This module provides a textfilter utility that:
;; A) Copies over the selected text to a special filtertext
;; buffer
;; B) Implements a filtertext mode for that buffer that
;; allows easy application of filters
;; C: Provides commands for reverting to the original
;; unfiltered text
;; D: Provides commands for saving results from
;; intermediate filters.
;;; Code:

;;;   structures 

(cl-defstruct (emacsvox-filtertext
               (:constructor
                emacsvox-filtertext-constructor))
  text                                  ;original text
  filters                               ;chain of filters applied 
  )

;;;  filtertext  mode 

(defvar emacsvox-filtertext-info  nil
  "Holds filtertext info structure.")
(make-variable-buffer-local 'emacsvox-filtertext-info)

(define-derived-mode emacsvox-filtertext-mode text-mode 
  "FilterText mode"
  "Major mode for FilterText interaction. \n\n
\\{emacsvox-filtertext-mode-map}")
(cl-declare (special emacsvox-filtertext-mode-map))
(define-key emacsvox-filtertext-mode-map "=" 'keep-lines)
(define-key emacsvox-filtertext-mode-map "^" 'flush-lines)
(define-key emacsvox-filtertext-mode-map "r"
            'emacsvox-filtertext-revert)

;;;  Interactive commands 
;;;###autoload
(defun emacsvox-filtertext(start end)
  "Copy over text in region to special filtertext buffer to  filter text. "
  (interactive "r")
  (cl-declare (special emacsvox-filtertext-info
                       case-fold-search))
  (let ((this (buffer-substring-no-properties start end))
        (buffer (get-buffer-create
                 (format "filter-%s" (buffer-name)))))
    (save-current-buffer
      (set-buffer buffer)
      (setq case-fold-search t)
      (erase-buffer)
      (make-local-variable 'emacsvox-filtertext-info)
      (insert this)
      (emacsvox-filtertext-mode)
      (setq emacsvox-filtertext-info
            (emacsvox-filtertext-constructor :text this))
      (goto-char (point-min)))
    (switch-to-buffer buffer)
    (emacsvox-speak-mode-line)))

(defun emacsvox-filtertext-revert ()
  "Revert to original text."
  (interactive)
  (cl-declare (special emacsvox-filtertext-info))
  (unless (eq  major-mode 'emacsvox-filtertext-mode)
    (error "Not in filter text mode."))
  (when emacsvox-filtertext-info
    (erase-buffer)
    (insert (emacsvox-filtertext-text emacsvox-filtertext-info))
    (emacsvox-icon 'unmodified-object)
    (message "Reverted filtered text.")))

(provide 'emacsvox-filtertext)
;;;  end of file

