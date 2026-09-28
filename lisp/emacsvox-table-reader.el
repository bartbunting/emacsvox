;;; emacsvox-table-reader.el --- Shared logical table reading  -*- lexical-binding: t; -*-

;; Copyright (C) 2025, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop tables
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

;; Common logical table formatting and navigation.  Adapters supply complete
;; cell values and source positions; reading never calls native table editors.
;; Agent Shell retains its public commands and presentation preferences.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup emacsvox-table-reader nil
  "Read logical tables in place."
  :group 'emacsvox)

(defcustom emacsvox-table-reader-titles '(column)
  "Titles spoken with cells in the explicit table reader.
Agent Shell retains its own table speech preferences."
  :type '(set (const column) (const row))
  :group 'emacsvox-table-reader)

(defcustom emacsvox-table-reader-data-position 'first
  "Whether table cell data precedes or follows its titles."
  :type '(choice (const first) (const last))
  :group 'emacsvox-table-reader)

(defun emacsvox-table-reader--title (title face data)
  "Return TITLE voiced with FACE unless it is blank or duplicates DATA."
  (when-let* ((title (and title (string-trim title)))
              ((not (string-empty-p title)))
              ((not (string= (substring-no-properties title)
                             (substring-no-properties data)))))
    (setq title (copy-sequence title))
    (add-face-text-property 0 (length title) face t title)
    title))

(defun emacsvox-table-reader--cell-speech (cell)
  "Format semantic table CELL according to the table speech options."
  (let* ((raw-data (or (plist-get cell :data) ""))
         (data (string-trim raw-data))
         (data (if (string-empty-p data) "blank" data))
         (row-title
          (when (memq 'row emacsvox-table-reader-titles)
            (emacsvox-table-reader--title
             (plist-get cell :row-title) 'italic data)))
         (column-title
          (when (memq 'column emacsvox-table-reader-titles)
            (emacsvox-table-reader--title
             (plist-get cell :column-title) 'bold data)))
         (titles (delq nil (list row-title column-title)))
         (parts (if (eq emacsvox-table-reader-data-position 'first)
                    (cons data titles)
                  (append titles (list data)))))
    (concat (mapconcat #'identity parts ", ") ".")))

(defun emacsvox-table-reader--context-speech (cell)
  "Format the position and dimensions of semantic table CELL."
  (let ((row-index (plist-get cell :row-index))
        (row-count (plist-get cell :row-count))
        (column (1+ (plist-get cell :column-index)))
        (column-count (plist-get cell :column-count)))
    (cond
     ((and (plist-get cell :column-titles-p) (zerop row-index))
      (let ((data-rows (1- row-count)))
        (format "Header row, column %d of %d; table has %d data %s."
                column column-count data-rows
                (if (= data-rows 1) "row" "rows"))))
     ((plist-get cell :column-titles-p)
      (format "Data row %d of %d, column %d of %d."
              row-index (1- row-count) column column-count))
     (t
      (format "Row %d of %d, column %d of %d."
              (1+ row-index) row-count column column-count)))))

(defun emacsvox-table-reader--dimensions-speech (cell)
  "Format the dimensions of the table containing semantic CELL."
  (let* ((column-titles-p (plist-get cell :column-titles-p))
         (rows (- (plist-get cell :row-count)
                  (if column-titles-p 1 0)))
         (columns (plist-get cell :column-count)))
    (format "Table, %d %s, %d %s."
            rows
            (if column-titles-p
                (if (= rows 1) "data row" "data rows")
              (if (= rows 1) "row" "rows"))
            columns
            (if (= columns 1) "column" "columns"))))

(defun emacsvox-table-reader--leading-title-speech (title face)
  "Format leading table TITLE with FACE, or return nil when it is blank."
  (when-let* ((title (emacsvox-table-reader--title title face "")))
    (concat title ".")))

(defun emacsvox-table-reader--row-speech (cell)
  "Format the logical table row containing semantic CELL."
  (let* ((rows (plist-get cell :rows))
         (row-index (plist-get cell :row-index))
         (row (nth row-index rows))
         (column-titles-p (plist-get cell :column-titles-p))
         (header-row-p (and column-titles-p (zerop row-index)))
         (row-title
          (when (and (not header-row-p)
                     (memq 'row emacsvox-table-reader-titles))
            (emacsvox-table-reader--leading-title-speech
             (car row) 'italic)))
         (first-column (if row-title 1 0))
         entries)
    (when header-row-p
      (push "Header row." entries))
    (when row-title
      (push row-title entries))
    (cl-loop
     for data in (nthcdr first-column row)
     for column from first-column
     do
     (push
      (emacsvox-table-reader--cell-speech
       (list :data data
             :column-title
             (when column-titles-p (nth column (car rows)))))
      entries))
    (string-join (nreverse entries) " ")))

(defun emacsvox-table-reader--column-speech (cell)
  "Format the logical table column containing semantic CELL."
  (let* ((rows (plist-get cell :rows))
         (column (plist-get cell :column-index))
         (column-titles-p (plist-get cell :column-titles-p))
         (column-title
          (when (and column-titles-p
                     (memq 'column emacsvox-table-reader-titles))
            (emacsvox-table-reader--leading-title-speech
             (nth column (car rows)) 'bold)))
         (data-rows (if column-titles-p (cdr rows) rows))
         entries)
    (when column-title
      (push column-title entries))
    (dolist (row data-rows)
      (push
       (emacsvox-table-reader--cell-speech
        (list :data (nth column row)
              :row-title (car row)))
       entries))
    (string-join (nreverse entries) " ")))

(defun emacsvox-table-reader--plain-cell (data)
  "Return table cell DATA without padding or text properties."
  (substring-no-properties (string-trim (or data ""))))

(defun emacsvox-table-reader--exit-destination (region direction)
  "Return a useful point outside table REGION in DIRECTION."
  (pcase direction
    ('backward
     (when (> (car region) (point-min))
       (save-excursion
         (goto-char (car region))
         (backward-char 1)
         (skip-chars-backward " \t\n\r")
         (beginning-of-line)
         (back-to-indentation)
         (point))))
    ('forward
     (when (< (cdr region) (point-max))
       (save-excursion
         (goto-char (cdr region))
         (skip-chars-forward " \t\n\r")
         (back-to-indentation)
         (point))))))

(defun emacsvox-table-reader--destination (cell row-delta column-delta)
  "Return a non-mutating movement result for CELL and the requested deltas.
ROW-DELTA and COLUMN-DELTA use logical coordinates.  The result is
\(`cell' POSITION), (`exit' DIRECTION), or (`boundary' MESSAGE).
CELL carries complete :rows, zero-based :row-index and :column-index,
and a flat :positions list in row order.  Missing cells never clamp."
  (let* ((rows (plist-get cell :rows))
         (row (+ (plist-get cell :row-index) row-delta))
         (column (+ (plist-get cell :column-index) column-delta)))
    (cond
     ((< row 0) '(exit backward))
     ((>= row (length rows)) '(exit forward))
     ((< column 0) '(boundary "Left edge of table."))
     ((>= column (length (nth row rows)))
      (list 'boundary (if (zerop row-delta)
                          "Right edge of table."
                        "No cell in that row.")))
     (t
      (if-let* ((position
                 (nth (+ column (apply #'+ (mapcar #'length (seq-take rows row))))
                      (plist-get cell :positions))))
          (list 'cell position)
        '(boundary "No cell at that position."))))))

(defun emacsvox-table-reader--copy-text (cell object)
  "Return plain logical CELL, row or column text for OBJECT."
  (pcase object
    ('cell (emacsvox-table-reader--plain-cell (plist-get cell :data)))
    ('row (mapconcat #'emacsvox-table-reader--plain-cell
                     (nth (plist-get cell :row-index) (plist-get cell :rows)) "\t"))
    ('column
     (mapconcat (lambda (row)
                  (emacsvox-table-reader--plain-cell
                   (nth (plist-get cell :column-index) row)))
                (plist-get cell :rows) "\n"))))


(defvar-local emacsvox-table-reader-mode nil
  "Non-nil during explicit table reading.")

(defvar emacsvox-table-reader--adapters nil
  "Alist of (MAJOR-MODE SNAPSHOT SUBMIT) table adapters.
SNAPSHOT returns a fresh cell plist at point, or nil outside a supported table.
SUBMIT accepts text, occasion, presentation and icon.  Adapters retain their
mode's registered Aural facts.  No adapter may edit the source to read it.")

(defvar-local emacsvox-table-reader--adapter nil
  "Adapter selected when explicit reading begins.")
(defvar-local emacsvox-table-reader--region nil
  "Markers delimiting the table in the current reading context.")

(defun emacsvox-table-reader--adapter ()
  "Return a registered adapter for the current major mode."
  (or (seq-find (lambda (entry) (derived-mode-p (car entry)))
                emacsvox-table-reader--adapters)
      (user-error "No table reader for %s" mode-name)))

(defun emacsvox-table-reader--snapshot ()
  "Get current logical cell data without retaining stale source positions."
  (funcall (nth 1 (or emacsvox-table-reader--adapter
                      (emacsvox-table-reader--adapter)))))

(defun emacsvox-table-reader--cell ()
  "Return the current cell or reject navigation outside a supported table."
  (or (emacsvox-table-reader--snapshot)
      (user-error "Not in a supported table")))

(defun emacsvox-table-reader--submit (text occasion presentation icon)
  "Submit one TEXT presentation using the active adapter.
OCCASION, PRESENTATION and ICON describe the user's action."
  (funcall (nth 2 (or emacsvox-table-reader--adapter
                      (emacsvox-table-reader--adapter)))
           text occasion presentation icon))

(defun emacsvox-table-reader--release ()
  "Release the reading context without speech or source changes."
  (setq emacsvox-table-reader-mode nil)
  (mapc (lambda (marker) (set-marker marker nil)) emacsvox-table-reader--region)
  (setq emacsvox-table-reader--region nil)
  (remove-hook 'post-command-hook #'emacsvox-table-reader--post-command t)
  (remove-hook 'after-change-functions #'emacsvox-table-reader--after-change t)
  (remove-hook 'change-major-mode-hook #'emacsvox-table-reader--release t)
  (remove-hook 'kill-buffer-hook #'emacsvox-table-reader--release t)
  (force-mode-line-update))

(defun emacsvox-table-reader--leave ()
  "Leave explicit reading and announce restoration of ordinary mode keys."
  (emacsvox-table-reader--release)
  (emacsvox-table-reader--submit
   "Table reading off." 'navigation 'context 'close-object))

(defun emacsvox-table-reader--after-change (&rest _)
  "End reading after a source edit; let the editing command give feedback."
  (emacsvox-table-reader--release))

(defun emacsvox-table-reader--post-command ()
  "Restore ordinary keys when point leaves the table that was entered."
  (when emacsvox-table-reader-mode
    (let* ((cell (emacsvox-table-reader--snapshot))
           (region (plist-get cell :region)))
      (unless (and region emacsvox-table-reader--region
                   (= (car region) (car emacsvox-table-reader--region))
                   (= (cdr region) (cadr emacsvox-table-reader--region)))
        (emacsvox-table-reader--leave)))))

(defun emacsvox-table-reader--enter (cell)
  "Activate reading at CELL without modifying or aligning the source."
  (emacsvox-table-reader--release)
  (goto-char (cadr (emacsvox-table-reader--destination cell 0 0)))
  (setq emacsvox-table-reader--adapter (emacsvox-table-reader--adapter)
        emacsvox-table-reader-mode t
        emacsvox-table-reader--region
        (list (copy-marker (car (plist-get cell :region)))
              (copy-marker (cdr (plist-get cell :region)))))
  (add-hook 'post-command-hook #'emacsvox-table-reader--post-command nil t)
  (add-hook 'after-change-functions #'emacsvox-table-reader--after-change nil t)
  (add-hook 'change-major-mode-hook #'emacsvox-table-reader--release nil t)
  (add-hook 'kill-buffer-hook #'emacsvox-table-reader--release nil t)
  (emacsvox-table-reader--submit
   (concat "Table reading. " (emacsvox-table-reader--dimensions-speech cell)
           " " (emacsvox-table-reader--cell-speech cell))
   'navigation 'cell 'open-object)
  (force-mode-line-update))

(defun emacsvox-table-reader--inspect (presentation)
  "Speak PRESENTATION of the current table as a single inspection."
  (let ((cell (emacsvox-table-reader--cell)))
    (emacsvox-table-reader--submit
     (funcall (pcase presentation
                ('cell #'emacsvox-table-reader--cell-speech)
                ('row #'emacsvox-table-reader--row-speech)
                ('column #'emacsvox-table-reader--column-speech)
                ('context #'emacsvox-table-reader--context-speech)
                ('dimensions #'emacsvox-table-reader--dimensions-speech)) cell)
     'inspection presentation 'item)))

(defun emacsvox-table-reader-speak-cell ()
  "Speak the complete logical table cell at point."
  (interactive)
  (emacsvox-table-reader--inspect 'cell))
(defun emacsvox-table-reader-speak-row ()
  "Speak the complete logical table row at point."
  (interactive)
  (emacsvox-table-reader--inspect 'row))
(defun emacsvox-table-reader-speak-column ()
  "Speak the complete logical table column at point."
  (interactive)
  (emacsvox-table-reader--inspect 'column))
(defun emacsvox-table-reader-speak-context ()
  "Speak the current logical table coordinates."
  (interactive)
  (emacsvox-table-reader--inspect 'context))
(defun emacsvox-table-reader-speak-dimensions ()
  "Speak the current table dimensions, distinguishing headers from data."
  (interactive)
  (emacsvox-table-reader--inspect 'dimensions))

(defun emacsvox-table-reader--copy (object)
  "Copy the logical table OBJECT and confirm with one submission."
  (kill-new (emacsvox-table-reader--copy-text
             (emacsvox-table-reader--cell) object))
  (emacsvox-table-reader--submit
   (format "Copied table %s." object) 'state-change object 'save-object))
(defun emacsvox-table-reader-copy-cell ()
  "Copy the logical cell as plain text."
  (interactive)
  (emacsvox-table-reader--copy 'cell))
(defun emacsvox-table-reader-copy-row ()
  "Copy the logical row as tab-separated plain text."
  (interactive)
  (emacsvox-table-reader--copy 'row))
(defun emacsvox-table-reader-copy-column ()
  "Copy the logical column as newline-separated plain text."
  (interactive)
  (emacsvox-table-reader--copy 'column))

(defun emacsvox-table-reader--exit (direction)
  "Leave the table in DIRECTION and speak the adjacent prose."
  (let* ((cell (emacsvox-table-reader--cell))
         (position (emacsvox-table-reader--exit-destination
                    (plist-get cell :region) direction)))
    (if (not position)
        (emacsvox-table-reader--submit
         (format "No content %s table."
                 (if (eq direction 'forward) "after" "before"))
         'navigation 'context 'warn-user)
      (goto-char position)
      (emacsvox-table-reader--release)
      (emacsvox-table-reader--submit
       (format "%s table. %s"
               (if (eq direction 'forward) "After" "Before")
               (string-trim (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position))))
       'navigation 'context 'close-object))))
(defun emacsvox-table-reader-exit-forward ()
  "Leave table reading and move to following prose."
  (interactive)
  (emacsvox-table-reader--exit 'forward))
(defun emacsvox-table-reader-exit-backward ()
  "Leave table reading and move to preceding prose."
  (interactive)
  (emacsvox-table-reader--exit 'backward))

(defun emacsvox-table-reader--move (rows columns)
  "Move by logical ROWS and COLUMNS, speaking a row after vertical movement."
  (pcase (emacsvox-table-reader--destination
          (emacsvox-table-reader--cell) rows columns)
    (`(exit ,direction) (emacsvox-table-reader--exit direction))
    (`(boundary ,text)
     (emacsvox-table-reader--submit text 'navigation 'context 'warn-user))
    (`(cell ,position)
     (goto-char position)
     (let ((cell (emacsvox-table-reader--cell)))
       (emacsvox-table-reader--submit
        (if (zerop rows) (emacsvox-table-reader--cell-speech cell)
          (emacsvox-table-reader--row-speech cell))
        'navigation (if (zerop rows) 'cell 'row) 'item)))))
(defun emacsvox-table-reader-next-row (&optional count)
  "Move COUNT logical rows down, retaining the column and reading the row."
  (interactive "p")
  (emacsvox-table-reader--move (or count 1) 0))
(defun emacsvox-table-reader-previous-row (&optional count)
  "Move COUNT logical rows up, retaining the column and reading the row."
  (interactive "p")
  (emacsvox-table-reader--move (- (or count 1)) 0))
(defun emacsvox-table-reader-next-column (&optional count)
  "Move COUNT logical columns right and read the destination cell."
  (interactive "p")
  (emacsvox-table-reader--move 0 (or count 1)))
(defun emacsvox-table-reader-previous-column (&optional count)
  "Move COUNT logical columns left and read the destination cell."
  (interactive "p")
  (emacsvox-table-reader--move 0 (- (or count 1))))

(defun emacsvox-table-reader-select-speaking-method ()
  "Choose table titles or data order for this buffer.
Press c for column titles, r for row titles, or o for data order.
Agent Shell and Org editing feedback retain their existing preferences."
  (interactive)
  (let ((choice (read-char-choice
                 "Toggle table speech: column titles, row titles, or order? "
                 '(?c ?r ?o))))
    (if (= choice ?o)
        (setq-local emacsvox-table-reader-data-position
                    (if (eq emacsvox-table-reader-data-position 'first) 'last 'first))
      (let* ((title (if (= choice ?c) 'column 'row))
             (titles (if (memq title emacsvox-table-reader-titles)
                         (remq title emacsvox-table-reader-titles)
                       (cons title emacsvox-table-reader-titles))))
        (setq-local emacsvox-table-reader-titles
                    (seq-filter (lambda (item) (memq item titles)) '(column row)))))
    (emacsvox-table-reader--submit
     (format "Table speech: %s; column titles %s; row titles %s."
             (if (eq emacsvox-table-reader-data-position 'first)
                 "data first" "titles first")
             (if (memq 'column emacsvox-table-reader-titles) "on" "off")
             (if (memq 'row emacsvox-table-reader-titles) "on" "off"))
     'state-change 'context 'button)))

(defun emacsvox-table-reader--find (direction)
  "Find and enter the next supported table in DIRECTION without wrapping."
  (let* ((adapter (emacsvox-table-reader--adapter))
         (emacsvox-table-reader--adapter adapter)
         (current (emacsvox-table-reader--snapshot))
         (step (if (eq direction 'forward) 1 -1))
         found destination)
    (save-excursion
      (when current
        (goto-char (if (> step 0) (cdr (plist-get current :region))
                     (car (plist-get current :region)))))
      (when (or current (< step 0))
        (when (< step 0) (forward-line -1)))
      (while (and (not found) (not (if (> step 0) (eobp) (bobp))))
        (setq found (emacsvox-table-reader--snapshot))
        (if found (setq destination (car (plist-get found :positions)))
          (forward-line step)))
      (unless found
        (setq found (emacsvox-table-reader--snapshot)
              destination (car (plist-get found :positions)))))
    (if (and found destination
             (not (equal (plist-get current :region) (plist-get found :region))))
        (progn (goto-char destination)
               (emacsvox-table-reader--enter (emacsvox-table-reader--cell)))
      (emacsvox-table-reader--submit
       (format "No %s table." (if (> step 0) "next" "previous"))
       'navigation 'context 'warn-user))))

;;;###autoload
(defun emacsvox-table-reader-next-table ()
  "Find the next supported table and enter explicit reading."
  (interactive)
  (emacsvox-table-reader--find 'forward))
;;;###autoload
(defun emacsvox-table-reader-previous-table ()
  "Find the previous supported table and enter explicit reading."
  (interactive)
  (emacsvox-table-reader--find 'backward))

(defvar emacsvox-table-reader-mode-map
  (let ((map (make-sparse-keymap)) (copy (make-sparse-keymap)))
    (dolist (binding
             '(("<up>" . emacsvox-table-reader-previous-row)
               ("<down>" . emacsvox-table-reader-next-row)
               ("C-M-<up>" . emacsvox-table-reader-previous-row)
               ("C-M-<down>" . emacsvox-table-reader-next-row)
               ("C-M-<left>" . emacsvox-table-reader-previous-column)
               ("C-M-<right>" . emacsvox-table-reader-next-column)
               ("<left>" . left-char) ("<right>" . right-char)
               ("M-<up>" . emacsvox-table-reader-exit-backward)
               ("M-<down>" . emacsvox-table-reader-exit-forward)
               ("TAB" . emacsvox-table-reader-next-column)
               ("<backtab>" . emacsvox-table-reader-previous-column)
               ("RET" . emacsvox-table-reader-speak-cell)
               ("SPC" . emacsvox-table-reader-speak-cell)
               ("r" . emacsvox-table-reader-speak-row)
               ("c" . emacsvox-table-reader-speak-column)
               ("." . emacsvox-table-reader-speak-context)
               ("=" . emacsvox-table-reader-speak-dimensions)
               ("w" . emacsvox-table-reader-copy-cell)
               ("a" . emacsvox-table-reader-select-speaking-method)
               ("t" . emacsvox-table-reader-next-table)
               ("T" . emacsvox-table-reader-previous-table)
               ("q" . emacsvox-table-reader-mode)))
      (define-key map (kbd (car binding)) (cdr binding)))
    (define-key copy "k" #'emacsvox-table-reader-copy-cell)
    (define-key copy "r" #'emacsvox-table-reader-copy-row)
    (define-key copy "c" #'emacsvox-table-reader-copy-column)
    (define-key map "k" copy)
    map)
  "Keys used only during explicit table reading.
Other editing commands retain their normal meaning; editing ends reading.")

;;;###autoload
(define-minor-mode emacsvox-table-reader-mode
  "Read a Markdown or Org table in place with contextual navigation keys.
Use the speech prefix followed by C-t C-r to toggle reading.  Up/Down read
logical rows, C-M-Left/Right read cells, and r/c read rows/columns.  TAB moves
right without editing and RET reads the cell.  q restores normal mode keys.
Leaving the table or editing its source also ends this context.  This mode
is independent of Markdown's markup-stripping speech preference."
  :lighter " Table"
  :group 'emacsvox-table-reader
  (if (not emacsvox-table-reader-mode)
      (when emacsvox-table-reader--region (emacsvox-table-reader--leave))
    ;; A failed entry must not leave printable table keys active in prose.
    (setq emacsvox-table-reader-mode nil
          emacsvox-table-reader--adapter nil)
    (emacsvox-table-reader--enter (emacsvox-table-reader--cell))))


(defun emacsvox-table-reader--pipe-spans (begin end &optional markdown)
  "Return absolute cell spans between BEGIN and END on one source line.
With MARKDOWN, preserve escaped pipes and matched inline code spans.  Outer
pipes are optional; no phantom cell is added after a closing outer pipe."
  (save-excursion
    (goto-char begin)
    (skip-chars-forward " \t" end)
    (setq begin (point))
    (goto-char end)
    (skip-chars-backward " \t" begin)
    (setq end (point))
    (goto-char begin)
    (let ((start (if (eq (char-after) ?|) (1+ begin) begin)) spans pipes)
      (goto-char start)
      (while (< (point) end)
        (cond
         ((and markdown (eq (char-after) ?\\))
          (forward-char (min 2 (- end (point)))))
         ((and markdown (eq (char-after) ?`))
          (let* ((width (skip-chars-forward "`" end))
                 (after (point)) close)
            (while (and (not close) (re-search-forward "`+" end t))
              (when (= width (- (match-end 0) (match-beginning 0)))
                (setq close (point))))
            (goto-char (or close after))))
         ((eq (char-after) ?|)
          (push (cons start (point)) spans)
          (push (point) pipes)
          (setq start (1+ (point)))
          (forward-char 1))
         (t (forward-char 1))))
      (unless (and pipes (= (car pipes) (1- end)))
        (push (cons start end) spans))
      (nreverse spans))))

(defun emacsvox-table-reader--source-cell (region markdown clean separator)
  "Build fresh logical cell data for a pipe table in REGION.
MARKDOWN controls quoting rules; CLEAN converts each cell to logical text.
SEPARATOR recognizes a structural line.  Only a separator immediately after
one row establishes column titles.  Mid-table separators are never data."
  (let ((origin (point)) rows positions spans-by-row lines header)
    (save-excursion
      (goto-char (car region))
      (while (< (point) (cdr region))
        (let* ((begin (line-beginning-position))
               (end (line-end-position))
               (line (buffer-substring-no-properties begin end)))
          (if (funcall separator line)
              (when (= (length rows) 1) (setq header t))
            (let* ((spans (emacsvox-table-reader--pipe-spans begin end markdown))
                   (row (mapcar
                         (lambda (span)
                           (funcall clean (string-trim
                                           (buffer-substring-no-properties
                                            (car span) (cdr span))))) spans)))
              (push row rows)
              (push begin lines)
              (push spans spans-by-row)
              (dolist (span spans)
                (goto-char (car span))
                (skip-chars-forward " \t" (cdr span))
                (push (point) positions))))
          (goto-char end)
          (forward-line 1))))
    (setq rows (nreverse rows) lines (nreverse lines)
          spans-by-row (nreverse spans-by-row) positions (nreverse positions))
    (when rows
      (let* ((row (max 0 (1- (cl-count-if (lambda (line) (<= line origin)) lines))))
             (spans (nth row spans-by-row))
             (column (max 0 (1- (cl-count-if
                                (lambda (span) (<= (car span) origin)) spans))))
             (values (nth row rows)))
        (list :region region :positions positions :rows rows
              :row-index row :row-count (length rows)
              :column-index column :column-count (apply #'max (mapcar #'length rows))
              :data (nth column values) :column-titles-p header
              :column-title (and header (nth column (car rows)))
              :row-title (unless (and header (zerop row)) (car values)))))))

(provide 'emacsvox-table-reader)
;;; emacsvox-table-reader.el ends here
