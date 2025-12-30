;;; emacsvox-gridtext.el --- Filter columnar text  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox module for laying grids on text
;; Keywords: Emacsvox, gridtext
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4150 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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


;;; Commentary:

;; Emacsvox's table browsing mode allows one to
;; efficiently access  content that is tabular in nature.
;; That module also provides functions for inferring table
;; structure where possible.
;; Often, such structure is hard to infer automatically
;; --but might be known to the user 
;; e.g. treat columns 1 through 30 as one column of a table
;; and so on.
;; This module allows the user to specify a conceptual grid
;; that is "overlaid" on the region of text to turn it into
;; a table for tabular browsing. For now, elements of the
;; grid are "one line" high --but that may change in the
;; future if necessary. This module is useful for browsing
;; structured text files and the output from programs that
;; tabulate their output.
;; It's also useful for handling multicolumn text.
;; The "grid" is specified as a list of (start end) tuples..
;;; Code:

;;  required modules

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'emacsvox-table)
(require 'emacsvox-table-ui)

;;;   variables

(defvar emacsvox-gridtext-current-grid nil
  "List that records currently active grid for this
buffer.")

(make-variable-buffer-local 'emacsvox-gridtext-current-grid)

;;;   helpers

(defun emacsvox-gridtext-generate-key ()
  "Generates a key for current context.
The key is used when persisting out the grid setting for
future  use."
  (cl-declare (special  major-mode))
  (or (buffer-file-name)
      (format "%s:%s" (buffer-name) major-mode)))

(defun emacsvox-gridtext-vector-region (start end grid)
  "Returns a vector containing the text bounded by start and
end   as specified by grid."
  (let ((result-grid (make-vector (count-lines start end) nil))
        (this-line nil)
        (this-length 0)
        (this-row nil)
        (num-rows (count-lines start end))
        (num-columns(1+  (length grid))))
    (save-excursion
      (save-restriction
        (narrow-to-region start end)
        (if (< start end)
            (goto-char start)
          (goto-char end))
        (cl-loop
         for i from 0 to (1- num-rows)
         do
         (setq this-line
               (buffer-substring (line-beginning-position) (line-end-position)))
         (setq this-length (length this-line))
         (setq this-row (make-vector num-columns ""))
         (cl-loop
          for j from 0 to (1- (length grid))
          do
          (when (< (1- (nth j grid)) this-length)
            ;; within bounds 
            (aset  this-row j
                   (substring
                    this-line
                    (if (= j 0) 
                        0
                      (nth  (1- j) grid))
                    (1- (nth j grid))))))
         (aset this-row (length grid)
               (if (< (nth (1- (length grid)) grid) this-length)
                   (substring this-line
                              (nth (1- (length grid)) grid))
                 ""))
         (aset result-grid i this-row)
         (forward-line 1))
        result-grid))))

;;;   persistent store 

(defvar emacsvox-gridtext-table (make-hash-table :test 'equal)
  "Stores grid settings.")

(defun emacsvox-gridtext-set (key grid)
  "Map grid to key."
  (cl-declare (special emacsvox-gridtext-table))
  (setf (gethash key emacsvox-gridtext-table) grid))

(defun emacsvox-gridtext-get (key)
  "Lookup key and return corresponding grid. "
  (cl-declare (special emacsvox-gridtext-table))
  (gethash key emacsvox-gridtext-table))

(defun emacsvox-gridtext-load (file)
  "Load saved grid settings."
  (interactive
   (list
    (read-file-name "Load grid settings  from file: "
                    emacsvox-user-directory
                    ".gridtext")))
  (condition-case nil
      (progn
        (load
         (expand-file-name  file emacsvox-user-directory)))
    (error (message "Error loading resources from %s "
                    file))))

(defun emacsvox-gridtext-save (file)
  "Save out grid settings."
  (interactive
   (list
    (read-file-name "Save gridtext settings  to file: "
                    emacsvox-user-directory
                    ".gridtext")))
  (cl-declare (special emacsvox-user-directory))
  (let ((print-level nil)
        (print-length nil)
        (buffer (find-file-noselect
                 (expand-file-name file
                                   emacsvox-user-directory))))
    (save-current-buffer
      (set-buffer buffer)
      (erase-buffer)
      (cl-loop for key being the hash-keys of
               emacsvox-gridtext-table
               do
               (insert
                (format
                 "\n(setf
 (gethash %s emacsvox-gridtext-table)
 (quote %s))"
                 (prin1-to-string key)
                 (prin1-to-string (emacsvox-gridtext-get
                                   key)))))
      (basic-save-buffer)
      (kill-buffer buffer))))

;;;  interactive commands

(defun emacsvox-gridtext-apply (start end grid)
  "Apply grid to region."
  (interactive
   (list
    (point) (mark)
    (read-minibuffer
     "Specify grid as a list of tuples: "
     (format "%s" (emacsvox-gridtext-get (emacsvox-gridtext-generate-key))))))
  (let ((grid-table
         (emacsvox-table-make-table
          (emacsvox-gridtext-vector-region start end grid)))
        (buffer (get-buffer-create (format "*%s-grid*" (buffer-name)))))
    (emacsvox-gridtext-set
     (emacsvox-gridtext-generate-key) grid)
    (emacsvox-table-prepare-table-buffer grid-table buffer)))

;;;   keymaps 
(defvar emacsvox-gridtext-keymap nil
  "Prefix keymap used by gridtext.")
;;;###autoload
(define-prefix-command  'emacsvox-gridtext 'emacsvox-gridtext-keymap)
(define-key emacsvox-gridtext-keymap "a" 'emacsvox-gridtext-apply)
(define-key emacsvox-gridtext-keymap "l"
            'emacsvox-gridtext-load)
(define-key emacsvox-gridtext-keymap "s" 'emacsvox-gridtext-save)

(provide 'emacsvox-gridtext)
;;;  end of file

