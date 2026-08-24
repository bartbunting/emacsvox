;;; emacsvox-eat-review.el --- Frozen EAT screen review  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Keywords: Emacsvox, Audio Desktop, eat

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
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

;;; Commentary:
;; Frozen, read-only review and explicit inspection for EAT screen state.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

(require 'emacsvox-eat-input)
(defvar emacsvox-eat-review-map)

;;;  Snapshot Review:

(defvar-local emacsvox-eat-review--source-buffer nil
  "Live EAT buffer from which this frozen review was explicitly copied.")

(defvar-local emacsvox-eat-review--snapshot nil
  "Immutable concealed-redacted EAT screen copied for this review buffer.")

(defvar-local emacsvox-eat-review--completion nil
  "Immutable completion/help presentation copied for this review buffer.")

(defvar-local emacsvox-eat-review--focus nil
  "Immutable conservative focus inference copied for this review buffer.")

(defvar-local emacsvox-eat-review--status nil
  "Immutable terminal status copied for this review buffer.")

(defvar-local emacsvox-eat-review--metadata nil
  "Immutable sanitized terminal metadata change copied for this review buffer.")

(defvar-local emacsvox-eat-review--view 'screen
  "Kind of frozen content currently rendered in this review buffer.")

(defvar-local emacsvox-eat-review--navigation-delivery-key nil
  "Replacement key used to interrupt stale frozen-row announcements.")

(defun emacsvox-eat--kill-review-buffer ()
  "Kill and forget the current EAT terminal's content-bearing review buffer."
  (when (buffer-live-p emacsvox-eat--review-buffer)
    (let ((review emacsvox-eat--review-buffer))
      (setq emacsvox-eat--review-buffer nil)
      (kill-buffer review)))
  (setq emacsvox-eat--review-buffer nil))

(defun emacsvox-eat-review--forget-source ()
  "Clear the source terminal's reference when this review buffer is killed."
  (let ((source emacsvox-eat-review--source-buffer)
        (review (current-buffer)))
    (setq emacsvox-eat-review--source-buffer nil)
    (when (buffer-live-p source)
      (with-current-buffer source
        (when (eq emacsvox-eat--review-buffer review)
          (setq emacsvox-eat--review-buffer nil))))))

(defun emacsvox-eat-review--copy-data (value)
  "Return a deep mutable-container and string copy of data-only VALUE."
  (cond
   ((stringp value) (copy-sequence value))
   ((consp value)
    (cons
     (emacsvox-eat-review--copy-data (car value))
     (emacsvox-eat-review--copy-data (cdr value))))
   ((vectorp value)
    (apply
     #'vector
     (mapcar #'emacsvox-eat-review--copy-data (append value nil))))
   (t value)))

(defun emacsvox-eat--ensure-review-context ()
  "Require a reviewable EAT terminal as the current buffer."
  (unless (emacsvox-eat--terminal-buffer-p)
    (user-error "This is not an EAT terminal buffer"))
  (when emacsvox-eat--secure-input-active-p
    (user-error "Terminal review is unavailable during secure input")))

(defun emacsvox-eat--review-facts (&optional operation)
  "Return semantic facts for explicit terminal review of OPERATION."
  (append
   '(:role command-output :command-interaction-kind shell)
   (when operation (list :command-operation operation))))

(defun emacsvox-eat--submit-review (content &optional operation)
  "Submit retained terminal CONTENT for explicit OPERATION review."
  (emacsvox-eat--submit
   content (emacsvox-eat--review-facts operation) 'inspection))

(defun emacsvox-eat--review-state-value (terminal-variable review-variable)
  "Return retained TERMINAL-VARIABLE or frozen REVIEW-VARIABLE for review."
  (cond
   ((derived-mode-p 'emacsvox-eat-review-mode)
    (symbol-value review-variable))
   ((emacsvox-eat--terminal-buffer-p)
    (emacsvox-eat--ensure-review-context)
    (symbol-value terminal-variable))
   (t (user-error "This is not an EAT terminal or frozen review buffer"))))

(defun emacsvox-eat-speak-retained-status ()
  "Speak the latest retained or explicitly frozen terminal status row."
  (interactive)
  (if-let* ((status
             (emacsvox-eat--review-state-value
              'emacsvox-eat--last-status-text
              'emacsvox-eat-review--status))
            (content (emacsvox-eat--bounded-review-output (list status))))
      (emacsvox-eat--submit-review
       (concat "Retained terminal status: " content) 'output-navigation)
    (emacsvox-eat--submit-review
     "No terminal status is retained" 'output-navigation)))

(defun emacsvox-eat--retained-metadata-lines (metadata)
  "Return explicit-review lines for sanitized retained METADATA."
  (let (lines)
    (when (plist-get metadata :title-changed)
      (push
       (if-let* ((title (plist-get metadata :title))
                 ((not (string-empty-p title))))
           (format "Terminal title: %s"
                   (emacsvox-eat--sanitize-output-row title))
         "Terminal title cleared")
       lines))
    (when (plist-get metadata :cwd-changed)
      (push
       (if-let* ((cwd (plist-get metadata :cwd))
                 ((not (string-empty-p cwd))))
           (format "Working directory: %s"
                   (emacsvox-eat--sanitize-output-row cwd))
         "Working directory unavailable")
       lines))
    (nreverse lines)))

(defun emacsvox-eat-speak-retained-metadata ()
  "Speak the latest retained or explicitly frozen title/directory change."
  (interactive)
  (let* ((metadata
          (emacsvox-eat--review-state-value
           'emacsvox-eat--last-metadata-change
           'emacsvox-eat-review--metadata))
         (lines (and metadata (emacsvox-eat--retained-metadata-lines metadata)))
         (content (and lines (emacsvox-eat--bounded-review-output lines))))
    (if content
        (emacsvox-eat--submit-review content 'output-navigation)
      (emacsvox-eat--submit-review
       "No terminal metadata change is retained" 'output-navigation))))

(defun emacsvox-eat--bounded-review-output (rows)
  "Return a bounded explicit-review representation of retained ROWS."
  (let* ((total-lines (length rows))
         (shown-count (min total-lines emacsvox-eat--maximum-review-lines))
         (shown-rows
          (mapcar
           #'emacsvox-eat--sanitize-output-row
           (emacsvox-eat--list-slice rows 0 shown-count)))
         (text (string-join shown-rows "\n"))
         (characters-truncated
          (> (length text) emacsvox-eat--maximum-review-characters)))
    (when characters-truncated
      (setq text
            (concat
             (substring text 0 emacsvox-eat--maximum-review-characters)
             " … review truncated")))
    (when (> total-lines shown-count)
      (setq text
            (concat
             text "\n"
             (format "%d additional retained rows not spoken"
                     (- total-lines shown-count)))))
    (unless (string-empty-p (string-trim text)) text)))

(defun emacsvox-eat--row-range-label (start end)
  "Return a human one-based row label for zero-based START through END."
  (if (= start end)
      (format "row %d" (1+ start))
    (format "rows %d through %d" (1+ start) (1+ end))))

(defun emacsvox-eat-speak-current-row ()
  "Speak the terminal cursor row from the latest retained screen snapshot."
  (interactive)
  (emacsvox-eat--ensure-review-context)
  (let* ((snapshot emacsvox-eat--screen-snapshot)
         (rows (plist-get snapshot :rows))
         (row (plist-get snapshot :cursor-row)))
    (cond
     ((null snapshot)
      (emacsvox-eat--submit-review
       "No terminal screen snapshot is available" 'output-navigation))
     ((not (and (integerp row) (< -1 row (length rows))))
      (emacsvox-eat--submit-review
       "The retained terminal screen has no cursor row"
       'output-navigation))
     (t
      (let ((text
             (emacsvox-eat--sanitize-output-row (nth row rows))))
        (emacsvox-eat--submit-review
         (if (string-empty-p (string-trim text))
             (format "Current terminal row %d of %d is blank"
                     (1+ row) (length rows))
           (format "Current terminal row %d of %d: %s"
                   (1+ row) (length rows) text))
         'output-navigation))))))

(defun emacsvox-eat--style-change-row-label (diff snapshot)
  "Return the retained row label for a style-only DIFF at SNAPSHOT."
  (when-let* ((change (plist-get diff :style-change))
              (text (plist-get snapshot :text))
              ((stringp text))
              (start (plist-get change :start))
              (new-end (plist-get change :new-end))
              ((integerp start))
              ((integerp new-end)))
    (let* ((starts (emacsvox-eat--row-start-offsets text))
           (first (emacsvox-eat--row-for-offset starts start))
           (last
            (emacsvox-eat--row-for-offset
             starts (max start (1- new-end)))))
      (emacsvox-eat--row-range-label first last))))

(defun emacsvox-eat--last-change-description (diff snapshot)
  "Return an explicit-review description of retained DIFF at SNAPSHOT."
  (cond
   ((plist-get diff :alternate-screen-changed)
    (if (plist-get snapshot :alternate-screen)
        "The last terminal change entered an application screen"
      "The last terminal change returned to the main screen"))
   ((plist-get diff :generation-changed)
    "The last terminal change started a new display generation")
   ((plist-get diff :prompt-status-changed)
    (if-let* ((status
               (emacsvox-eat--prompt-status-text
                (plist-get diff :new-prompt-status))))
        (format "The terminal prompt reports: %s" status)
      "The terminal prompt status is no longer available"))
   ((plist-get diff :text-changed)
    (let* ((change (plist-get diff :row-change))
           (start (or (plist-get change :start) 0))
           (rows (plist-get change :new-rows))
           (end (max start (+ start (length rows) -1)))
           (label (emacsvox-eat--row-range-label start end))
           (content (emacsvox-eat--bounded-review-output rows)))
      (cond
       (content
        (format "Last terminal text change, %s:\n%s" label content))
       (rows
        (format "The last terminal text change left %s blank" label))
       (t
        (format "The last terminal text change removed content at %s"
                label)))))
   ((plist-get diff :style-changed)
    (if-let* ((label
               (emacsvox-eat--style-change-row-label diff snapshot)))
        (format "The last terminal change affected styling on %s" label)
      "The last terminal change affected terminal styling"))
   ((plist-get diff :cursor-moved)
    (let ((row (plist-get snapshot :cursor-row))
          (column (plist-get snapshot :cursor-column)))
      (if (and (integerp row) (integerp column))
          (format "The terminal cursor last moved to row %d, column %d"
                  (1+ row) (1+ column))
        "The last terminal change moved the cursor")))
   ((plist-get diff :size-changed)
    (if-let* ((size (plist-get snapshot :size)))
        (format "The terminal was resized to %d columns by %d rows"
                (car size) (cdr size))
      "The terminal size changed"))
   ((or (plist-get diff :title-changed) (plist-get diff :cwd-changed))
    (cond
     ((and (plist-get diff :title-changed) (plist-get diff :cwd-changed))
      "The terminal title and working directory changed")
     ((plist-get diff :title-changed) "The terminal title changed")
     (t "The terminal working directory changed")))
   ((plist-get diff :cursor-type-changed)
    "The terminal cursor style changed")
   (t "No classified terminal screen change is retained")))

(defun emacsvox-eat-speak-last-change ()
  "Speak the most recent quiesced terminal change from retained state."
  (interactive)
  (emacsvox-eat--ensure-review-context)
  (if (and emacsvox-eat--last-screen-diff
           emacsvox-eat--last-changed-screen)
      (emacsvox-eat--submit-review
       (emacsvox-eat--last-change-description
        emacsvox-eat--last-screen-diff
        emacsvox-eat--last-changed-screen)
       'output-navigation)
    (emacsvox-eat--submit-review
     "No terminal screen change is retained" 'output-navigation)))

(defun emacsvox-eat-speak-likely-focus ()
  "Speak the latest conservative terminal focus inference for review."
  (interactive)
  (emacsvox-eat--ensure-review-context)
  (if-let* ((focus emacsvox-eat--last-likely-focus)
            (text
             (emacsvox-eat--bounded-focus-text
              (or (plist-get focus :text) ""))))
      (let* ((kind (plist-get focus :kind))
             (confidence (or (plist-get focus :confidence) 'unknown))
             (row (plist-get focus :row-start))
             (label
              (if (eq kind 'highlight)
                  "Likely terminal highlight"
                "Likely terminal cursor row")))
        (emacsvox-eat--submit-review
         (format "%s, %s confidence%s: %s"
                 label confidence
                 (if (integerp row)
                     (format ", row %d" (1+ row))
                   "")
                 text)
         'output-navigation))
    (emacsvox-eat--submit-review
     "No likely terminal focus is retained" 'output-navigation)))

(defun emacsvox-eat-speak-completion-output ()
  "Speak the latest retained terminal candidate or help-row presentation."
  (interactive)
  (emacsvox-eat--ensure-review-context)
  (if-let* ((completion emacsvox-eat--last-completion-output))
      (let* ((items-p (eq (plist-get completion :layout) 'items))
             (count
              (or (and items-p (plist-get completion :item-count))
                  (plist-get completion :row-count)
                  (length (plist-get completion :rows))))
             (noun (if items-p "candidate" "completion row"))
             (visible-p
              (eq (plist-get completion :confidence) 'unanchored))
             (heading
              (format "%s%d%s %s%s retained"
                      (if visible-p "At least " "")
                      count
                      (if visible-p " visible" "")
                      noun
                      (if (= count 1) "" "s")))
             (content
              (emacsvox-eat--bounded-review-output
               (plist-get completion :rows))))
        (emacsvox-eat--submit-review
         (if content (concat heading ":\n" content) heading)
         'completion))
    (emacsvox-eat--submit-review
     "No terminal completion output is retained" 'completion)))

(defun emacsvox-eat-speak-visible-screen ()
  "Speak a bounded frozen copy of the latest retained visible EAT screen."
  (interactive)
  (emacsvox-eat--ensure-review-context)
  (if-let* ((snapshot emacsvox-eat--screen-snapshot))
      (let* ((rows (plist-get snapshot :rows))
             (count (length rows))
             (cursor-row (plist-get snapshot :cursor-row))
             (heading
              (format "Frozen %s terminal screen, %d row%s%s"
                      (if (plist-get snapshot :alternate-screen)
                          "application"
                        "main")
                      count (if (= count 1) "" "s")
                      (if (integerp cursor-row)
                          (format ", cursor row %d" (1+ cursor-row))
                        ", no cursor row")))
             (content (emacsvox-eat--bounded-review-output rows)))
        (emacsvox-eat--submit-review
         (if content
             (concat heading ":\n" content)
           (concat heading "; screen is blank"))
         'output-navigation))
    (emacsvox-eat--submit-review
     "No terminal screen snapshot is available" 'output-navigation)))

(defun emacsvox-eat-review--normalized-face-property (normalized)
  "Return an Emacs face property reconstructed from NORMALIZED face data."
  (when normalized
    (let ((faces (copy-sequence (plist-get normalized :faces)))
          attributes)
      (dolist (entry (plist-get normalized :attributes))
        (setq attributes
              (append attributes (list (car entry) (cdr entry)))))
      (cond
       ((and faces attributes) (append faces (list attributes)))
       ((cdr faces) faces)
       ((car faces) (car faces))
       (attributes attributes)))))

(defun emacsvox-eat-review--apply-styles ()
  "Apply normalized frozen screen styles to the current review buffer."
  (let* ((snapshot emacsvox-eat-review--snapshot)
         (text-length (length (or (plist-get snapshot :text) "")))
         (origin (point-min)))
    (dolist (run (plist-get snapshot :styles))
      (let* ((start (+ origin (max 0 (car run))))
             (end (+ origin (min text-length (cadr run))))
             (style (caddr run))
             (face
              (emacsvox-eat-review--normalized-face-property
               (plist-get style :face)))
             (mouse-face
              (emacsvox-eat-review--normalized-face-property
               (plist-get style :mouse-face)))
             properties)
        (when face (setq properties (append properties (list 'face face))))
        (when mouse-face
          (setq properties
                (append properties (list 'mouse-face mouse-face))))
        (when-let* ((traits (plist-get style :traits)))
          (setq properties
                (append
                 properties
                 (list 'emacsvox-eat-style-traits
                       (copy-sequence traits)))))
        (when (and properties (< start end))
          (add-text-properties start end properties))))))

(defun emacsvox-eat-review--rows (&optional view)
  "Return frozen rows for VIEW, defaulting to the current review view."
  (pcase (or view emacsvox-eat-review--view)
    ('completion (plist-get emacsvox-eat-review--completion :rows))
    (_ (plist-get emacsvox-eat-review--snapshot :rows))))

(defun emacsvox-eat-review--render (view)
  "Render immutable terminal VIEW in the current read-only review buffer."
  (let ((rows (emacsvox-eat-review--rows view))
        (cursor-row
         (and (eq view 'screen)
              (plist-get emacsvox-eat-review--snapshot :cursor-row)))
        (focus-start
         (and (eq view 'screen)
              (plist-get emacsvox-eat-review--focus :row-start)))
        (focus-end
         (and (eq view 'screen)
              (plist-get emacsvox-eat-review--focus :row-end)))
        (inhibit-read-only t)
        (inhibit-modification-hooks t))
    (setq emacsvox-eat-review--view view)
    (erase-buffer)
    (cl-loop
     for row in rows
     for index from 0
     do
     (let ((start (point)))
       (insert (emacsvox-eat--sanitize-output-row row) "\n")
       (add-text-properties
        start (point)
        (append
         (list 'emacsvox-eat-review-row index
               'emacsvox-eat-review-view view
               'rear-nonsticky t)
         (when (and (integerp cursor-row) (= index cursor-row))
           '(emacsvox-eat-review-cursor t))
         (when (and (integerp focus-start) (integerp focus-end)
                    (<= focus-start index focus-end))
           (list 'emacsvox-eat-review-focus
                 emacsvox-eat-review--focus))))))
    (when (eq view 'screen) (emacsvox-eat-review--apply-styles))
    (goto-char (point-min))
    (set-buffer-modified-p nil)))

(defun emacsvox-eat-review--row-at-point ()
  "Return the zero-based frozen row represented at point, or nil."
  (get-text-property (line-beginning-position) 'emacsvox-eat-review-row))

(defun emacsvox-eat-review--goto-row (row)
  "Move point to frozen zero-based ROW in the current rendered view."
  (let ((count (length (emacsvox-eat-review--rows))))
    (when (> count 0)
      (goto-char (point-min))
      (forward-line (max 0 (min row (1- count))))
      (emacsvox-eat-review--row-at-point))))

(defun emacsvox-eat-review--current-line-description ()
  "Return a styled spoken description of the frozen row at point."
  (when-let* ((row (emacsvox-eat-review--row-at-point)))
    (let* ((rows (emacsvox-eat-review--rows))
           (text
            (buffer-substring
             (line-beginning-position) (line-end-position)))
           (cursor-p
            (get-text-property
             (line-beginning-position) 'emacsvox-eat-review-cursor))
           (focus
            (get-text-property
             (line-beginning-position) 'emacsvox-eat-review-focus))
           (label
            (if (eq emacsvox-eat-review--view 'completion)
                (format "Completion row %d of %d" (1+ row) (length rows))
              (concat
               (format "Terminal row %d of %d" (1+ row) (length rows))
               (when cursor-p ", captured cursor")
               (when focus
                 (format ", likely focus, %s confidence"
                         (or (plist-get focus :confidence) 'unknown)))))))
      (if (string-empty-p (string-trim text))
          (concat label " is blank")
        (concat label ": " text)))))

(defun emacsvox-eat-review-speak-current-line
    (&optional introduction replaceable-p)
  "Speak the current frozen terminal row after optional INTRODUCTION.
When REPLACEABLE-P is non-nil, interrupt an older row announcement from this
review because only the newly reached row remains useful."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (if-let* ((description
             (emacsvox-eat-review--current-line-description)))
      (let ((content (concat (or introduction "") description))
            (operation
             (if (eq emacsvox-eat-review--view 'completion)
                 'completion
               'output-navigation)))
        (if replaceable-p
            (emacsvox-eat--submit
             content (emacsvox-eat--review-facts operation) 'inspection
             nil 'replaceable emacsvox-eat-review--navigation-delivery-key)
          (emacsvox-eat--submit-review content operation)))
    (emacsvox-eat--submit-review
     "This frozen review view contains no rows" 'output-navigation)))

(defun emacsvox-eat-review--move (delta)
  "Move by DELTA frozen rows and speak the destination."
  (let* ((rows (emacsvox-eat-review--rows))
         (count (length rows))
         (current (or (emacsvox-eat-review--row-at-point) 0))
         (requested (+ current delta))
         (target (max 0 (min requested (1- count))))
         introduction)
    (unless (> count 0) (user-error "This frozen view contains no rows"))
    (when (< requested 0) (setq introduction "First retained row. "))
    (when (>= requested count) (setq introduction "Last retained row. "))
    (emacsvox-eat-review--goto-row target)
    (emacsvox-eat-review-speak-current-line introduction t)))

(defun emacsvox-eat-review-next-line (&optional count)
  "Move forward COUNT frozen terminal rows and speak the destination."
  (interactive "p")
  (emacsvox-eat-review--move (or count 1)))

(defun emacsvox-eat-review-previous-line (&optional count)
  "Move backward COUNT frozen terminal rows and speak the destination."
  (interactive "p")
  (emacsvox-eat-review--move (- (or count 1))))

(defun emacsvox-eat-review-show-screen ()
  "Render the frozen terminal screen and move to its captured cursor row."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (emacsvox-eat-review--render 'screen)
  (emacsvox-eat-review--goto-row
   (or (plist-get emacsvox-eat-review--snapshot :cursor-row) 0))
  (emacsvox-eat-review-speak-current-line "Frozen screen view. "))

(defun emacsvox-eat-review--completion-heading ()
  "Return a count description for the frozen completion presentation."
  (let* ((completion emacsvox-eat-review--completion)
         (items-p (eq (plist-get completion :layout) 'items))
         (count
          (or (and items-p (plist-get completion :item-count))
              (plist-get completion :row-count)
              (length (plist-get completion :rows))))
         (visible-p (eq (plist-get completion :confidence) 'unanchored)))
    (format "%s%d%s retained %s%s. "
            (if visible-p "At least " "")
            count
            (if visible-p " visible" "")
            (if items-p "candidate" "completion row")
            (if (= count 1) "" "s"))))

(defun emacsvox-eat-review-show-completion ()
  "Render and speak the frozen terminal candidate or help-row presentation."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (if (emacsvox-eat-review--rows 'completion)
      (progn
        (emacsvox-eat-review--render 'completion)
        (emacsvox-eat-review--goto-row 0)
        (emacsvox-eat-review-speak-current-line
         (emacsvox-eat-review--completion-heading)))
    (emacsvox-eat--submit-review
     "No terminal completion output was frozen for this review"
     'completion)))

(defun emacsvox-eat-review-goto-cursor ()
  "Return to the frozen screen's captured terminal cursor row."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (if-let* ((row (plist-get emacsvox-eat-review--snapshot :cursor-row))
            ((integerp row)))
      (progn
        (unless (eq emacsvox-eat-review--view 'screen)
          (emacsvox-eat-review--render 'screen))
        (emacsvox-eat-review--goto-row row)
        (emacsvox-eat-review-speak-current-line "Captured cursor. "))
    (emacsvox-eat--submit-review
     "The frozen terminal screen has no cursor row" 'output-navigation)))

(defun emacsvox-eat-review-goto-focus ()
  "Move to the frozen conservative focus row and speak it."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (if-let* ((focus emacsvox-eat-review--focus)
            (row (plist-get focus :row-start))
            ((integerp row))
            ((< -1 row (length (emacsvox-eat-review--rows 'screen)))))
      (progn
        (unless (eq emacsvox-eat-review--view 'screen)
          (emacsvox-eat-review--render 'screen))
        (emacsvox-eat-review--goto-row row)
        (emacsvox-eat-review-speak-current-line "Likely focus. "))
    (emacsvox-eat--submit-review
     "No likely terminal focus was frozen for this review"
     'output-navigation)))

(defun emacsvox-eat-review--styled-regions ()
  "Return nonblank selection-like regions from the frozen screen."
  (seq-filter
   (lambda (region)
     (emacsvox-eat--bounded-focus-text (plist-get region :text)))
   (emacsvox-eat--highlight-regions emacsvox-eat-review--snapshot)))

(defun emacsvox-eat-review--styled-region-at-offset (regions offset)
  "Return the member of REGIONS containing frozen screen OFFSET."
  (seq-find
   (lambda (region)
     (<= (plist-get region :start) offset
         (1- (plist-get region :end))))
   regions))

(defun emacsvox-eat-review--speak-styled-region (region regions)
  "Speak selection-like REGION and its position among REGIONS."
  (let* ((origin (point-min))
         (start (+ origin (plist-get region :start)))
         (end (+ origin (plist-get region :end)))
         (text (string-trim (buffer-substring start end)))
         (bounded
          (if (> (length text) emacsvox-eat--maximum-focus-characters)
              (concat
               (substring text 0 emacsvox-eat--maximum-focus-characters)
               "…")
            text))
         (index (cl-position region regions :test #'eq))
         (row-start (plist-get region :row-start))
         (row-end (plist-get region :row-end)))
    (emacsvox-eat--submit-review
     (concat
      (format "Selection-like styled region %d of %d, %s: "
              (1+ index) (length regions)
              (emacsvox-eat--row-range-label row-start row-end))
      bounded)
     'output-navigation)))

(defun emacsvox-eat-review--move-styled-region (direction)
  "Move to and speak a frozen selection-like region in DIRECTION."
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (unless (eq emacsvox-eat-review--view 'screen)
    (emacsvox-eat-review--render 'screen))
  (let* ((regions (emacsvox-eat-review--styled-regions))
         (offset (- (point) (point-min)))
         (current
          (emacsvox-eat-review--styled-region-at-offset regions offset))
         (anchor (if current (plist-get current :start) offset))
         (region
          (if (eq direction 'next)
              (seq-find
               (lambda (candidate)
                 (if current
                     (> (plist-get candidate :start) anchor)
                   (>= (plist-get candidate :start) anchor)))
               regions)
            (seq-find
             (lambda (candidate)
               (< (plist-get candidate :start) anchor))
             (reverse regions)))))
    (if region
        (progn
          (goto-char (+ (point-min) (plist-get region :start)))
          (emacsvox-eat-review--speak-styled-region region regions))
      (emacsvox-eat--submit-review
       (if (eq direction 'next)
           "No later selection-like styled region is frozen"
         "No earlier selection-like styled region is frozen")
       'output-navigation))))

(defun emacsvox-eat-review-next-styled-region ()
  "Move to and speak the next frozen selection-like styled region."
  (interactive)
  (emacsvox-eat-review--move-styled-region 'next))

(defun emacsvox-eat-review-previous-styled-region ()
  "Move to and speak the previous frozen selection-like styled region."
  (interactive)
  (emacsvox-eat-review--move-styled-region 'previous))

(defun emacsvox-eat-review-speak-view ()
  "Speak a bounded overview of the current immutable review view."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (if-let* ((content
             (emacsvox-eat--bounded-review-output
              (emacsvox-eat-review--rows))))
      (emacsvox-eat--submit-review
       (concat
        (if (eq emacsvox-eat-review--view 'completion)
            (emacsvox-eat-review--completion-heading)
          "Frozen terminal screen. ")
        content)
       (if (eq emacsvox-eat-review--view 'completion)
           'completion
         'output-navigation))
    (emacsvox-eat--submit-review
     "This frozen review view is blank" 'output-navigation)))

(defun emacsvox-eat-review-quit ()
  "Kill the content-bearing frozen EAT review and restore its prior window."
  (interactive)
  (unless (derived-mode-p 'emacsvox-eat-review-mode)
    (user-error "This is not a frozen EAT review buffer"))
  (emacsvox-eat--submit
   "Frozen screen review closed"
   (emacsvox-eat--facts 'command-interaction 'operation-completed)
   'state-change 'close-object 'urgent)
  (quit-window t))

(defvar emacsvox-eat-review-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (dolist
        (binding
         '(("n" . emacsvox-eat-review-next-line)
           ("p" . emacsvox-eat-review-previous-line)
           ("C-n" . emacsvox-eat-review-next-line)
           ("C-p" . emacsvox-eat-review-previous-line)
           ("<down>" . emacsvox-eat-review-next-line)
           ("<up>" . emacsvox-eat-review-previous-line)
           ("SPC" . emacsvox-eat-review-speak-current-line)
           ("RET" . emacsvox-eat-review-speak-current-line)
           ("." . emacsvox-eat-review-speak-current-line)
           ("a" . emacsvox-eat-review-speak-view)
           ("s" . emacsvox-eat-review-show-screen)
           ("c" . emacsvox-eat-review-show-completion)
           ("C" . emacsvox-eat-review-goto-cursor)
           ("h" . emacsvox-eat-review-goto-focus)
           ("]" . emacsvox-eat-review-next-styled-region)
           ("[" . emacsvox-eat-review-previous-styled-region)
           ("t" . emacsvox-eat-speak-retained-status)
           ("i" . emacsvox-eat-speak-retained-metadata)
           ("v" . emacsvox-eat-cycle-verbosity)
           ("m" . emacsvox-eat-toggle-background-monitoring)
           ("?" . describe-mode)
           ("q" . emacsvox-eat-review-quit)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Keymap for immutable EAT screen review buffers.")

(define-derived-mode emacsvox-eat-review-mode special-mode "EAT-Review"
  "Review a frozen concealed-redacted EAT screen without touching its terminal.

The buffer is an explicit immutable copy.  n and p move by terminal row; SPC,
RET, or period speaks the current row; C returns to the captured cursor; h
moves to a retained likely focus; [ and ] move among selection-like styled
regions without treating them as focus; c shows retained completion/help
output; s returns to screen rows; a speaks the bounded current view; t and i
speak frozen status and metadata; v and m control source-terminal feedback
without sending terminal input; and q kills the content-bearing review buffer."
  (setq-local emacsvox-aural-module 'eat)
  (setq-local truncate-lines t)
  (buffer-disable-undo)
  (add-hook 'kill-buffer-hook #'emacsvox-eat-review--forget-source nil t))

(defun emacsvox-eat-review-screen ()
  "Open a read-only review copied from retained EAT screen state.
The command never captures mutable live terminal-buffer text."
  (interactive)
  (emacsvox-eat--ensure-review-context)
  (if (null emacsvox-eat--screen-snapshot)
      (progn
        (emacsvox-eat--submit-review
         "No terminal screen snapshot is available" 'output-navigation)
        nil)
    (let* ((source (current-buffer))
           (snapshot
            (emacsvox-eat-review--copy-data
             emacsvox-eat--screen-snapshot))
           (completion
            (emacsvox-eat-review--copy-data
             emacsvox-eat--last-completion-output))
           (focus
            (emacsvox-eat-review--copy-data
             emacsvox-eat--last-likely-focus))
           (status
            (emacsvox-eat-review--copy-data
             emacsvox-eat--last-status-text))
           (metadata
            (emacsvox-eat-review--copy-data
             emacsvox-eat--last-metadata-change))
           (navigation-delivery-key
            (emacsvox-eat--terminal-delivery-key 'review-navigation))
           (buffer
            (if (buffer-live-p emacsvox-eat--review-buffer)
                emacsvox-eat--review-buffer
              (generate-new-buffer
               (format "*EAT Review: %s*" (buffer-name source))))))
      (setq emacsvox-eat--review-buffer buffer)
      (with-current-buffer buffer
        (emacsvox-eat-review-mode)
        (setq-local emacsvox-eat-review--source-buffer source
                    emacsvox-eat-review--snapshot snapshot
                    emacsvox-eat-review--completion completion
                    emacsvox-eat-review--focus focus
                    emacsvox-eat-review--status status
                    emacsvox-eat-review--metadata metadata
                    emacsvox-eat-review--navigation-delivery-key
                    navigation-delivery-key)
        (emacsvox-eat-review--render 'screen)
        (emacsvox-eat-review--goto-row
         (or (plist-get snapshot :cursor-row) 0)))
      (pop-to-buffer buffer)
      (emacsvox-eat--submit
       (concat
        "Frozen screen review opened. "
        (or (emacsvox-eat-review--current-line-description)
            "The frozen review contains no rows"))
       (emacsvox-eat--facts 'command-interaction 'operation-started)
       'state-change 'open-object 'urgent)
      buffer)))

(define-prefix-command 'emacsvox-eat-review-map)
(define-key emacsvox-eat-review-map (kbd "l")
            #'emacsvox-eat-speak-current-row)
(define-key emacsvox-eat-review-map (kbd "d")
            #'emacsvox-eat-speak-last-change)
(define-key emacsvox-eat-review-map (kbd "h")
            #'emacsvox-eat-speak-likely-focus)
(define-key emacsvox-eat-review-map (kbd "c")
            #'emacsvox-eat-speak-completion-output)
(define-key emacsvox-eat-review-map (kbd "s")
            #'emacsvox-eat-speak-visible-screen)
(define-key emacsvox-eat-review-map (kbd "r")
            #'emacsvox-eat-review-screen)
(define-key emacsvox-eat-review-map (kbd "t")
            #'emacsvox-eat-speak-retained-status)
(define-key emacsvox-eat-review-map (kbd "i")
            #'emacsvox-eat-speak-retained-metadata)
(define-key emacsvox-eat-review-map (kbd "v")
            #'emacsvox-eat-cycle-verbosity)
(define-key emacsvox-eat-review-map (kbd "m")
            #'emacsvox-eat-toggle-background-monitoring)
(define-key emacsvox-keymap (kbd "q") 'emacsvox-eat-review-map)
(provide 'emacsvox-eat-review)
;;; emacsvox-eat-review.el ends here
