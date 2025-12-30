;;; emacsvox-table-ui.el --- Table Navigation UI  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Emacsvox Table Navigation UI
;; Keywords: Emacsvox, Table UI ,  Visual layout gives structure
;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 
;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995 by T. V. Raman
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


;;;   Introduction

;;; Commentary:
;; User interface to tables
;;; Code:

;;;  requires
(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(eval-when-compile
  (require 'derived))
(require 'emacsvox-preamble)
(require 'emacsvox-table)

;;;   emacsvox table mode

;; emacsvox-table-submap makes these available globally.
;; Forward declaration

(define-derived-mode  emacsvox-table-mode  special-mode
  "Table Navigation On The Emacsvox Audio Desktop"
  "Major mode for browsing tables.
Table mode is designed to allow speech users to browse tabular
data with full contextual feedback while retaining all the power
of the two-dimensional spatial layout of tables.

In table mode, the arrow keys move between cells of the table.
Emacsvox speaks the cell contents in a user-customizable way.  The
visual display is kept in sync with the speech you hear; however
Emacsvox is examining the entire table in order to speak the current
cell content intelligently.

You can interactively specify that emacsvox should speak either the row or
column header (or both) while speaking each cell.  You can also specify a row
or column filter that should be applied when speaking entire rows or columns
--this lets you view slices of a table.  You can move to a specific row or
column by searching the cell contents or by searching the row or column
headers to locate items of interest.

Here is a short description of the special commands provided in this mode.

The next four commands help you move to the edges of the table:

E               emacsvox-table-goto-right
A               emacsvox-table-goto-left
B               emacsvox-table-goto-bottom
T               emacsvox-table-goto-top

The next two commands let you search the table.
The commands ask you if you want to search rows or columns.
When searching headers remember that row 0 is the column header,
and that column 0 is the row header.

h               emacsvox-table-search-headers
s               emacsvox-table-search

The next command lets you specify how cell contents should be spoken.  Specify
one of: `b' for both, `c' for column, `r' for row, `f' for row filtering and
`g' for column filtering. --table cells with then be spoken with both (or
either)row and column headers, or with the filter applied.

a               emacsvox-table-select-automatic-speaking-method

The next set of commands speak the current table cell:

.               emacsvox-table-speak-coordinates
b               emacsvox-table-speak-both-headers-and-element
SPC             emacsvox-table-speak-current-element
c               emacsvox-table-speak-column-header-and-element
r               e macspeak-table-speak-row-header-and-element

The next set of commands navigate the table:

right               emacsvox-table-next-column
left               emacsvox-table-previous-column
down               emacsvox-table-next-row
up               emacsvox-table-previous-row
j               emacsvox-table-goto
S-tab               emacsvox-table-previous-column
TAB               emacsvox-table-next-column

Row and Column Filtering

Filtering is designed to let you view slices of a table.
They are specified as lists of numbers and strings.
The concept is best explained with an example.

A row filter specifies which of the entries in the current row should be
spoken.Entries are numbered starting with 0.  Thus, when working with a table
having 8 columns, a row filter of (1 2 3) will speak only entries 1 2 and 3.
Use the sample tables in etc/tables   to familiarize yourself with this
feature. Note that you can intersperse meaningful strings in the list that
specifies the filter.

Full List Of Keybindings:
\\{emacsvox-table-mode-map}"
  (set (make-local-variable 'voice-lock-mode) t)
  (put-text-property (point-min) (point-max)
                     'point-entered 'emacsvox-table-point-motion-hook)
  (set-buffer-modified-p nil)
  (setq buffer-undo-list  t)
  (setq buffer-read-only t)
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(cl-loop
 for binding in
 '(
   ("M-l" emacsvox-table-ui-filter-load)
   ("M-s" emacsvox-table-ui-filter-save)
   ("S-<tab>" emacsvox-table-previous-column)
   ("#" emacsvox-table-sort-on-current-column)
   ("." emacsvox-table-speak-coordinates)
   ("," emacsvox-table-find-csv-file)
   ("v" emacsvox-table-view-csv-buffer)
   ("<down>" emacsvox-table-next-row)
   ("<left>" emacsvox-table-previous-column)
   ("<right>" emacsvox-table-next-column)
   ("<up>"  emacsvox-table-previous-row)
   ("=" emacsvox-table-speak-dimensions)
   ("<" emacsvox-table-goto-left)
   (">" emacsvox-table-goto-right)
   ("M-<" emacsvox-table-goto-top)
   ("M->" emacsvox-table-goto-bottom)
   ("A" emacsvox-table-goto-left)
   ("B" emacsvox-table-goto-bottom)
   ("C" emacsvox-table-search-column)
   ("C-b" emacsvox-table-previous-column)
   ("C-f" emacsvox-table-next-column)
   ("C-n" emacsvox-table-next-row)
   ("C-p" emacsvox-table-previous-row)
   ("E" emacsvox-table-goto-right)
   ("R" emacsvox-table-search-row)
   ("SPC" emacsvox-table-speak-current-element)
   ("T" emacsvox-table-goto-top)
   ("TAB" emacsvox-table-next-column)
   ("a" emacsvox-table-select-automatic-speaking-method)
   ("b" emacsvox-table-speak-both-headers-and-element)
   ("c" emacsvox-table-speak-column-header-and-element)
   ("f" emacsvox-table-speak-row-filtered)
   ("g" emacsvox-table-speak-column-filtered)
   ("h" emacsvox-table-search-headers)
   ("j" emacsvox-table-goto)
   ("k" emacsvox-table-copy-to-clipboard)
   ("n" emacsvox-table-next-row)
   ("p" emacsvox-table-previous-row)
   ("q" quit-window)
   ("Q" emacsvox-kill-buffer-quietly)
   ("r" emacsvox-table-speak-row-header-and-element)
   ("s" emacsvox-table-search)
   ("w" emacsvox-table-copy-current-element-to-kill-ring)
   ("x" emacsvox-table-copy-current-element-to-register)
   )
 do
 (emacsvox-keymap-update emacsvox-table-mode-map binding)
 (emacsvox-keymap-update emacsvox-table-submap binding))

;;;   speaking current entry

(defun emacsvox-table-synchronize-display ()
  "Bring visual display in sync with internal representation"
  
  (let ((row (emacsvox-table-current-row emacsvox-table))
        (column (emacsvox-table-current-column emacsvox-table))
        (width (frame-width)))
    (goto-char
     (or
      (gethash
       (intern
        (format "element:%s:%s" row column))
       ems--positions)
      (point)))
    (scroll-left (- (current-column)
                    (+ (/ width  2)
                       (window-hscroll))))))

(defun  emacsvox-table-speak-coordinates ()
  "Speak current table coordinates."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (message "Row %s Column %s"
           (emacsvox-table-current-row emacsvox-table)
           (emacsvox-table-current-column emacsvox-table)))

(defun  emacsvox-table-speak-dimensions ()
  "Speak current table dimensions."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (message "%s by %s table"
           (emacsvox-table-num-rows emacsvox-table)
           (emacsvox-table-num-columns emacsvox-table)))

(defun emacsvox-table-speak-current-element ()
  "Speak current table element"
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (message
   (format "%s" (emacsvox-table-current-element emacsvox-table))))

(defun emacsvox-table-speak-row-header-and-element ()
  "Speak  row header and table element"
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (let ((element (emacsvox-table-current-element emacsvox-table))
        (head
         (format
          "%s"
          (emacsvox-table-row-header-element
           emacsvox-table
           (emacsvox-table-current-row emacsvox-table)))))
    (put-text-property 0 (length head) 'face 'italic head)
    (dtk-speak
     (concat head
             (format " %s" element)))))

(defun emacsvox-table-speak-column-header-and-element ()
  "Speak  column header and table element"
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (let ((head
         (format
          "%s"
          (emacsvox-table-column-header-element
           emacsvox-table
           (emacsvox-table-current-column emacsvox-table))))
        (content nil))
    (put-text-property 0 (length head) 'face 'italic head)
    (setq content
          (string-trim
           (concat
            head
            (format " %s" (emacsvox-table-current-element
                           emacsvox-table)))))
    (cond
     ((zerop (length content))
      (dtk-speak-list "blank")
      (sox-sin 0.1 400))
     (t (message content)))))

(defun emacsvox-table-speak-both-headers-and-element ()
  "Speak  both row and column header and table element"
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (let ((element (emacsvox-table-current-element emacsvox-table))
        (col-head
         (format
          "%s"
          (emacsvox-table-column-header-element
           emacsvox-table
           (emacsvox-table-current-column emacsvox-table))))
        (row-head
         (format
          "%s"
          (emacsvox-table-row-header-element
           emacsvox-table
           (emacsvox-table-current-row emacsvox-table)))))
    (put-text-property
     0 (length row-head) 'face 'italic row-head)
    (put-text-property
     0 (length col-head) 'face 'bold col-head)
    (dtk-speak
     (concat row-head " " col-head
             (format " %s" element)))))

(defun emacsvox-table-get-entry-with-headers  (row column
                                                    &optional
                                                    row-head-p
                                                    col-head-p)
  "Return table element. Optional args specify  if we return any headers."
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (let ((col-head nil)
        (row-head nil))
    (when row-head-p
      (setq row-head
            (format "%s"
                    (emacsvox-table-row-header-element emacsvox-table row)))
      (put-text-property 0 (length row-head)
                         'face 'italic row-head))
    (when  col-head-p
      (setq col-head
            (format
             "%s"
             (emacsvox-table-column-header-element emacsvox-table column)))
      (put-text-property
       0 (length col-head)
       'face 'bold col-head))
    (concat
     row-head " " col-head " "
     (format " %s"
             (emacsvox-table-this-element emacsvox-table row column)))))

(defvar emacsvox-table-speak-row-filter nil
  "Template specifying how a row is filtered before it is spoken.")

(make-variable-buffer-local 'emacsvox-table-speak-row-filter)

(defun emacsvox-table-handle-row-filter-token  (token)
  "Handle a single token in an Emacsvox table row/column formatter."
  (let ((value nil))
    (cond
     ((stringp token) (format "%s" token))
     ((numberp token)
      (setq value
            (emacsvox-table-get-entry-with-headers
             (emacsvox-table-current-row emacsvox-table) token))
      (put-text-property
       0 (length value)
       'face 'bold  value)
      value)
     ((and (listp token) (numberp (cl-first token)) (numberp (cl-second token)))
      (setq value
            (emacsvox-table-get-entry-with-headers
             (cl-first token) (cl-second token)))
      (put-text-property 0 (length value) 'face 'bold value)
      value)
     ((and (symbolp (cl-first token)) (fboundp  (cl-first token)))
      ;; applying a function:
      (setq value
            (funcall
             (cl-first token) ;;; get args
             (cond
              ((and
                (= 2 (length token)) (numberp (cl-second token)))
               (emacsvox-table-get-entry-with-headers
                (emacsvox-table-current-row emacsvox-table)
                (cl-second token)))
              ((and
                (= 3 (length token))
                (numberp (cl-second token))
                (numberp (cl-third token)))
               (emacsvox-table-get-entry-with-headers
                (cl-second token) (cl-third token))))))
      (put-text-property 0 (length value) 'face 'bold  value)
      value)
     (t  (format "%s" token)))))

(defun emacsvox-table-speak-row-filtered  (&optional prefix)
  "Speaks a table row after applying a specified row filter.
Optional prefix arg prompts for a new filter."
  (interactive "P")
  
  (and emacsvox-table-speak-row-filter
       (push emacsvox-table-speak-row-filter minibuffer-default))
  (unless (and  emacsvox-table-speak-row-filter
                (listp emacsvox-table-speak-row-filter)
                (not prefix))
    (setq emacsvox-table-speak-row-filter
          (read-minibuffer
           "Specify row filter as a list: "
           (format
            "%s"
            (or
             (emacsvox-table-ui-filter-get (emacsvox-table-ui-generate-key))
             "("))))
    (emacsvox-table-ui-filter-set
     (emacsvox-table-ui-generate-key)
     emacsvox-table-speak-row-filter))
  (message
   (mapconcat
    #'emacsvox-table-handle-row-filter-token
    emacsvox-table-speak-row-filter
    " ")))

(defvar emacsvox-table-speak-column-filter nil
  "Template specifying how a column is filtered before it is spoken.")

(make-variable-buffer-local 'emacsvox-table-speak-column-filter)

(defun emacsvox-table-handle-column-filter-token (token)
  "Handle token from column filter."
  (let ((value nil))
    (cond
     ((stringp token) token)
     ((numberp token)
      (emacsvox-table-get-entry-with-headers
       token
       (emacsvox-table-current-column emacsvox-table)))
     ((and (listp token)
           (numberp (cl-first token))
           (numberp (cl-second token)))
      (emacsvox-table-get-entry-with-headers
       (cl-first token) (cl-second token)))
     ((and (symbolp (cl-first token)) (fboundp  (cl-first token)))
      ;; applying a function:
      (setq value
            (funcall
             (cl-first token) ;;; get args
             (cond
              ((and
                (= 2 (length token)) (numberp (cl-second token)))
               (emacsvox-table-get-entry-with-headers
                (cl-second token)
                (emacsvox-table-current-column emacsvox-table)))
              ((and
                (= 3 (length token))
                (numberp (cl-second token))
                (numberp (cl-third token)))
               (emacsvox-table-get-entry-with-headers
                (cl-second token) (cl-third token))))))
      (put-text-property 0 (length value) 'face 'bold  value)
      value)
     (t  (format "%s" token)))))
(defun emacsvox-table-speak-column-filtered  (&optional prefix)
  "Speaks a table column after applying a specified column filter.
Optional prefix arg prompts for a new filter."
  (interactive "P")
  (cl-declare (special emacsvox-table-speak-column-filter
                       emacsvox-table))
  (unless (and  emacsvox-table-speak-column-filter
                (listp emacsvox-table-speak-column-filter)
                (not prefix))
    (setq emacsvox-table-speak-column-filter
          (read-minibuffer "Specify column filter as a list: " "(")))
  (message
   (mapconcat
    #'emacsvox-table-handle-column-filter-token
    emacsvox-table-speak-column-filter
    " ")))

;;;   what to do when point moves

(defun emacsvox-table-point-motion-hook (old new)
  "Bring internal representation in sync with visual display"
  
  (condition-case nil
      (emacsvox-table-goto-cell
       emacsvox-table
       (get-text-property new 'row)
       (get-text-property new 'column))
    (error nil))
  (push-mark old t))

;;;   opening a file of table data

;;;  csv helpers:

(defun ems-csv-forward-field ()
  "Skip forward over one field."
  (skip-syntax-forward " ")
  (if (and (following-char) (eq (following-char) ?\"))
      (forward-sexp)
    (skip-chars-forward "^,\n")))

(defun ems-csv-backward-field ()
  "Skip backward over one field."
  (skip-syntax-backward " ")
  (if (eq (preceding-char) ?\")
      (backward-sexp)
    (skip-chars-backward "^,\n")))

;;;###autoload
(defun emacsvox-table-prepare-table-buffer (table buffer)
  "Prepare tabular data."
  
  (with-current-buffer buffer
    (emacsvox-table-mode)
    (let ((i 0)
          (j 0)
          (count 0)
          (row-start 1)
          (column-start 1)
          (inhibit-read-only t))
      (setq truncate-lines t)
      (setq buffer-undo-list  t)
      (erase-buffer)
      (set (make-local-variable 'emacsvox-table) table)
      (set (make-local-variable 'ems--positions) (make-hash-table))
      (setq count (1-  (emacsvox-table-num-columns table)))
      (cl-loop
       for row across (emacsvox-table-elements table) do
       (cl-loop
        for _element across row do
        (puthash
         (intern (format "element:%s:%s" i j))  ; compute key
         (point) ; insertion point  is the value
         ems--positions)
        (insert
         (format "%s%s"
                 (emacsvox-table-this-element table i j)
                 (if (=  j count)
                     "\n"
                   "\t")))
        (put-text-property column-start (point)
                           'column j)
        (setq column-start (point))
        (cl-incf j))
       (setq j 0)
       (put-text-property row-start (point) 'row i)
       (setq row-start (point))
       (cl-incf i))))
  (switch-to-buffer buffer)
  (emacsvox-table-goto-cell emacsvox-table 0 0)
  (setq truncate-lines t)
  (message "Use Emacsvox Table UI to browse this table."))

;;;###autoload
(defun emacsvox-table-find-file (filename)
  "Open a file containing table data and display it in table mode.
emacsvox table mode is designed to let you browse tabular data using
all the power of the two-dimensional spatial layout while giving you
sufficient contextual information.  The etc/tables subdirectory of the
emacsvox distribution contains some sample tables --these are the
CalTrain schedules.  Execute command `describe-mode' bound to
\\[describe-mode] in a buffer that is in emacsvox table mode to read
the documentation on the table browser."
  (interactive "FEnter filename containing table data: ")
  
  (let ((buffer (get-buffer-create (format  "*%s*"
                                            (file-name-nondirectory filename))))
        (data nil)
        (table nil))
    (setq data (find-file-noselect filename))
    (setq table (emacsvox-table-make-table (read data)))
    (kill-buffer data)
    (emacsvox-table-prepare-table-buffer table buffer)))

(defun ems-csv-get-fields ()
  "Return list of fields on this line."
  (let ((fields nil)
        (this-field nil)
        (start (line-beginning-position)))
    (goto-char start)
    (while (not (eolp))
      (ems-csv-forward-field)
      (setq this-field
            (cond
             ((= (preceding-char) ?\")
              (buffer-substring-no-properties  start (point)))
             (t (buffer-substring-no-properties start  (point)))))
      (push this-field fields)
      (when(and (char-after) (= (char-after) ?,))
        (forward-char 1))
      (setq start (point)))
    (when (= (preceding-char) ?,)
      (push "" fields))
    (nreverse fields)))

;;;###autoload
(defun emacsvox-table-find-csv-file (filename)
  "Process a csv (comma separated values) file.
The processed  data is presented using emacsvox table navigation. "
  (interactive "FFind CSV file: ")
  (let  ((buffer (find-file-noselect filename)))
    (emacsvox-table-view-csv-buffer buffer)
    (kill-buffer buffer)))

;;;###autoload
(defun emacsvox-table-view-csv-buffer (&optional buffer-name)
  "Process a csv (comma separated values) data.
The processed  data is  presented using emacsvox table navigation. "
  (interactive)
  (or buffer-name
      (setq buffer-name (current-buffer)))
  (let ((scratch (get-buffer-create "*csv-scratch*"))
        (table nil)
        (elements nil)
        (fields nil)
        (buffer (get-buffer-create
                 (format "*%s-table*" buffer-name))))
    (save-current-buffer
      (set-buffer scratch)
      (setq buffer-undo-list  t)
      (erase-buffer)
      (insert-buffer-substring buffer-name)
      (goto-char (point-min))
      (flush-lines "^ *$")
      (goto-char (point-min))
      (setq elements
            (make-vector (count-lines (point-min) (point-max))
                         nil))
      (cl-loop for i from 0 to (1- (length elements))
               do
               (setq fields (ems-csv-get-fields))
               (aset elements i (apply 'vector fields))
               (forward-line 1))
      (setq table (emacsvox-table-make-table elements))
      )
    (kill-buffer scratch)
    (emacsvox-table-prepare-table-buffer table buffer)
    (emacsvox-icon 'open-object)))

(defun emacsvox-table-render-csv-url  (_status result-buffer)
  "Render the result of asynchronously retrieving CSV data from url."
  (let ((inhibit-read-only t)
        (data-buffer (current-buffer))
        (coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))
    (with-current-buffer data-buffer
      (goto-char (point-min))
      (search-forward "\n\n")
      (delete-region (point-min) (point))
      (decode-coding-region (point-min) (point-max) 'utf-8)
      (emacsvox-table-view-csv-buffer)
      (rename-buffer result-buffer 'unique)
      (emacsvox-speak-mode-line)
      (emacsvox-icon 'open-object))))

;;;###autoload
(defun emacsvox-table-view-csv-url  (url &optional buffer-name)
  "Process a csv (comma separated values) data at  `URL'.
The processed  data is  presented using emacsvox table navigation. "
  (interactive "sURL:\nP")
  (unless (or buffer-name (stringp buffer-name))
    (setq buffer-name "CSV Data Table"))
  
  (url-retrieve url #'emacsvox-table-render-csv-url  (list buffer-name)))

;;;  Processing a region of tabular data

;;;  select default speaking action

(defvar emacsvox-table-select-automatic-speaking-method-prompt
  "Select: b both c column d default r row f filter row g filter column "
  "Prompt to display when selecting automatic speaking method for
table elements")

(defun emacsvox-table-select-automatic-speaking-method ()
  "Interactively select the kind of automatic speech to produce when
browsing table elements"
  (interactive)
  
  (message emacsvox-table-select-automatic-speaking-method-prompt)
  (let ((key (read-char)))
    (setq emacsvox-table-speak-element
          (cl-case  key
            (?b 'emacsvox-table-speak-both-headers-and-element)
            (?c 'emacsvox-table-speak-column-header-and-element)
            (?r 'emacsvox-table-speak-row-header-and-element)
            (?d 'emacsvox-table-speak-current-element)
            (?f 'emacsvox-table-speak-row-filtered)
            (?g 'emacsvox-table-speak-column-filtered)
            (?. 'emacsvox-table-speak-coordinates)
            (otherwise (message "Invalid method specified")
                       emacsvox-table-speak-element)))
    (emacsvox-icon 'button)))

;;;  Navigating the table:

(defvar emacsvox-table-speak-element
  'emacsvox-table-speak-current-element
  "Function to call when automatically speaking table elements.")

(make-variable-buffer-local 'emacsvox-table-speak-element)

(defun emacsvox-table-next-row (&optional count)
  "Move to the next row if possible"
  (interactive "p")
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (setq count (or count 1))
  (emacsvox-table-move-down emacsvox-table count)
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element))

(defun emacsvox-table-previous-row (&optional count)
  "Move to the previous row if possible"
  (interactive "p")
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (setq count (or count 1))
  (emacsvox-table-move-up emacsvox-table count)
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element))

(defun emacsvox-table-next-column (&optional count)
  "Move to the next column if possible"
  (interactive "p")
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (setq count (or count 1))
  (emacsvox-table-move-right emacsvox-table count)
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element))

(defun emacsvox-table-previous-column (&optional count)
  "Move to the previous column  if possible"
  (interactive "p")
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (setq count (or count 1))
  (emacsvox-table-move-left emacsvox-table count)
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element))

(defun emacsvox-table-goto (row column)
  "Prompt for a table cell coordinates and jump to it."
  (interactive "nRow:\nNColumn:")
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (emacsvox-table-goto-cell emacsvox-table row column)
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element)
  (emacsvox-icon 'large-movement))

(defun emacsvox-table-goto-top ()
  "Goes to the top of the current column."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (emacsvox-table-goto-cell
   emacsvox-table
   0 (emacsvox-table-current-column emacsvox-table))
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element)
  (emacsvox-icon 'large-movement))

(defun emacsvox-table-goto-bottom ()
  "Goes to the bottom of the current column."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (emacsvox-table-goto-cell
   emacsvox-table

   (1- (emacsvox-table-num-rows emacsvox-table))
   (emacsvox-table-current-column
    emacsvox-table))
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element)
  (emacsvox-icon 'large-movement))

(defun emacsvox-table-goto-left ()
  "Goes to the left of the current row."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (emacsvox-table-goto-cell
   emacsvox-table
   (emacsvox-table-current-row emacsvox-table) 0)
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element)
  (emacsvox-icon 'left))

(defun emacsvox-table-goto-right ()
  "Goes to the right of the current row."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (emacsvox-table-goto-cell
   emacsvox-table
   (emacsvox-table-current-row emacsvox-table)
   (1- (emacsvox-table-num-columns emacsvox-table)))
  (emacsvox-table-synchronize-display)
  (funcall emacsvox-table-speak-element)
  (emacsvox-icon 'right))

;;;  searching and finding:

(defun emacsvox-table-search (&optional what)
  "Search the table for matching elements.  Interactively prompts for
row or column to search and pattern to look for.    If there is a match, makes
the matching cell current. When called from a program, `what' can
  be either `row' or `column'."
  (interactive "P")
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (message "Search   in: r row c column")
  (let* ((row (emacsvox-table-current-row emacsvox-table))
         (column (emacsvox-table-current-column emacsvox-table))
         (found nil)
         (slice
          (or what
              (cl-case (read-char)
                (?r 'row)
                (?c 'column)
                (otherwise (error "Can only search in either row or column")))))
         (pattern
          (read-string
           (format "Search in current  %s for: " slice))))
    (cond
     ((eq slice 'row)
      (setq found
            (emacsvox-table-find-match-in-row
             emacsvox-table row pattern 'string-match)))
     ((eq slice 'column)
      (setq found
            (emacsvox-table-find-match-in-column
             emacsvox-table column pattern 'string-match)))
     (t (error "Invalid search")))
    (cond
     (found
      (cond
       ((eq slice 'row)
        (emacsvox-table-goto-cell emacsvox-table row found))
       ((eq slice 'column)
        (emacsvox-table-goto-cell emacsvox-table found column)))
      (emacsvox-table-synchronize-display)
      (emacsvox-icon 'search-hit))
     (t (emacsvox-icon 'search-miss)))
    (funcall emacsvox-table-speak-element)))

(defun emacsvox-table-search-row ()
  "Search in current table row."
  (interactive)
  (emacsvox-table-search 'row))

(defun emacsvox-table-search-column ()
  "Search in current table column."
  (interactive)
  (emacsvox-table-search 'column))

(defun emacsvox-table-search-headers ()
  "Search the table row or column headers.  Interactively prompts for
row or column to search and pattern to look for.  If there is a
match, makes the matching row or column current."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (message
   "Search headers : r row c column")
  (let* ((row (emacsvox-table-current-row emacsvox-table))
         (column (emacsvox-table-current-column emacsvox-table))
         (found nil)
         (slice
          (cl-case (read-char "Search headers : r row c column")
            (?r 'row)
            (?c 'column)
            (otherwise (error "Can only search in either row or column"))))
         (pattern
          (completing-read
           (format "Search %s headers for: " slice)
           (cond
            ((eq slice 'row)
             (append (emacsvox-table-row-header emacsvox-table) nil))
            ((eq slice 'column)
             (append (emacsvox-table-column-header emacsvox-table) nil)))
           nil 'must-match)))
    (cond
     ((eq slice 'row)
      (setq found
            (emacsvox-table-find-match-in-column
             emacsvox-table 0 pattern 'string-match)))
     ((eq slice 'column)
      (setq found
            (emacsvox-table-find-match-in-row
             emacsvox-table 0 pattern 'string-match)))
     (t (error "Invalid search")))
    (cond
     (found
      (cond
       ((eq slice 'row)
        (emacsvox-table-goto-cell emacsvox-table  found column))
       ((eq slice 'column)
        (emacsvox-table-goto-cell emacsvox-table row found)))
      (emacsvox-table-synchronize-display)
      (emacsvox-icon 'search-hit))
     (t (emacsvox-icon 'search-miss)))
    (emacsvox-table-speak-both-headers-and-element)))

;;;  cutting and pasting tables:

(defun emacsvox-table-copy-current-element-to-kill-ring ()
  "Copy current table element to kill ring."
  (interactive)
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (kill-new  (emacsvox-table-current-element emacsvox-table))
  (when (called-interactively-p 'interactive) 
    (emacsvox-icon 'yank-object)
    (message "Copied element to kill ring")))
(defun emacsvox-table-copy-current-element-to-register (register)
  "Copy current table element to specified register."
  (interactive (list (register-read-with-preview "Copy to register: ")))
  
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (set-register register (emacsvox-table-current-element
                          emacsvox-table))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'select-object)
    (message "Copied element to register %c" register)))

;;;  variables

;; Implementing table editing and table clipboard.
(defvar emacsvox-table-clipboard nil
  "Variable to hold table copied to the clipboard.")

;;;   define table markup structure and accessors

(cl-defstruct (emacsvox-table-markup
               (:constructor
                emacsvox-table-make-markup))
  table-start
  table-end
  row-start
  row-end
  col-start
  col-end
  col-separator)

(defvar emacsvox-table-markup-table  (make-hash-table)
  "Hash table to hold mapping between major modes and mode specific
table markup.")

(defun emacsvox-table-markup-set-table (mode markup)
  
  (setf  (gethash mode emacsvox-table-markup-table) markup))

(defun emacsvox-table-markup-get-table (mode)
  
  (or (gethash mode emacsvox-table-markup-table)
      (gethash 'fundamental-mode emacsvox-table-markup-table)))

;;;   define table markup for the various modes of interest
(let ((html-table
       (emacsvox-table-make-markup
        :table-start "<TABLE>\n"
        :table-end "</TABLE>\n"
        :row-start "<TR>\n"
        :row-end "</TR>\n"
        :col-start "<TD>\n"
        :col-end "</TD>\n"
        :col-separator "")))
  (emacsvox-table-markup-set-table 'xml-mode html-table)
  (emacsvox-table-markup-set-table 'nxml-mode html-table)
  (emacsvox-table-markup-set-table 'html-helper-mode html-table))

(emacsvox-table-markup-set-table 'latex2e-mode
                                  (emacsvox-table-make-markup
                                   :table-start "\\begin{tabular}{}\n"
                                   :table-end "\\end{tabular}\n"
                                   :row-start ""
                                   :row-end "\\\\\n"
                                   :col-start ""
                                   :col-end ""
                                   :col-separator " & "))
(emacsvox-table-markup-set-table 'latex-mode
                                  (emacsvox-table-markup-get-table
                                   'latex2e-mode))

(emacsvox-table-markup-set-table 'LaTeX-mode
                                  (emacsvox-table-markup-get-table
                                   'latex2e-mode))

(emacsvox-table-markup-set-table 'TeX-mode
                                  (emacsvox-table-markup-get-table
                                   'latex2e-mode))

(emacsvox-table-markup-set-table
 'org-mode
 (emacsvox-table-make-markup
  :table-start ""
  :table-end ""
  :row-start "|"
  :row-end "|\n"
  :col-start ""
  :col-end ""
  :col-separator "|"))

(emacsvox-table-markup-set-table 'fundamental-mode
                                  (emacsvox-table-make-markup
                                   :table-start ""
                                   :table-end ""
                                   :row-start ""
                                   :row-end "\n"
                                   :col-start "\""
                                   :col-end "\""
                                   :col-separator ", "))

(emacsvox-table-markup-set-table
 'text-mode
 (emacsvox-table-make-markup
  :table-start
  "\n------------------------------------------------------------\n"
  :table-end
  "\n------------------------------------------------------------\n"
  :row-start ""
  :row-end "\n"
  :col-start ""
  :col-end ""
  :col-separator "\t"))

;;;  copy and paste tables

(defun emacsvox-table-copy-to-clipboard ()
  "Copy table in current buffer to the table clipboard.
Current buffer must be in emacsvox-table mode."
  (interactive)
  
  (cl-assert (eq   major-mode 'emacsvox-table-mode)  nil "Not in table mode.")
  (cl-assert  (boundp 'emacsvox-table) nil "No table here")
  (setq emacsvox-table-clipboard emacsvox-table)
  (message "Copied current table to emacsvox table clipboard."))

(defun emacsvox-table-paste-from-clipboard ()
  "Paste the emacsvox table clipboard into the current buffer.
Use the major  mode of this buffer to  decide what kind of table
markup to use."
  (interactive)
  
  (let ((mode  major-mode)
        (markup nil)
        (table (emacsvox-table-elements emacsvox-table-clipboard))
        (read-only buffer-read-only)
        (table-start nil)
        (table-end nil)
        (row-start nil)
        (row-end nil)
        (col-start nil)
        (col-end nil)
        (col-separator nil))
    (cond
     (read-only (error "Cannot paste into read only buffer."))
     (t
      (setq markup  (emacsvox-table-markup-get-table mode))
      (setq table-start (emacsvox-table-markup-table-start markup)
            table-end (emacsvox-table-markup-table-end markup)
            row-start (emacsvox-table-markup-row-start markup)
            row-end (emacsvox-table-markup-row-end markup)
            col-start (emacsvox-table-markup-col-start markup)
            col-end (emacsvox-table-markup-col-end markup)
            col-separator (emacsvox-table-markup-col-separator markup))
      (insert (format "%s" table-start))
      (cl-loop
       for row across table
       do
       (insert (format "%s" row-start))
       (let
           ((current 0)
            (final (length row)))
         (cl-loop
          for column across row do
          (insert (format "%s %s %s"
                          col-start column col-end))
          (cl-incf current)
          (unless (= current final)
            (insert
             (format "%s" col-separator)))))
       (insert (format "%s" row-end)))
      (insert (format "%s" table-end))))))

;;;   table sorting:

(defun emacsvox-table-sort-on-current-column ()
  "Sort table on current column. "
  (interactive)
  (cl-declare (special major-mode emacsvox-table
                       emacsvox-table-speak-row-filter))
  (cl-assert (eq major-mode  'emacsvox-table-mode) nil "Not in table mode.")
  (let* ((column  (emacsvox-table-current-column emacsvox-table))
         (row-head   nil)
         (row-filter emacsvox-table-speak-row-filter)
         (rows (append
                (emacsvox-table-elements emacsvox-table) nil))
         (sorted-table nil)
         (sorted-row-list nil)
         (buffer(get-buffer-create  (format "sorted-on-%d" column))))
    (setq row-head (pop rows)) ;;; header does not play in sort
    (setq  rows
           (cl-remove-if
            #'(lambda (row)
                (null (aref row column)))
            rows))
    (setq
     sorted-row-list
     (sort
      rows
      #'(lambda (x y)
          (cond
           ((and (numberp (read  (aref x column)))
                 (numberp (read  (aref y column))))
            (< (read  (aref x column))
               (read  (aref y column))))
           ((and (stringp  (aref x column))
                 (stringp (aref y column)))
            (string-lessp (aref x column)
                          (aref y column)))
           (t (string-lessp
               (format "%s" (aref x column))
               (format "%s" (aref y column))))))))
    (push row-head sorted-row-list)
    (setq sorted-table (make-vector (length sorted-row-list) nil))
    (cl-loop
     for i from 0 to (1- (length sorted-row-list)) do
     (aset sorted-table i (nth i sorted-row-list)))
    (emacsvox-table-prepare-table-buffer
     (emacsvox-table-make-table  sorted-table) buffer)
    (switch-to-buffer buffer)
    (setq emacsvox-table-speak-row-filter row-filter)
    (emacsvox-table-goto  0 column)
    (call-interactively #'emacsvox-table-next-row)))

;;;   persistent store

(defun emacsvox-table-ui-generate-key ()
  "Generates a key for current context.
The key is used when persisting out the filter setting for
future  use."
  
  (or (buffer-file-name)
      (format "%s:%s" (buffer-name) major-mode)))

(defvar emacsvox-table-ui-filter-table (make-hash-table :test 'equal)
  "Stores table filter  settings.")

(defun emacsvox-table-ui-filter-set (key filter)
  "Map filter to key."
  
  (setf (gethash key emacsvox-table-ui-filter-table) filter))

(defun emacsvox-table-ui-filter-get (key)
  "Lookup key and return corresponding filter. "
  
  (gethash key emacsvox-table-ui-filter-table))

(defun emacsvox-table-ui-filter-load (file)
  "Load saved filter settings."
  (interactive
   (list
    (read-file-name "Load filter settings  from file: "
                    emacsvox-user-directory
                    ".table-ui-filter")))
  (condition-case nil
      (progn
        (load
         (expand-file-name  file emacsvox-user-directory)))
    (error (message "Error loading resources from %s "
                    file))))

(defun emacsvox-table-ui-filter-save (file)
  "Save out filter settings."
  (interactive
   (list
    (read-file-name "Save table-ui-filter settings  to file: "
                    emacsvox-user-directory
                    ".table-ui-filter")))
  
  (let ((buffer (find-file-noselect
                 (expand-file-name file
                                   emacsvox-user-directory))))
    (save-current-buffer
      (set-buffer buffer)
      (erase-buffer)
      (cl-loop for key being the hash-keys of
               emacsvox-table-ui-filter-table
               do
               (insert
                (format
                 "\n(setf
 (gethash %s emacsvox-table-ui-filter-table)
 (quote %s))"
                 (prin1-to-string key)
                 (prin1-to-string (emacsvox-table-ui-filter-get
                                   key)))))
      (basic-save-buffer)
      (kill-buffer buffer))))

(provide  'emacsvox-table-ui)

