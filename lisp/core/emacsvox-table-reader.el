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
;; Agent Shell retains its public commands and host-owned reading context.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup emacsvox-table-reader nil
  "Read logical tables in place."
  :group 'emacsvox)

(defcustom emacsvox-table-reader-titles '(column)
  "Default titles spoken with logical table cells."
  :type '(set (const column) (const row))
  :group 'emacsvox-table-reader)

(defcustom emacsvox-table-reader-data-position 'first
  "Whether table cell data precedes or follows its titles."
  :type '(choice (const first) (const last))
  :group 'emacsvox-table-reader)

(defcustom emacsvox-table-reader-movement-speech 'row
  "What plain Up and Down read while navigating a table.
Control-Meta arrows always read the destination cell."
  :type '(choice (const row) (const cell)) :group 'emacsvox-table-reader)
(defcustom emacsvox-table-reader-activation nil
  "When table reading starts.
Nil uses each adapter's default: automatic in Agent Shell and HTML mail in
Notmuch, and on demand elsewhere.  An explicit choice applies to modes
without an override."
  :type '(choice (const :tag "Mode defaults" nil)
                 (const automatic) (const on-demand)) :group 'emacsvox-table-reader)
(defcustom emacsvox-table-reader-coordinates nil
  "Whether table movement also announces the destination coordinates."
  :type 'boolean :group 'emacsvox-table-reader)
(defcustom emacsvox-table-reader-entry-detail 'full
  "Whether entering a table announces its dimensions as well as the cell."
  :type '(choice (const full) (const brief)) :group 'emacsvox-table-reader)
(defcustom emacsvox-table-reader-repeat-titles t
  "Whether movement repeats titles that were already spoken.
When nil, omit unchanged row and column titles on consecutive cell moves.
Explicit inspection always uses the selected titles."
  :type 'boolean :group 'emacsvox-table-reader)
(defcustom emacsvox-table-reader-edge-action 'leave
  "Whether vertical movement leaves a table or stops at its edge.
Application lists always stop.  Explicit exit commands remain available."
  :type '(choice (const leave) (const stop)) :group 'emacsvox-table-reader)
(defcustom emacsvox-table-reader-mode-preferences nil
  "Table preferences by major mode.
Each entry is (MODE . ((SETTING . VALUE) ...)).  SETTING is titles,
data-position, movement-speech, activation, coordinates, entry-detail,
repeat-titles or edge-action.  VALUE inherit explicitly follows common
defaults, including when an older Agent Shell option is set.
Agent Shell transcript and viewport share the agent-shell-mode entry."
  :type '(alist :key-type symbol :value-type (alist :key-type symbol :value-type sexp))
  :group 'emacsvox-table-reader)

(defconst emacsvox-table-reader--options
  '((titles . emacsvox-table-reader-titles)
    (data-position . emacsvox-table-reader-data-position)
    (movement-speech . emacsvox-table-reader-movement-speech)
    (activation . emacsvox-table-reader-activation)
    (coordinates . emacsvox-table-reader-coordinates)
    (entry-detail . emacsvox-table-reader-entry-detail)
    (repeat-titles . emacsvox-table-reader-repeat-titles)
    (edge-action . emacsvox-table-reader-edge-action)))
(defvar-local emacsvox-table-reader--buffer-preferences nil
  "Explicit temporary choices, including inherit to ignore older local values.")
(defvar emacsvox-table-reader--preference-mode nil
  "Adapter's mode while running an operation outside its usual major mode.")
(defvar emacsvox-table-reader--legacy-preexisting nil
  "Legacy options already bound before their initial definition.")
(defvar emacsvox-table-reader--legacy-assigned nil
  "Legacy options assigned after definition, even to their old default.")
(defvar emacsvox-table-reader--legacy-watching nil)
(defvar-local emacsvox-table-reader--last-titles nil)

(defun emacsvox-table-reader--mode ()
  "Return the settings mode, grouping both Agent Shell reading views."
  (or emacsvox-table-reader--preference-mode
      (when (derived-mode-p 'agent-shell-mode 'agent-shell-viewport-view-mode)
        'agent-shell-mode)
      major-mode))

(defun emacsvox-table-reader--legacy-watch (symbol _value operation where)
  "Record explicit assignments to legacy SYMBOL with OPERATION and WHERE."
  (when (eq operation 'set)
    (if (bufferp where)
        (with-current-buffer where
          ;; The variable itself records a local legacy choice.
          (setq emacsvox-table-reader--last-titles nil))
      (cl-pushnew symbol emacsvox-table-reader--legacy-assigned))))

(defun emacsvox-table-reader--watch-legacy ()
  "Observe future legacy assignments without changing or saving values."
  (unless emacsvox-table-reader--legacy-watching
    (dolist (symbol '(emacsvox-agent-shell-table-titles
                      emacsvox-agent-shell-table-data-position))
      (add-variable-watcher symbol #'emacsvox-table-reader--legacy-watch))
    (setq emacsvox-table-reader--legacy-watching t)))

(defun emacsvox-table-reader--mode-choice (key)
  "Return the most specific mode entry for KEY, retaining explicit nil."
  (let ((mode (emacsvox-table-reader--mode)) choice)
    (while (and mode (not choice))
      (setq choice (assq key (alist-get mode emacsvox-table-reader-mode-preferences))
            mode (get mode 'derived-mode-parent)))
    choice))

(defun emacsvox-table-reader--resolve (key)
  "Return (:value VALUE :source SCOPE) for table preference KEY.
An explicit nil title list is a value, never an inheritance marker."
  (let* ((option (alist-get key emacsvox-table-reader--options))
         (buffer-choice (assq key emacsvox-table-reader--buffer-preferences))
         (mode-choice (emacsvox-table-reader--mode-choice key))
         (legacy (and (eq (emacsvox-table-reader--mode) 'agent-shell-mode)
                      (pcase key
                        ('titles 'emacsvox-agent-shell-table-titles)
                        ('data-position 'emacsvox-agent-shell-table-data-position))))
         (legacy-bound (and legacy (boundp legacy)))
         (old-default (if (eq key 'titles) '(column) 'first))
         (local-inherit (eq (cdr buffer-choice) 'inherit))
         value source)
    (cond
     ((and buffer-choice (not local-inherit))
      (setq value (cdr buffer-choice) source 'buffer))
     ((and (not local-inherit) (local-variable-p option))
      (setq value (symbol-value option) source 'buffer))
     ((and (not local-inherit) legacy-bound (local-variable-p legacy))
      (setq value (symbol-value legacy) source 'legacy-buffer))
     (mode-choice
      (if (eq (cdr mode-choice) 'inherit)
          (setq value (default-value option) source 'common)
        (setq value (cdr mode-choice) source 'mode)))
     ((and legacy-bound
           (or (get legacy 'saved-value) (get legacy 'customized-value)
               (memq legacy emacsvox-table-reader--legacy-assigned)
               (memq legacy emacsvox-table-reader--legacy-preexisting)
               (not (equal (default-value legacy) old-default))))
      (setq value (default-value legacy)
            source (if (and (equal value old-default)
                            (memq legacy emacsvox-table-reader--legacy-preexisting)
                            (not (or (get legacy 'saved-value) (get legacy 'customized-value)
                                     (memq legacy emacsvox-table-reader--legacy-assigned))))
                       'legacy-ambiguous 'legacy-mode)))
     (t (setq value (default-value option) source 'common)))
    (when (and (eq key 'activation) (null value))
      (setq value (if (memq (emacsvox-table-reader--mode)
                            '(agent-shell-mode notmuch-show-mode))
                      'automatic 'on-demand)
            source 'built-in))
    (list :value value :source source)))

(defun emacsvox-table-reader--preference (key)
  "Return the effective value for table preference KEY."
  (plist-get (emacsvox-table-reader--resolve key) :value))

(defun emacsvox-table-reader--format (cell presentation &optional movement)
  "Format CELL as PRESENTATION using effective preferences.
MOVEMENT enables optional coordinate and repeated-title feedback."
  (let* ((emacsvox-table-reader-titles (emacsvox-table-reader--preference 'titles))
         (emacsvox-table-reader-data-position (emacsvox-table-reader--preference 'data-position))
         (titles (list (plist-get cell :row-title) (plist-get cell :column-title))))
    (when (and movement (eq presentation 'cell)
               (not (emacsvox-table-reader--preference 'repeat-titles)))
      (when (equal (car titles) (car emacsvox-table-reader--last-titles))
        (setq emacsvox-table-reader-titles (remq 'row emacsvox-table-reader-titles)))
      (when (equal (cadr titles) (cadr emacsvox-table-reader--last-titles))
        (setq emacsvox-table-reader-titles (remq 'column emacsvox-table-reader-titles))))
    (let ((text (funcall
                 (pcase presentation
                   ('cell #'emacsvox-table-reader--cell-speech)
                   ('row #'emacsvox-table-reader--row-speech)
                   ('column #'emacsvox-table-reader--column-speech)
                   ('context #'emacsvox-table-reader--context-speech)
                   ('dimensions #'emacsvox-table-reader--dimensions-speech)) cell)))
      (when movement (setq emacsvox-table-reader--last-titles titles))
      (if (and movement (emacsvox-table-reader--preference 'coordinates))
          (concat text " " (emacsvox-table-reader--context-speech cell))
        text))))

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
             (nth column (or (plist-get cell :column-titles)
                             (and column-titles-p (car rows))))))
      entries))
    (string-join (nreverse entries) " ")))

(defun emacsvox-table-reader--column-speech (cell)
  "Format the logical table column containing semantic CELL."
  (let* ((rows (plist-get cell :rows))
         (column (plist-get cell :column-index))
         (column-titles-p (plist-get cell :column-titles-p))
         (column-title
          (when (and (or column-titles-p (plist-get cell :column-titles))
                     (memq 'column emacsvox-table-reader-titles))
            (emacsvox-table-reader--leading-title-speech
             (nth column (or (plist-get cell :column-titles) (car rows))) 'bold)))
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
  "Alist of (MAJOR-MODE SNAPSHOT SUBMIT [KEYMAP LIFECYCLE]) adapters.
LIFECYCLE may supply :enter and :toggle callbacks for host-owned contexts.
SNAPSHOT returns a fresh cell plist at point, or nil outside a supported table.
SUBMIT accepts text, occasion, presentation and icon.  Adapters retain their
mode's registered Aural facts.  Optional KEYMAP preserves application actions
inside the reading context.  No adapter may edit the source to read it.")

(defvar-local emacsvox-table-reader--adapter nil
  "Adapter selected when explicit reading begins.")
(defvar-local emacsvox-table-reader--region nil
  "Markers delimiting the table in the current reading context.")
(defvar-local emacsvox-table-reader--map-override nil
  "Owned entry in `minor-mode-overriding-map-alist' during reading.")
(defvar-local emacsvox-table-reader--suspended nil
  "Non-nil after leaving or editing, until leaving the table or explicit entry.
For rendered tables an uncertain identity remains suspended until prose is
reached; a re-render alone never resumes reading.")

(defvar emacsvox-table-reader--entering nil
  "Non-nil while the first arrow's feedback should announce reader entry.")

(defun emacsvox-table-reader--entry-filter (command)
  "Offer COMMAND only at a supported source table outside reading mode.
Returning nil lets Emacs resolve the existing binding in lower keymaps."
  (when (and (not emacsvox-table-reader-mode)
             (seq-some (lambda (entry) (derived-mode-p (car entry)))
                       emacsvox-table-reader--adapters)
             (not (nth 4 (emacsvox-table-reader--adapter)))
             (save-excursion
               (save-match-data (emacsvox-table-reader--snapshot))))
    command))

(defun emacsvox-table-reader--enter-and-move (rows columns)
  "Enter reading and move by ROWS and COLUMNS with one spoken result."
  (let ((cell (emacsvox-table-reader--cell))
        (origin (point)))
    (emacsvox-table-reader--enter cell t)
    ;; Keep boundary and zero-count behaviour relative to the original point.
    (goto-char origin)
    (let ((emacsvox-table-reader--entering t))
      (emacsvox-table-reader--move rows columns t))))

(defun emacsvox-table-reader--enter-next-row (count)
  "Enter table reading and move COUNT rows down."
  (interactive "p")
  (emacsvox-table-reader--enter-and-move count 0))
(defun emacsvox-table-reader--enter-previous-row (count)
  "Enter table reading and move COUNT rows up."
  (interactive "p")
  (emacsvox-table-reader--enter-and-move (- count) 0))
(defun emacsvox-table-reader--enter-next-column (count)
  "Enter table reading and move COUNT columns right."
  (interactive "p")
  (emacsvox-table-reader--enter-and-move 0 count))
(defun emacsvox-table-reader--enter-previous-column (count)
  "Enter table reading and move COUNT columns left."
  (interactive "p")
  (emacsvox-table-reader--enter-and-move 0 (- count)))

(defvar emacsvox-table-reader--entry-enabled t
  "Allow conditional Control-Meta arrow entry into source-table reading.
The entry map contributes no binding outside supported tables.")

(defvar emacsvox-table-reader--entry-map
  (let ((map (make-sparse-keymap)))
    (dolist (binding '(("C-M-<up>" . emacsvox-table-reader--enter-previous-row)
                       ("C-M-<down>" . emacsvox-table-reader--enter-next-row)
                       ("C-M-<left>" . emacsvox-table-reader--enter-previous-column)
                       ("C-M-<right>" . emacsvox-table-reader--enter-next-column)))
      (define-key map (kbd (car binding))
                  `(menu-item "Table reading" ,(cdr binding)
                              :filter emacsvox-table-reader--entry-filter)))
    map)
  "Conditional arrow bindings that preserve the underlying maps elsewhere.")

(unless (assq 'emacsvox-table-reader--entry-enabled minor-mode-map-alist)
  (push (cons 'emacsvox-table-reader--entry-enabled
              emacsvox-table-reader--entry-map)
        minor-mode-map-alist))

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
           (if (and emacsvox-table-reader--entering
                    (or emacsvox-table-reader-mode
                        (bound-and-true-p emacsvox-agent-shell--table-navigation-active)))
               (concat "Table reading. " text)
             text)
           occasion presentation icon))

(defun emacsvox-table-reader--release ()
  "Release the reading context without speech or source changes."
  (setq emacsvox-table-reader-mode nil)
  (setq emacsvox-table-reader--last-titles nil)
  (when emacsvox-table-reader--map-override
    (setq minor-mode-overriding-map-alist
          (delq emacsvox-table-reader--map-override
                minor-mode-overriding-map-alist)
          emacsvox-table-reader--map-override nil))
  (mapc (lambda (marker) (set-marker marker nil)) emacsvox-table-reader--region)
  (setq emacsvox-table-reader--region nil)
  (remove-hook 'post-command-hook #'emacsvox-table-reader--post-command t)
  (remove-hook 'after-change-functions #'emacsvox-table-reader--after-change t)
  (remove-hook 'change-major-mode-hook #'emacsvox-table-reader--release t)
  (remove-hook 'kill-buffer-hook #'emacsvox-table-reader--release t)
  (force-mode-line-update))

(defun emacsvox-table-reader--leave ()
  "Leave explicit reading and announce restoration of ordinary mode keys."
  (setq emacsvox-table-reader--suspended t)
  (emacsvox-table-reader--release)
  (emacsvox-table-reader--submit
   "Table reading off." 'navigation 'context 'close-object))

(defun emacsvox-table-reader--after-change (&rest _)
  "End reading after a source edit; let the editing command give feedback."
  (setq emacsvox-table-reader--suspended t)
  (emacsvox-table-reader--release))

(defvar-local emacsvox-table-reader--command-tick nil)

(defun emacsvox-table-reader--before-command ()
  "Remember the text revision before a command, without parsing tables."
  (setq emacsvox-table-reader--command-tick (buffer-chars-modified-tick)))

(add-hook 'pre-command-hook #'emacsvox-table-reader--before-command)

(defun emacsvox-table-reader--automatic-entry ()
  "Enter source tables according to their policy after deliberate navigation."
  (when (and (not emacsvox-table-reader-mode)
             (or (null emacsvox-table-reader--command-tick)
                 (= emacsvox-table-reader--command-tick (buffer-chars-modified-tick)))
             (not (bound-and-true-p transient--prefix))
             (seq-some (lambda (entry) (and (not (nth 4 entry))
                                           (derived-mode-p (car entry))))
                       emacsvox-table-reader--adapters)
             (or emacsvox-table-reader--suspended
                 (eq (emacsvox-table-reader--preference 'activation) 'automatic)))
    (let ((cell (emacsvox-table-reader--snapshot)))
      (cond
       ((null cell) (setq emacsvox-table-reader--suspended nil))
       ((not emacsvox-table-reader--suspended)
        (emacsvox-table-reader--enter cell))))))

(add-hook 'post-command-hook #'emacsvox-table-reader--automatic-entry)

(defun emacsvox-table-reader--post-command ()
  "Restore ordinary keys when point leaves the table that was entered."
  (when emacsvox-table-reader-mode
    (let* ((cell (emacsvox-table-reader--snapshot))
           (region (plist-get cell :region)))
      (unless (and region emacsvox-table-reader--region
                   (= (car region) (car emacsvox-table-reader--region))
                   (= (cdr region) (cadr emacsvox-table-reader--region)))
        (emacsvox-table-reader--leave)))))

(defun emacsvox-table-reader--enter (cell &optional quiet)
  "Activate reading at CELL without modifying or aligning the source.
With QUIET, let the following movement submit the single entry announcement."
  (setq emacsvox-table-reader--suspended nil)
  (if-let* ((enter (plist-get (nth 4 (emacsvox-table-reader--adapter)) :enter)))
      (funcall enter cell quiet)
    (emacsvox-table-reader--release)
  (goto-char (cadr (emacsvox-table-reader--destination cell 0 0)))
  (setq emacsvox-table-reader--adapter (emacsvox-table-reader--adapter)
        emacsvox-table-reader-mode t
        emacsvox-table-reader--region
        (list (copy-marker (car (plist-get cell :region)))
              (copy-marker (cdr (plist-get cell :region)))))
  (when-let* ((map (nth 3 emacsvox-table-reader--adapter)))
    (setq emacsvox-table-reader--map-override
          (cons 'emacsvox-table-reader-mode map))
    (setq-local minor-mode-overriding-map-alist
                (cons emacsvox-table-reader--map-override
                      minor-mode-overriding-map-alist)))
  (add-hook 'post-command-hook #'emacsvox-table-reader--post-command nil t)
  (add-hook 'after-change-functions #'emacsvox-table-reader--after-change nil t)
  (add-hook 'change-major-mode-hook #'emacsvox-table-reader--release nil t)
  (add-hook 'kill-buffer-hook #'emacsvox-table-reader--release nil t)
  (unless quiet
    (emacsvox-table-reader--submit
     (concat "Table reading. "
             (when (eq (emacsvox-table-reader--preference 'entry-detail) 'full)
               (concat (emacsvox-table-reader--dimensions-speech cell) " "))
             (emacsvox-table-reader--format cell 'cell))
     'navigation 'cell 'open-object))
  (force-mode-line-update)))

(defun emacsvox-table-reader--inspect (presentation &optional occasion)
  "Speak PRESENTATION once, using OCCASION or the default inspection intent."
  (let ((cell (emacsvox-table-reader--cell)))
    (emacsvox-table-reader--submit
     (emacsvox-table-reader--format cell presentation)
     (or occasion 'inspection) presentation 'item)))

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

(defun emacsvox-table-reader--move (rows columns &optional cell-only exit-function)
  "Move by logical ROWS and COLUMNS, reading rows after vertical movement.
With CELL-ONLY, read a cell instead.  EXIT-FUNCTION, when supplied, owns
the host's exit lifecycle; otherwise use the explicit reader's exit."
  (pcase (emacsvox-table-reader--destination
          (emacsvox-table-reader--cell) rows columns)
    (`(exit ,direction)
     (if (eq (emacsvox-table-reader--preference 'edge-action) 'stop)
         (emacsvox-table-reader--submit
          (if (eq direction 'backward) "First row of table." "Last row of table.")
          'navigation 'context 'warn-user)
       (funcall (or exit-function #'emacsvox-table-reader--exit) direction)))
    (`(boundary ,text)
     (emacsvox-table-reader--submit text 'navigation 'context 'warn-user))
    (`(cell ,position)
     (goto-char position)
     (let ((cell (emacsvox-table-reader--cell)))
       (emacsvox-table-reader--submit
        (emacsvox-table-reader--format
         cell (if (or cell-only (zerop rows)) 'cell 'row) t)
        'navigation (if (or cell-only (zerop rows)) 'cell 'row) 'item)))))
(defun emacsvox-table-reader-next-row (&optional count)
  "Move COUNT logical rows down, retaining the column and reading the row."
  (interactive "p")
  (emacsvox-table-reader--move (or count 1) 0))
(defun emacsvox-table-reader-previous-row (&optional count)
  "Move COUNT logical rows up, retaining the column and reading the row."
  (interactive "p")
  (emacsvox-table-reader--move (- (or count 1)) 0))
(defun emacsvox-table-reader-next-row-cell (&optional count)
  "Move COUNT rows down, retaining the column and reading the cell."
  (interactive "p")
  (emacsvox-table-reader--move (or count 1) 0 t))
(defun emacsvox-table-reader-previous-row-cell (&optional count)
  "Move COUNT rows up, retaining the column and reading the cell."
  (interactive "p")
  (emacsvox-table-reader--move (- (or count 1)) 0 t))
(defun emacsvox-table-reader--plain-next-row (count)
  "Move COUNT rows down with the selected movement speech."
  (interactive "p")
  (emacsvox-table-reader--move count 0
   (eq (emacsvox-table-reader--preference 'movement-speech) 'cell)))
(defun emacsvox-table-reader--plain-previous-row (count)
  "Move COUNT rows up with the selected movement speech."
  (interactive "p")
  (emacsvox-table-reader--plain-next-row (- count)))
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
             '(("<up>" . emacsvox-table-reader--plain-previous-row)
               ("<down>" . emacsvox-table-reader--plain-next-row)
               ("C-M-<up>" . emacsvox-table-reader-previous-row-cell)
               ("C-M-<down>" . emacsvox-table-reader-next-row-cell)
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
               ("a" . emacsvox-table-settings)
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
  "Toggle logical table reading in the current supported buffer.
Control-Meta arrows enter and read the destination cell.  Plain Up and Down
read rows by default; `emacsvox-table-reader-movement-speech' can choose cells.
Use r/c to inspect rows/columns, a for Tables settings, and q to leave in place.
Quitting or editing suspends automatic entry until you leave the table and
return, or explicitly enter again.  Source reading does not edit or align text.
Agent Shell manages its own contextual map and retains native TAB and RET.
Application lists retain their action keys.  Use M-x reading commands when
an application action occupies a short key.  Native Org editing feedback and
Markdown markup-stripping speech remain independent."
  :lighter " Table"
  :group 'emacsvox-table-reader
  (if-let* ((adapter (seq-find (lambda (entry) (derived-mode-p (car entry)))
                              emacsvox-table-reader--adapters))
            (toggle (plist-get (nth 4 adapter) :toggle)))
      (progn (setq emacsvox-table-reader-mode nil) (funcall toggle arg))
    (if (not emacsvox-table-reader-mode)
      (when emacsvox-table-reader--region (emacsvox-table-reader--leave))
    ;; A failed entry must not leave printable table keys active in prose.
    (setq emacsvox-table-reader-mode nil
          emacsvox-table-reader--adapter nil)
    (emacsvox-table-reader--enter (emacsvox-table-reader--cell)))))

(autoload 'emacsvox-table-settings "emacsvox-table-settings" nil t)


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
