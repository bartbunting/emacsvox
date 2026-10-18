;;; emacsvox-agent-shell-tables.el --- Rendered Agent Shell tables  -*- lexical-binding: t; -*-

;; Copyright (C) 2025, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop agent-shell
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
;; Rendered Markdown table mapping, movement, speech and contextual keys.
;; Load through `emacsvox-agent-shell', which owns integration activation.
;; This adapter delegates logical reading to `emacsvox-table-reader'.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-render)
(require 'emacsvox-table-reader)

(declare-function agent-shell--point-in-live-input-p "agent-shell-prompt" ())

(declare-function emacsvox-agent-shell--vertical-toggle-hint-setup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--vertical-toggle-hint-cleanup
                  "emacsvox-agent-shell" ())
(declare-function emacsvox-agent-shell--presentation-facts
                  "emacsvox-agent-shell-presentation" (role &optional event states attributes))
(declare-function emacsvox-agent-shell--submit-text-feedback
                  "emacsvox-agent-shell-presentation" (text facts occasion &optional icon delivery-policy replacement-key))
(declare-function emacsvox-agent-shell--live-input-bounds
                  "emacsvox-agent-shell" ())
(defvar emacsvox-agent-shell-table-titles)
(defvar emacsvox-agent-shell-table-data-position)
(defvar emacsvox-agent-shell--speech-control-active)
(defvar emacsvox-agent-shell--speech-control-map)

(defvar-local emacsvox-agent-shell--table-navigation-active nil
  "Non-nil when contextual Markdown table keys are active.")

(defvar-local emacsvox-agent-shell--table-navigation-table-start nil
  "Start position of the rendered table currently being navigated.")

(defvar-local emacsvox-agent-shell--table-navigation-region nil
  "Marker pair tracking the table independently of a renderer's working point.")

(defvar-local emacsvox-agent-shell--table-navigation-origin nil
  "Point before the command most recently tracked for table entry.")

(defvar-local emacsvox-agent-shell--table-navigation-owns-aural-module-p nil
  "Non-nil when table navigation assigned the local Aural module.")

(defvar-local emacsvox-agent-shell--table-navigation-saved-aural-module nil
  "Locality and value preceding table navigation's Aural module.")

(defun emacsvox-agent-shell--markdown-table-separator-p (row)
  "Return non-nil if Markdown table ROW is a separator row."
  (string-match-p "\\`[ \t]*|[-:| \t]+|[ \t]*\\'" row))

(defun emacsvox-agent-shell--table-cell-value (cell)
  "Decode renderer escape placeholders in a copy of CELL.
Table metadata is captured before the renderer's final escape decoding.
Decode after splitting cells so an escaped pipe stays inside its cell."
  (let ((value (copy-sequence cell)))
    (dotimes (index (length value))
      (when-let* ((literal (get-text-property index 'agent-shell-markdown-escaped value)))
        (when (characterp literal)
          (setq value
                (concat (substring value 0 index)
                        (apply #'propertize (char-to-string literal)
                               (text-properties-at index value))
                        (substring value (1+ index))))
          (remove-text-properties index (1+ index)
                                  '(agent-shell-markdown-escaped nil) value))))
    value))

(defun emacsvox-agent-shell--markdown-table-parse-row (row)
  "Return the logical cells parsed from Markdown table ROW.
Preserve cell text properties and ignore pipes protected by agent-shell's
Markdown renderer."
  (let ((length (length row))
        (position 0)
        cells
        ended-with-separator)
    (while (and (< position length)
                (memq (aref row position) '(?\s ?\t)))
      (setq position (1+ position)))
    (when (and (< position length) (eq (aref row position) ?|))
      (setq position (1+ position)))
    (let ((cell-start position))
      (while (< position length)
        (let ((character (aref row position)))
          (cond
           ((and (eq character ?|)
                 (not (get-text-property
                       position 'agent-shell-markdown-frozen row)))
            (push (string-trim (substring row cell-start position)) cells)
            (setq position (1+ position)
                  cell-start position
                  ended-with-separator t))
           ((eq character ?\\)
            (setq position (min length (+ position 2))
                  ended-with-separator nil))
           (t
            (unless (memq character '(?\s ?\t))
              (setq ended-with-separator nil))
            (setq position (1+ position))))))
      (unless ended-with-separator
        (push (string-trim (substring row cell-start length)) cells))
    (mapcar #'emacsvox-agent-shell--table-cell-value (nreverse cells)))))

(defun emacsvox-agent-shell--markdown-table-rows (source)
  "Parse Markdown table SOURCE into rows and separator metadata."
  (let (rows separator-p)
    (dolist (line (split-string source "\n"))
      (unless (string-empty-p (string-trim line))
        (if (emacsvox-agent-shell--markdown-table-separator-p line)
            (setq separator-p t)
          (push (emacsvox-agent-shell--markdown-table-parse-row line)
                rows))))
    (list :rows (nreverse rows) :column-titles-p separator-p)))

(defun emacsvox-agent-shell--markdown-table-region-at-point ()
  "Return the rendered Markdown table region at point, or nil."
  (when (get-text-property (point) 'agent-shell-markdown-table-source)
    (cons
     (or (previous-single-property-change
          (min (1+ (point)) (point-max))
          'agent-shell-markdown-table-source nil (point-min))
         (point-min))
     (or (next-single-property-change
          (point) 'agent-shell-markdown-table-source nil (point-max))
         (point-max)))))

(defun emacsvox-agent-shell--markdown-table-cell-starts (region)
  "Return navigable cell positions in rendered Markdown table REGION."
  (let (positions)
    (save-excursion
      (save-restriction
        (narrow-to-region (car region) (cdr region))
        (goto-char (point-min))
        (while-let ((match (text-property-search-forward
                            'agent-shell-markdown-table-cell-start t t)))
          (push (prop-match-beginning match) positions))))
    (nreverse positions)))

(defun emacsvox-agent-shell--table-line-borders ()
  "Return the rendered vertical border positions on the current line."
  (let ((end (line-end-position)) borders)
    (save-excursion
      (goto-char (line-beginning-position))
      (while (re-search-forward "[│|]" end t)
        (let ((position (1- (point))))
          (when (seq-some
                 (lambda (property)
                   (emacsvox-agent-shell--face-spec-includes-p
                    (get-text-property position property)
                    'agent-shell-markdown-table-border))
                 '(face font-lock-face))
            (push position borders)))))
    (nreverse borders)))

(defun emacsvox-agent-shell--table-cell-layout (region starts)
  "Return the cell index and rendered spans at point in table REGION.
STARTS lists the first content position of every logical cell.  Continuation
lines use their bordered column and the preceding logical row's markers."
  (let* ((position (point))
         (inhibit-field-text-motion t)
         (line-end (line-end-position))
         (anchor (car (last (seq-take-while
                            (lambda (start) (<= start line-end)) starts)))))
    (when anchor
      (save-excursion
        (let* ((borders (emacsvox-agent-shell--table-line-borders))
               (column (and (cdr borders)
                            (max 0 (min (- (length borders) 2)
                                        (1- (length (seq-take-while
                                                     (lambda (border)
                                                       (<= border position))
                                                     borders))))))))
          (when column
            (goto-char anchor)
            (let* ((row-start (line-beginning-position))
                   (row-end (line-end-position))
                   (first (seq-find (lambda (start) (>= start row-start)) starts))
                   (next-row (seq-find (lambda (start) (> start row-end)) starts))
                   (limit (if next-row
                              (save-excursion
                                (goto-char next-row) (line-beginning-position))
                            (cdr region)))
                   (index (+ (cl-position first starts) column))
                   spans)
              (goto-char row-start)
              (while (< (point) limit)
                (let* ((edges (emacsvox-agent-shell--table-line-borders))
                       (left (nth column edges))
                       (right (nth (1+ column) edges)))
                  (when (and left right)
                    (save-excursion
                      (goto-char (1+ left))
                      (skip-chars-forward " \t" right)
                      (let ((start (point)))
                        (goto-char right)
                        (skip-chars-backward " \t" start)
                        (when (< start (point))
                          (push (cons start (point)) spans))))))
                (forward-line 1))
              (list :index index :spans (nreverse spans)))))))))

(defun emacsvox-agent-shell--table-cell-text-map (cell)
  "Return logical text and buffer positions for rendered CELL.
Join hard word breaks directly.  A whitespace break uses one padding space
as a navigable space between the two rendered fragments."
  (let ((source (substring-no-properties (plist-get cell :data)))
        (offset 0) (text "") positions previous-end)
    (dolist (span (plist-get cell :spans))
      (let* ((fragment (buffer-substring-no-properties (car span) (cdr span)))
             (match (string-match (regexp-quote fragment) source offset)))
        (when (and previous-end (or (null match) (> match offset)))
          (setq text (concat text " "))
          (push previous-end positions))
        (setq text (concat text fragment))
        (cl-loop for position from (car span) below (cdr span)
                 do (push position positions))
        (setq offset (if match (+ match (length fragment)) offset)
              previous-end (cdr span))))
    (when previous-end
      (list text (vconcat (nreverse (cons previous-end positions)))))))

(defun emacsvox-agent-shell--table-text-motion (target direction count word-p)
  "Handle interactive TARGET movement through the current logical cell.
DIRECTION and COUNT determine movement; WORD-P selects words rather than
characters.  Return non-nil only when this function owns the movement."
  (when (and emacsvox-agent-shell--table-navigation-active
             (not (zerop count))
             (derived-mode-p 'agent-shell-mode 'agent-shell-viewport-view-mode)
             (not (and (derived-mode-p 'agent-shell-mode)
                       (agent-shell--point-in-live-input-p))))
    (when-let* ((cell (emacsvox-agent-shell--markdown-table-cell-at-point)))
      (ems-interactive-p target)
      (if-let* ((mapping (emacsvox-agent-shell--table-cell-text-map cell)))
          (let* ((text (car mapping))
                 (positions (cadr mapping))
                 (offset 0)
                 (delta (* (if (eq direction 'forward) 1 -1) count))
                 (syntax (syntax-table)) destination speech)
            (dotimes (index (length positions))
              (when (<= (aref positions index) (point))
                (setq offset index)))
            (if word-p
                (with-temp-buffer
                  (set-syntax-table syntax)
                  (insert text)
                  (goto-char (1+ offset))
                  (forward-word delta)
                  (when (> delta 0) (skip-syntax-forward " "))
                  (setq destination (1- (point)))
                  (unless (eobp)
                    (let ((start (point)))
                      (forward-word 1)
                      (setq speech (buffer-substring-no-properties start (point))))))
              (setq destination (max 0 (min (length text) (+ offset delta)))))
            (goto-char (aref positions destination))
            (cond
             ((and (< delta 0) (= offset 0))
              (emacsvox-agent-shell--table-boundary-feedback "Beginning of cell."))
             ((= destination (length text))
              (emacsvox-agent-shell--table-boundary-feedback "End of cell."))
             (word-p
              (emacsvox-agent-shell--submit-text-feedback
               speech (emacsvox-agent-shell--table-cell-facts cell 'focus-entered)
               'navigation))
             (t
              (and tts-stop-immediately (tts-stop))
              (let ((emacsvox-aural-submission-occasion 'navigation))
                ;; A wrap space may occupy pixel padding with a display
                ;; property.  Speak the text, without its layout cue.
                (emacsvox-speak-this-char (aref text destination))))))
        (emacsvox-agent-shell--table-boundary-feedback "Blank cell."))
      t)))

(defun emacsvox-agent-shell--forward-word-around (original &rest arguments)
  "Follow logical table text during interactive forward word movement."
  (if (and (memq ems--interactive-fn-name '(forward-word right-word))
           (emacsvox-agent-shell--table-text-motion
            ems--interactive-fn-name 'forward
            (prefix-numeric-value (car arguments)) t))
      nil
    (apply original arguments)))

(defun emacsvox-agent-shell--backward-word-around (original &rest arguments)
  "Follow logical table text during interactive backward word movement."
  (if (and (memq ems--interactive-fn-name '(backward-word left-word))
           (emacsvox-agent-shell--table-text-motion
            ems--interactive-fn-name 'backward
            (prefix-numeric-value (car arguments)) t))
      nil
    (apply original arguments)))

(defun emacsvox-agent-shell--markdown-table-cell-at-point ()
  "Return semantic Markdown table cell data for point, or nil."
  (when-let* ((source (get-text-property
                       (point) 'agent-shell-markdown-table-source))
              (region (emacsvox-agent-shell--markdown-table-region-at-point))
              (starts
               (emacsvox-agent-shell--markdown-table-cell-starts region)))
    (let* ((layout (emacsvox-agent-shell--table-cell-layout region starts))
           (position (point))
           (line-start (line-beginning-position))
           (line-end (line-end-position))
           (first-cell-on-line
            (seq-find
             (lambda (start)
               (and (<= line-start start) (<= start line-end)))
             starts))
           ;; Ordinary line motion can land on a row's leading border or
           ;; padding, before that row's first navigable cell marker.  Resolve
           ;; that prefix as the first cell on the same rendered row instead
           ;; of retaining the final cell from the preceding row.
           (effective-position
            (if (and first-cell-on-line (< position first-cell-on-line))
                first-cell-on-line
              position))
           (cell-index -1)
          (index 0))
      (dolist (start starts)
        (when (<= start effective-position)
          (setq cell-index index))
        (setq index (1+ index)))
      (when layout (setq cell-index (plist-get layout :index)))
      (when (>= cell-index 0)
        (let* ((parsed (emacsvox-agent-shell--markdown-table-rows source))
               (rows (plist-get parsed :rows))
               (column-titles-p (plist-get parsed :column-titles-p))
               (remaining cell-index)
               (row-index 0)
               current-row
               column-index)
          (while (and rows (not current-row))
            (if (< remaining (length (car rows)))
                (setq current-row (car rows)
                      column-index remaining)
              (setq remaining (- remaining (length (car rows)))
                    rows (cdr rows)
                    row-index (1+ row-index))))
          (when current-row
            (let ((all-rows (plist-get parsed :rows)))
              (list
               :positions starts
               :spans (plist-get layout :spans)
               :data (nth column-index current-row)
               :row-index row-index
               :row-count (length all-rows)
               :column-index column-index
               :column-count
               (apply #'max 0 (mapcar #'length all-rows))
               :column-titles-p column-titles-p
               :rows all-rows
               :column-title
               (when column-titles-p
                 (nth column-index (car all-rows)))
               :row-title
               (unless (and column-titles-p (zerop row-index))
                 (car current-row))))))))))

(defun emacsvox-agent-shell--table-snapshot ()
  "Return a fresh rendered cell for the shared reader, or nil.
Reject editable input and incomplete source-to-display mappings.  Never keep
positions across a render or resize."
  (let* ((input (emacsvox-agent-shell--live-input-bounds))
         (region (emacsvox-agent-shell--markdown-table-region-at-point))
         (cell
          (and region
               (not (derived-mode-p 'agent-shell-viewport-edit-mode))
               (not (and input (>= (point) (car input))))
               (emacsvox-agent-shell--markdown-table-cell-at-point))))
    (if (and cell
             (= (length (plist-get cell :positions))
                (apply #'+ (mapcar #'length (plist-get cell :rows)))))
        (plist-put cell :region region)
      (setq emacsvox-agent-shell--table-navigation-active nil
            emacsvox-agent-shell--table-navigation-table-start nil)
      nil)))

(defun emacsvox-agent-shell--table-submit (text occasion presentation icon)
  "Submit shared-reader TEXT with Agent Shell's existing semantic facts.
OCCASION, PRESENTATION and ICON identify inspection, movement or copying."
  (emacsvox-agent-shell--submit-text-feedback
   text
   (cond
    ((eq occasion 'state-change)
     (emacsvox-agent-shell--presentation-facts
      (if (eq presentation 'cell) 'agent-table-cell 'agent-table)
      'agent-content-copied))
    ((eq icon 'warn-user)
     (emacsvox-agent-shell--presentation-facts 'agent-table 'boundary-entered))
    ((eq presentation 'dimensions)
     (emacsvox-agent-shell--presentation-facts
      'agent-table 'agent-content-inspected))
    (t
     (emacsvox-agent-shell--table-cell-facts
      (emacsvox-agent-shell--table-snapshot)
      (if (eq occasion 'navigation) 'focus-entered 'agent-content-inspected))))
   occasion icon))

(defun emacsvox-agent-shell--table-read (operation &rest arguments)
  "Run shared reader OPERATION with ARGUMENTS in the rendered-table adapter.
Keep the contextual map and lifecycle with Agent Shell.  Binding the adapter
only during an operation avoids installing the explicit reader's entry map
or changing the scope of existing presentation preferences."
  (let ((emacsvox-table-reader--adapter
         '(agent-shell-mode emacsvox-agent-shell--table-snapshot
                            emacsvox-agent-shell--table-submit))
        (emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (apply operation arguments)))

(defun emacsvox-agent-shell--table-title (title face data)
  "Delegate table title to the shared reader."
  (let ((emacsvox-table-reader-titles emacsvox-agent-shell-table-titles)
        (emacsvox-table-reader-data-position
         emacsvox-agent-shell-table-data-position))
    (emacsvox-table-reader--title title face data)))

(defun emacsvox-agent-shell--table-cell-speech (cell)
  "Format table cell with the effective reading preferences."
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (emacsvox-table-reader--format cell 'cell)))

(defun emacsvox-agent-shell--table-cell-facts (cell &optional event)
  "Return registered semantic facts for table CELL and optional EVENT."
  (emacsvox-agent-shell--presentation-facts
   'agent-table-cell event nil
   (list
    :agent-table-row (plist-get cell :row-index)
    :agent-table-column (plist-get cell :column-index))))

(defun emacsvox-agent-shell--table-cell-feedback (&optional whole-row)
  "Speak the rendered Markdown table cell at point semantically.
When WHOLE-ROW is non-nil, speak its entire logical row."
  (when (emacsvox-agent-shell--table-snapshot)
    (emacsvox-agent-shell--table-read
     #'emacsvox-table-reader--inspect (if whole-row 'row 'cell) 'navigation)
    t))

(defun emacsvox-agent-shell--table-context-speech (cell)
  "Format table context with the effective reading preferences."
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (emacsvox-table-reader--format cell 'context)))

(defun emacsvox-agent-shell--table-dimensions-speech (cell)
  "Format table dimensions with the effective reading preferences."
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (emacsvox-table-reader--format cell 'dimensions)))

(defun emacsvox-agent-shell--table-entry-feedback (direction)
  "Enter and speak the table at point in navigation DIRECTION."
  (when-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
              (starts
               (emacsvox-agent-shell--markdown-table-cell-starts region)))
    (goto-char (if (eq direction 'forward) (car starts) (car (last starts))))
    (when-let* ((cell (emacsvox-agent-shell--table-snapshot)))
      (setq emacsvox-table-reader--suspended nil
            emacsvox-table-reader--last-titles nil)
      (emacsvox-agent-shell--table-track-region region)
      (setq emacsvox-agent-shell--table-navigation-active t
            emacsvox-agent-shell--table-navigation-table-start (car region))
      (emacsvox-agent-shell--submit-text-feedback
       (emacsvox-agent-shell--table-entry-text cell)
       (emacsvox-agent-shell--presentation-facts
        'agent-table 'agent-table-entered)
       'navigation 'open-object)
      t)))

(defun emacsvox-agent-shell-table-speak-context ()
  "Speak current Markdown table position and dimensions."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--inspect 'context))

(defun emacsvox-agent-shell-table-speak-cell ()
  "Speak the logical Markdown table cell at point."
  (interactive)
  (unless (emacsvox-agent-shell--table-cell-feedback)
    (user-error "Not in a rendered Markdown table")))

(defun emacsvox-agent-shell-table-speak-dimensions ()
  "Speak the dimensions of the Markdown table at point."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--inspect 'dimensions))

(defun emacsvox-agent-shell--table-leading-title-speech (title face)
  "Delegate table leading-title-speech to the shared reader."
  (let ((emacsvox-table-reader-titles emacsvox-agent-shell-table-titles)
        (emacsvox-table-reader-data-position
         emacsvox-agent-shell-table-data-position))
    (emacsvox-table-reader--leading-title-speech title face)))

(defun emacsvox-agent-shell--table-row-speech (cell)
  "Format table row with the effective reading preferences."
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (emacsvox-table-reader--format cell 'row)))

(defun emacsvox-agent-shell--table-column-speech (cell)
  "Format table column with the effective reading preferences."
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (emacsvox-table-reader--format cell 'column)))

(defun emacsvox-agent-shell-table-speak-row ()
  "Speak the logical Markdown table row at point."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--inspect 'row))

(defun emacsvox-agent-shell-table-speak-column ()
  "Speak the logical Markdown table column at point."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--inspect 'column))

;; Agent-shell does not currently expose a current-cell value or copy command.
;; Prefer speech-enabling that command if agent-shell adds one in the future.
(defun emacsvox-agent-shell--table-plain-cell (data)
  "Delegate table plain-cell to the shared reader."
  (let ((emacsvox-table-reader-titles emacsvox-agent-shell-table-titles)
        (emacsvox-table-reader-data-position
         emacsvox-agent-shell-table-data-position))
    (emacsvox-table-reader--plain-cell data)))

(defun emacsvox-agent-shell--table-copy (text object)
  "Copy plain TEXT to the kill ring and announce copied table OBJECT."
  (kill-new (substring-no-properties text))
  (emacsvox-agent-shell--submit-text-feedback
   (format "Copied table %s." object)
   (emacsvox-agent-shell--presentation-facts
    (if (string= object "cell") 'agent-table-cell 'agent-table)
    'agent-content-copied)
   'state-change 'save-object))

(defun emacsvox-agent-shell-table-copy-cell ()
  "Copy the logical Markdown table cell at point to the kill ring.
Remove renderer padding, borders, and text properties.  Preserve the complete
logical value of a wrapped cell."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--copy 'cell))

(defun emacsvox-agent-shell-table-copy-row ()
  "Copy the logical Markdown table row at point to the kill ring.
Separate cells with tabs and omit Markdown separator syntax."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--copy 'row))

(defun emacsvox-agent-shell-table-copy-column ()
  "Copy the logical Markdown table column at point to the kill ring.
Separate cells with newlines and omit Markdown separator syntax."
  (interactive)
  (emacsvox-agent-shell--table-read #'emacsvox-table-reader--copy 'column))

(defun emacsvox-agent-shell--table-cell-position (cell row column)
  "Return the rendered position for ROW and COLUMN relative to CELL.
Return nil when that logical cell does not exist."
  (let* ((rows (plist-get cell :rows))
         (region (emacsvox-agent-shell--markdown-table-region-at-point))
         (starts
          (and region
               (emacsvox-agent-shell--markdown-table-cell-starts region)))
         (target-row (nth row rows)))
    (when (and target-row (<= 0 column) (< column (length target-row)))
      (nth (+ column
              (apply #'+ (mapcar #'length (seq-take rows row))))
           starts))))

(defun emacsvox-agent-shell--table-boundary-feedback (message)
  "Play a boundary cue and speak MESSAGE."
  (emacsvox-agent-shell--submit-text-feedback
   message
   (emacsvox-agent-shell--presentation-facts
    'agent-table 'boundary-entered)
   'navigation 'warn-user))

(defun emacsvox-agent-shell--table-exit-destination (region direction)
  "Delegate table exit-destination to the shared reader."
  (let ((emacsvox-table-reader-titles emacsvox-agent-shell-table-titles)
        (emacsvox-table-reader-data-position
         emacsvox-agent-shell-table-data-position))
    (emacsvox-table-reader--exit-destination region direction)))

(defun emacsvox-agent-shell--table-exit (direction)
  "Leave the rendered table at point in DIRECTION and speak the destination."
  (if-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
            (destination
             (emacsvox-agent-shell--table-exit-destination region direction)))
      (progn
        (goto-char destination)
        (emacsvox-agent-shell--table-track-region nil)
        (setq emacsvox-agent-shell--table-navigation-active nil
              emacsvox-agent-shell--table-navigation-table-start nil)
        (let ((line
               (string-trim
                (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position)))))
          (emacsvox-agent-shell--submit-text-feedback
           (format "%s table.%s"
                   (if (eq direction 'backward) "Before" "After")
                   (if (string-empty-p line) "" (concat " " line)))
           (emacsvox-agent-shell--presentation-facts
            'agent-table 'agent-table-exited)
           'navigation 'close-object)))
    (emacsvox-agent-shell--table-boundary-feedback
     (format "No content %s table."
             (if (eq direction 'backward) "before" "after")))))

(defun emacsvox-agent-shell-table-exit-backward ()
  "Leave the current Markdown table and move to preceding content."
  (interactive)
  (emacsvox-agent-shell--table-exit 'backward))

(defun emacsvox-agent-shell-table-exit-forward ()
  "Leave the current Markdown table and move to following content."
  (interactive)
  (emacsvox-agent-shell--table-exit 'forward))

(defun emacsvox-agent-shell--table-move (row-delta column-delta &optional cell-only)
  "Move by ROW-DELTA and COLUMN-DELTA in the logical table at point.
When CELL-ONLY is non-nil, read only the destination cell after row movement."
  (emacsvox-agent-shell--table-read
   #'emacsvox-table-reader--move row-delta column-delta cell-only
   #'emacsvox-agent-shell--table-exit))

(defun emacsvox-agent-shell-table-next-column (&optional count)
  "Move COUNT columns right in the current logical Markdown table row."
  (interactive "p")
  (emacsvox-agent-shell--table-move 0 (or count 1)))

(defun emacsvox-agent-shell-table-previous-column (&optional count)
  "Move COUNT columns left in the current logical Markdown table row."
  (interactive "p")
  (emacsvox-agent-shell--table-move 0 (- (or count 1))))

(defun emacsvox-agent-shell-table-next-row (&optional count)
  "Move COUNT logical Markdown table rows down, retaining the column."
  (interactive "p")
  (emacsvox-agent-shell--table-move (or count 1) 0))

(defun emacsvox-agent-shell-table-previous-row (&optional count)
  "Move COUNT logical Markdown table rows up, retaining the column."
  (interactive "p")
  (emacsvox-agent-shell--table-move (- (or count 1)) 0))

(defun emacsvox-agent-shell-table-next-row-cell (&optional count)
  "Move COUNT logical table rows down and speak the destination cell.
Retain the current column and use the current table title settings."
  (interactive "p")
  (emacsvox-agent-shell--table-move (or count 1) 0 t))

(defun emacsvox-agent-shell-table-previous-row-cell (&optional count)
  "Move COUNT logical table rows up and speak the destination cell.
Retain the current column and use the current table title settings."
  (interactive "p")
  (emacsvox-agent-shell--table-move (- (or count 1)) 0 t))

(defvar emacsvox-agent-shell--table-navigation-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<down>") #'emacsvox-agent-shell--table-plain-next-row)
    (define-key map (kbd "<up>") #'emacsvox-agent-shell--table-plain-previous-row)
    (define-key map (kbd "M-<up>")
                #'emacsvox-agent-shell-table-exit-backward)
    (define-key map (kbd "M-<down>")
                #'emacsvox-agent-shell-table-exit-forward)
    (define-key map (kbd "r") #'emacsvox-agent-shell-table-speak-row)
    (define-key map (kbd "c") #'emacsvox-agent-shell-table-speak-column)
    (define-key map (kbd "SPC") #'emacsvox-agent-shell-table-speak-cell)
    (define-key map (kbd ".") #'emacsvox-agent-shell-table-speak-context)
    (define-key map (kbd "=") #'emacsvox-agent-shell-table-speak-dimensions)
    (define-key map (kbd "w") #'emacsvox-agent-shell-table-copy-cell)
    (define-key map (kbd "a") #'emacsvox-table-settings)
    (define-key map (kbd "q") #'emacsvox-agent-shell--table-leave)
    map)
  "Contextual keymap active while point is in a rendered Markdown table.")

(defun emacsvox-agent-shell--table-plain-next-row (count)
  "Move COUNT rows with the selected plain-arrow speech."
  (interactive "p")
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (emacsvox-agent-shell--table-move count 0
     (eq (emacsvox-table-reader--preference 'movement-speech) 'cell))))
(defun emacsvox-agent-shell--table-plain-previous-row (count)
  "Move COUNT rows backwards with the selected plain-arrow speech."
  (interactive "p")
  (emacsvox-agent-shell--table-plain-next-row (- count)))

(defun emacsvox-agent-shell--table-entry-text (cell)
  "Return the selected entry detail for rendered CELL."
  (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
    (concat
     (if (eq (emacsvox-table-reader--preference 'entry-detail) 'full)
         (concat (emacsvox-agent-shell--table-dimensions-speech cell) " ")
       "Table. ")
     (emacsvox-agent-shell--table-cell-speech cell))))

(defun emacsvox-agent-shell--table-leave ()
  "Leave table reading in place until explicit entry or a visit through prose.
In a viewport, q now resumes its ordinary bury-buffer action."
  (interactive)
  (setq emacsvox-table-reader--suspended t
        emacsvox-table-reader--last-titles nil
        emacsvox-agent-shell--table-navigation-active nil)
  (emacsvox-agent-shell--submit-text-feedback
   "Table reading off."
   (emacsvox-agent-shell--presentation-facts 'agent-table 'agent-table-exited)
   'navigation 'close-object))

(defun emacsvox-agent-shell--table-enter (cell &optional quiet)
  "Enter rendered CELL with existing host keys; QUIET defers entry speech."
  (emacsvox-agent-shell--table-navigation-setup)
  (setq emacsvox-table-reader--suspended nil
        emacsvox-table-reader--last-titles nil
        emacsvox-agent-shell--table-navigation-active t
        emacsvox-agent-shell--table-navigation-table-start
        (car (plist-get cell :region)))
  (emacsvox-agent-shell--table-track-region (plist-get cell :region))
  (unless quiet (emacsvox-agent-shell--table-navigation-entry-feedback 'forward)))

(defun emacsvox-agent-shell--table-toggle (arg)
  "Toggle the rendered reader, or enable it when ARG is positive."
  (if (if (null arg) (not emacsvox-agent-shell--table-navigation-active)
        (> (prefix-numeric-value arg) 0))
      (emacsvox-agent-shell--table-enter
       (or (emacsvox-agent-shell--table-snapshot)
           (user-error "Not in a rendered Markdown table")))
    (emacsvox-agent-shell--table-leave)))

(defun emacsvox-agent-shell--table-enter-move (rows columns)
  "Enter a rendered table and move ROWS and COLUMNS with one announcement."
  (emacsvox-agent-shell--table-enter
   (or (emacsvox-agent-shell--table-snapshot)
       (user-error "Not in a rendered Markdown table")) t)
  (let ((emacsvox-table-reader--entering t))
    (emacsvox-agent-shell--table-move rows columns t)))

(dolist (entry '((emacsvox-agent-shell--table-enter-down 1 0)
                 (emacsvox-agent-shell--table-enter-up -1 0)
                 (emacsvox-agent-shell--table-enter-left 0 -1)
                 (emacsvox-agent-shell--table-enter-right 0 1)))
  (let ((rows (nth 1 entry)) (columns (nth 2 entry)))
    (defalias (car entry)
      (lambda (count)
        "Enter table reading and move COUNT cells in this direction."
        (interactive "p")
        (emacsvox-agent-shell--table-enter-move (* count rows) (* count columns))))))

(defun emacsvox-agent-shell--install-table-entry-bindings ()
  "Install conditional table entry, including after speech controls refresh."
  (dolist (binding '(("C-M-<down>" emacsvox-agent-shell--table-enter-down t)
                   ("C-M-<up>" emacsvox-agent-shell--table-enter-up t)
                   ("C-M-<left>" emacsvox-agent-shell--table-enter-left nil)
                   ("C-M-<right>" emacsvox-agent-shell--table-enter-right nil)))
  (let ((vertical (nth 2 binding)))
    (define-key emacsvox-agent-shell--speech-control-map (kbd (car binding))
      `(menu-item "Table reading" ,(cadr binding) :filter
                  ,(lambda (command)
                     (if (emacsvox-agent-shell--table-snapshot) command
                       (when vertical #'ignore))))))))

(defun emacsvox-agent-shell--install-table-column-bindings ()
  "Keep character arrows and modified table keys current across reloads."
  (dolist (binding '(("C-M-<up>" . emacsvox-agent-shell-table-previous-row-cell)
                     ("C-M-<down>" . emacsvox-agent-shell-table-next-row-cell)
                     ("<left>" . left-char)
                     ("<right>" . right-char)
                     ("C-M-<left>" . emacsvox-agent-shell-table-previous-column)
                     ("C-M-<right>" . emacsvox-agent-shell-table-next-column)))
    (define-key emacsvox-agent-shell--table-navigation-map
                (kbd (car binding)) (cdr binding))))

(defun emacsvox-agent-shell--install-table-copy-bindings ()
  "Install reload-safe table copying keys in the contextual table map."
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "k") #'emacsvox-agent-shell-table-copy-cell)
    (define-key map (kbd "r") #'emacsvox-agent-shell-table-copy-row)
    (define-key map (kbd "c") #'emacsvox-agent-shell-table-copy-column)
    (define-key emacsvox-agent-shell--table-navigation-map (kbd "k") map)))

(defun emacsvox-agent-shell--table-navigation-entry-feedback (direction)
  "Announce entry at point, falling back to table edge in DIRECTION."
  (if-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
            (cell (emacsvox-agent-shell--table-snapshot)))
      (progn
        (setq emacsvox-table-reader--last-titles nil)
        (emacsvox-agent-shell--table-track-region region)
        (setq emacsvox-agent-shell--table-navigation-active t
              emacsvox-agent-shell--table-navigation-table-start
              (car region))
        (emacsvox-agent-shell--submit-text-feedback
         (emacsvox-agent-shell--table-entry-text cell)
         (emacsvox-agent-shell--presentation-facts
          'agent-table 'agent-table-entered)
         'navigation 'open-object))
    (emacsvox-agent-shell--table-entry-feedback direction)))

(defun emacsvox-agent-shell--table-navigation-pre-command ()
  "Remember point before a possible contextual table entry."
  (setq emacsvox-agent-shell--table-navigation-origin (point))
  (emacsvox-table-reader--before-command))

(defun emacsvox-agent-shell--table-readable-region ()
  "Return a rendered region only while its logical mapping is usable.
At a leading table border, validate from the first navigable cell."
  (when-let* ((region (emacsvox-agent-shell--markdown-table-region-at-point)))
    (save-excursion
      (when-let* ((start (car (emacsvox-agent-shell--markdown-table-cell-starts region))))
        (goto-char start)
        (when (emacsvox-agent-shell--table-snapshot) region)))))

(defun emacsvox-agent-shell--table-track-region (region)
  "Track rendered REGION through edits, releasing old markers first."
  (when emacsvox-agent-shell--table-navigation-region
    (set-marker (car emacsvox-agent-shell--table-navigation-region) nil)
    (set-marker (cdr emacsvox-agent-shell--table-navigation-region) nil))
  (setq emacsvox-agent-shell--table-navigation-region
        (when region
          (cons (copy-marker (car region)) (copy-marker (cdr region) t)))))

(defun emacsvox-agent-shell--table-navigation-invalidate (begin end _old-length)
  "Suspend table keys when the changed BEGIN..END range affects this table.
Streaming elsewhere in the transcript must not interrupt table navigation."
  (when emacsvox-agent-shell--table-navigation-active
    (let ((region emacsvox-agent-shell--table-navigation-region))
      (when (or (not region)
                (and (<= begin (cdr region)) (>= end (car region))))
        (setq emacsvox-agent-shell--table-navigation-active nil)))))

(defun emacsvox-agent-shell--table-navigation-post-command ()
  "Track table entry and toggle the contextual table keymap."
  (let* ((region (emacsvox-agent-shell--table-readable-region))
         (table-start (and region (car region))))
    (cond
     ((not region)
      ;; A redraw can temporarily remove the mapping.  Only navigation to
      ;; prose releases a deliberate quit, never a render or text edit.
      (when (and emacsvox-agent-shell--table-navigation-origin
                 (/= (point) emacsvox-agent-shell--table-navigation-origin)
                 (or (null emacsvox-table-reader--command-tick)
                     (= emacsvox-table-reader--command-tick
                        (buffer-chars-modified-tick)))
                 (not (get-text-property (point) 'agent-shell-markdown-table-source)))
        (setq emacsvox-table-reader--suspended nil))
      (emacsvox-agent-shell--table-track-region nil)
      (setq emacsvox-agent-shell--table-navigation-active nil
            emacsvox-agent-shell--table-navigation-table-start nil))
     ((or emacsvox-table-reader--suspended
          (and (not emacsvox-agent-shell--table-navigation-active)
               (not (let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
                      (eq (emacsvox-table-reader--preference 'activation) 'automatic)))))
      (setq emacsvox-agent-shell--table-navigation-active nil))
     ((not (equal table-start
                  emacsvox-agent-shell--table-navigation-table-start))
      (setq emacsvox-agent-shell--table-navigation-active t)
      (emacsvox-agent-shell--table-navigation-entry-feedback
       (if (and emacsvox-agent-shell--table-navigation-origin
                (< (point) emacsvox-agent-shell--table-navigation-origin))
           'backward
         'forward)))
     (t
      (emacsvox-agent-shell--table-track-region region)
      (setq emacsvox-agent-shell--table-navigation-active t)))))

(defun emacsvox-agent-shell--table-navigation-setup ()
  "Install contextual Markdown table navigation in the current buffer."
  (unless (or emacsvox-agent-shell--table-navigation-owns-aural-module-p
              (and (local-variable-p 'emacsvox-aural-module)
                   (eq emacsvox-aural-module 'agent-shell)))
    (setq emacsvox-agent-shell--table-navigation-saved-aural-module
          (cons (local-variable-p 'emacsvox-aural-module)
                emacsvox-aural-module)
          emacsvox-agent-shell--table-navigation-owns-aural-module-p t)
    (setq-local emacsvox-aural-module 'agent-shell))
  (setq emacsvox-agent-shell--speech-control-active t)
  (emacsvox-agent-shell--vertical-toggle-hint-setup)
  (add-hook 'pre-command-hook
            #'emacsvox-agent-shell--table-navigation-pre-command nil t)
  (add-hook 'post-command-hook
            #'emacsvox-agent-shell--table-navigation-post-command nil t)
  (add-hook 'after-change-functions
            #'emacsvox-agent-shell--table-navigation-invalidate nil t)
  (add-hook 'kill-buffer-hook
            #'emacsvox-agent-shell--table-navigation-cleanup nil t)
  (add-hook 'change-major-mode-hook
            #'emacsvox-agent-shell--table-navigation-cleanup nil t)
  (if-let* (((not emacsvox-table-reader--suspended))
            ((let ((emacsvox-table-reader--preference-mode 'agent-shell-mode))
               (eq (emacsvox-table-reader--preference 'activation) 'automatic)))
            (region (emacsvox-agent-shell--table-readable-region)))
      (progn
        (emacsvox-agent-shell--table-track-region region)
        (setq emacsvox-agent-shell--table-navigation-active t
              emacsvox-agent-shell--table-navigation-table-start (car region)))
    (emacsvox-agent-shell--table-track-region nil)
    (setq emacsvox-agent-shell--table-navigation-active nil
          emacsvox-agent-shell--table-navigation-table-start nil)))

(defun emacsvox-agent-shell--table-navigation-cleanup ()
  "Remove contextual Markdown table navigation from the current buffer."
  (emacsvox-agent-shell--table-track-region nil)
  (emacsvox-agent-shell--vertical-toggle-hint-cleanup)
  (setq emacsvox-agent-shell--speech-control-active nil
        emacsvox-agent-shell--table-navigation-active nil
        emacsvox-agent-shell--table-navigation-table-start nil
        emacsvox-agent-shell--table-navigation-origin nil)
  (remove-hook 'pre-command-hook
               #'emacsvox-agent-shell--table-navigation-pre-command t)
  (remove-hook 'post-command-hook
               #'emacsvox-agent-shell--table-navigation-post-command t)
  (remove-hook 'after-change-functions
               #'emacsvox-agent-shell--table-navigation-invalidate t)
  (remove-hook 'kill-buffer-hook
               #'emacsvox-agent-shell--table-navigation-cleanup t)
  (remove-hook 'change-major-mode-hook
               #'emacsvox-agent-shell--table-navigation-cleanup t)
  (when emacsvox-agent-shell--table-navigation-owns-aural-module-p
    (when (and (local-variable-p 'emacsvox-aural-module)
               (eq emacsvox-aural-module 'agent-shell))
      (if (car emacsvox-agent-shell--table-navigation-saved-aural-module)
          (setq-local
           emacsvox-aural-module
           (cdr emacsvox-agent-shell--table-navigation-saved-aural-module))
        (kill-local-variable 'emacsvox-aural-module)))
    (setq emacsvox-agent-shell--table-navigation-owns-aural-module-p nil
          emacsvox-agent-shell--table-navigation-saved-aural-module nil)))

(defun emacsvox-agent-shell--table-settings-speech ()
  "Return a complete spoken summary of the table speech settings."
  (format "Table speech: %s; column titles %s; row titles %s."
          (if (eq emacsvox-agent-shell-table-data-position 'first)
              "data first"
            "titles first")
          (if (memq 'column emacsvox-agent-shell-table-titles) "on" "off")
          (if (memq 'row emacsvox-agent-shell-table-titles) "on" "off")))

(defun emacsvox-agent-shell--toggle-table-title (title)
  "Toggle table TITLE and retain canonical column, row ordering."
  (let ((titles
         (if (memq title emacsvox-agent-shell-table-titles)
             (remove title emacsvox-agent-shell-table-titles)
           (cons title emacsvox-agent-shell-table-titles))))
    (setq emacsvox-agent-shell-table-titles
          (seq-filter (lambda (candidate) (memq candidate titles))
                      '(column row)))))

(defun emacsvox-agent-shell-table-select-speaking-method ()
  "Interactively change automatic Markdown table cell speech.
Press c to toggle column titles, r to toggle row titles, or o to
switch between data-first and title-first ordering.  Speak the complete
resulting configuration after the change."
  (interactive)
  (pcase
      (read-char-choice
       "Toggle table speech: c column titles, r row titles, o order: "
       '(?c ?r ?o))
    (?c (emacsvox-agent-shell--toggle-table-title 'column))
    (?r (emacsvox-agent-shell--toggle-table-title 'row))
    (?o (setq emacsvox-agent-shell-table-data-position
              (if (eq emacsvox-agent-shell-table-data-position 'first)
                  'last
                'first))))
  (emacsvox-agent-shell--submit-text-feedback
   (emacsvox-agent-shell--table-settings-speech)
   (emacsvox-agent-shell--presentation-facts
    'agent-table 'agent-setting-changed)
   'state-change 'button))

(defun emacsvox-agent-shell--install-table-adapter ()
  "Register rendered tables after the integration's speech controls exist."
  (emacsvox-agent-shell--install-table-entry-bindings)
  (emacsvox-agent-shell--install-table-column-bindings)
  (emacsvox-agent-shell--install-table-copy-bindings)
  (dolist (mode '(agent-shell-mode agent-shell-viewport-view-mode))
    (setf (alist-get mode emacsvox-table-reader--adapters)
          (list #'emacsvox-agent-shell--table-snapshot #'emacsvox-agent-shell--table-submit
                nil (list :enter #'emacsvox-agent-shell--table-enter
                          :toggle #'emacsvox-agent-shell--table-toggle))))
  (add-to-list 'minor-mode-alist '(emacsvox-agent-shell--table-navigation-active " Table"))
  (unless (assq 'emacsvox-agent-shell--table-navigation-active
                minor-mode-map-alist)
    (push (cons 'emacsvox-agent-shell--table-navigation-active
                emacsvox-agent-shell--table-navigation-map)
          minor-mode-map-alist)))

(provide 'emacsvox-agent-shell-tables)

;;; emacsvox-agent-shell-tables.el ends here
