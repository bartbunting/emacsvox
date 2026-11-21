;;; emacsvox-tabulated-list.el --- Speech-enable   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop tabulated-list
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
;;; TABULATED-LIST ==  tabulated list mode
;; Speech-enable tabulated lists and provide commands for intelligent
;; spoken output 

;;; Code:

;;; Forward variable declarations:

(defvar tabulated-list-format)

;;   Required modules:

(require 'cl-lib)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'tabulated-list)
(require 'emacsvox-table-reader)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (tabulated-list-fake-header voice-bolden)))

;;;  Interactive Commands:

(defun emacsvox-tabulated-list--cell-facts (empty)
  "Return semantic facts for the current field, including EMPTY state."
  (append
   '(:role field)
   (when empty '(:states (empty)))))

(defun emacsvox-tabulated-list--module ()
  "Return the owning integration module for the current table."
  (or (bound-and-true-p emacsvox-aural-module) 'tabulated-list))

(defun emacsvox-tabulated-list--submit-cell (content facts &rest icons)
  "Submit cell CONTENT, FACTS, and compatibility ICONS through aural policy."
  (let ((arguments
         (list
          :facts facts
          :module (emacsvox-tabulated-list--module)
          :occasion 'navigation
          :compatibility-actions
          (mapcar #'emacsvox-aural-compatibility-icon icons))))
  (if (zerop (length content))
        (apply #'emacsvox-aural-submit-actions arguments)
      (apply #'emacsvox-aural-submit content arguments))))

(defun emacsvox-tabulated-list--column-at-point ()
  "Return the printed column, treating padding as part of the nearest cell."
  (or (cl-position (get-text-property (point) 'tabulated-list-column-name)
                   tabulated-list-format :test #'equal :key #'car)
      (if (eolp) (1- (length tabulated-list-format)) 0)))

(defun emacsvox-tabulated-list-speak-cell (&optional movement-icon)
  "Speak the current cell with optional MOVEMENT-ICON."
  (interactive)
  (let* ((entry (or (tabulated-list-get-entry) (user-error "No entry here")))
         (column (emacsvox-tabulated-list--column-at-point))
         (name (car (elt tabulated-list-format column)))
         (value (emacsvox-tabulated-list--label (elt entry column))))
    (when value
      (apply #'emacsvox-tabulated-list--submit-cell
             (if (called-interactively-p 'interactive) (concat name " " value) value)
             (emacsvox-tabulated-list--cell-facts (string-blank-p value))
             (append (when movement-icon (list movement-icon))
                     (when (zerop column) '(left))
                     (when (= column (1- (length tabulated-list-format))) '(right)))))))

(cl-loop
 for target in
 '(tabulated-list-next-column tabulated-list-previous-column)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Tabulated List column movement."
       (when (ems-interactive-p ',target)
         (emacsvox-tabulated-list-speak-cell 'select-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox-tabulated-list--move-row (direction)
  "Move to the same column of the next visible entry in DIRECTION."
  (let* ((inhibit-field-text-motion t)
         (column (emacsvox-tabulated-list--column-at-point))
         (name (car (elt tabulated-list-format column)))
         (destination
          (save-excursion
            (beginning-of-line)
            (catch 'cell
              (while (zerop (forward-line direction))
                (when (and (tabulated-list-get-entry) (not (invisible-p (point))))
                  (throw 'cell
                         (or (text-property-any (point) (line-end-position)
                                                'tabulated-list-column-name name)
                             (when (and (= column (1- (length tabulated-list-format)))
                                        (equal "" (emacsvox-tabulated-list--label
                                                   (elt (tabulated-list-get-entry) column))))
                               (line-end-position))))))))))
    (unless destination
      (user-error "%s" (if (> direction 0) "No next entry" "No previous entry")))
    (goto-char destination)
    (emacsvox-tabulated-list-speak-cell 'select-object)))

(defun emacsvox-tabulated-list-next-row ()
  "Move to the next entry and speak the same column."
  (interactive)
  (emacsvox-tabulated-list--move-row 1))

(defun emacsvox-tabulated-list-previous-row ()
  "Move to the previous entry and speak the same column."
  (interactive)
  (emacsvox-tabulated-list--move-row -1))

(defun emacsvox-tabulated-list-setup ()
  "Setup Emacsvox"
  
  (cl-loop
   for b in
   '(
     ( "." emacsvox-tabulated-list-speak-cell)
     ("<down>"  emacsvox-tabulated-list-next-row)
     ("<left>" tabulated-list-previous-column)
     ("<right>" tabulated-list-next-column)
     ("<up>" emacsvox-tabulated-list-previous-row))
   do
   
   (emacsvox-keymap-update tabulated-list-mode-map b)))

(emacsvox-tabulated-list-setup)

;;; Explicit shared reading:

(defun emacsvox-tabulated-list--label (descriptor)
  "Return the logical text of a column DESCRIPTOR, or nil if unsupported."
  (cond ((stringp descriptor) descriptor)
        ((and (consp descriptor) (stringp (car descriptor))) (car descriptor))))

(defvar-local emacsvox-tabulated-list--cache nil
  "Printed rows indexed for the current buffer revision and visibility.")

(defun emacsvox-tabulated-list--printed-table (titles)
  "Index visible printed entries using TITLES, without calling a producer."
  (let (rows positions starts ends)
    (catch 'unsupported
      (unless (= (length titles) (length (delete-dups (copy-sequence titles))))
        (throw 'unsupported nil))
      (save-excursion
        (goto-char (point-min))
        (while (< (point) (point-max))
          (let* ((start (point))
                 (end (min (next-single-property-change start 'tabulated-list-entry nil (point-max))
                           (next-single-property-change start 'tabulated-list-id nil (point-max))))
                 (entry (tabulated-list-get-entry)))
            (when (and entry (not (invisible-p start)))
              (let ((values (mapcar #'emacsvox-tabulated-list--label entry))
                    cells)
                (unless (and (= (length values) (length titles)) (cl-every #'stringp values))
                  (throw 'unsupported nil))
                (cl-loop for title in titles for value in values for column from 0 do
                         (let ((pos (or (text-property-any start end 'tabulated-list-column-name title)
                                        (when (and (= column (1- (length titles))) (equal value ""))
                                          (1- end)))))
                           (when (and pos (invisible-p pos)) (throw 'unsupported nil))
                           (push pos cells)))
                (push start starts)
                (push end ends)
                (push values rows)
                (push (vconcat (nreverse cells)) positions)))
            (goto-char end))))
      (setq rows (nreverse rows) positions (nreverse positions))
      (list :region (cons (point-min) (point-max)) :rows rows :row-count (length rows)
            :column-count (length titles) :column-titles titles
            :source-rows (vconcat rows) :source-positions (vconcat positions)
            :positions (cl-mapcan (lambda (row) (append row nil)) positions)
            :starts (vconcat (nreverse starts)) :ends (vconcat (nreverse ends))))))

(defun emacsvox-tabulated-list--snapshot ()
  "Return the visible printed cell at point with its complete logical value."
  (when (and (eq tabulated-list-printer #'tabulated-list-print-entry)
             (> (length tabulated-list-format) 0)
             (tabulated-list-get-entry) (not (invisible-p (point))))
    (let* ((titles (mapcar #'car tabulated-list-format))
           ;; Moving or hiding an overlay can change the visible rows without
           ;; changing the buffer tick.  Ignore overlays that only paint text.
           (key (list (buffer-modified-tick) (point-min) (point-max) titles
                      (copy-tree buffer-invisibility-spec)
                      (cl-loop for ov in (overlays-in (point-min) (point-max))
                               when (overlay-get ov 'invisible)
                               collect (list (overlay-start ov) (overlay-end ov)
                                             (overlay-get ov 'invisible)))))
           (table (if (equal key (car emacsvox-tabulated-list--cache))
                      (cdr emacsvox-tabulated-list--cache)
                    (cdr (setq emacsvox-tabulated-list--cache
                               (cons key (emacsvox-tabulated-list--printed-table titles)))))))
      (when table
        (let ((row (emacsvox-table-reader--index-at (plist-get table :starts) (point)))
              (column (emacsvox-tabulated-list--column-at-point)))
          (when (and (>= row 0) (< (point) (aref (plist-get table :ends) row)))
            (let ((values (aref (plist-get table :source-rows) row)))
              (append (list :row-index row :column-index column :data (nth column values)
                            :column-title (nth column titles) :row-title (car values))
                      table))))))))

(defun emacsvox-tabulated-list--reader-submit (text occasion presentation icon)
  "Submit shared-reader TEXT with OCCASION, PRESENTATION and ICON."
  (let ((empty (and (eq presentation 'cell)
                    (string-blank-p
                     (or (plist-get emacsvox-table-reader--presentation-cell :data) "")))))
    (emacsvox-aural-submit
     text :module (emacsvox-tabulated-list--module) :occasion occasion
     :facts (emacsvox-tabulated-list--cell-facts empty)
     :compatibility-actions (list (emacsvox-aural-compatibility-icon icon)))))

(defun emacsvox-tabulated-list--reader-key (key command)
  "Offer reader COMMAND on KEY only when the application has no action there."
  (let* ((emacsvox-table-reader-mode nil)
         (binding (key-binding key)))
    (when (memq binding '(nil undefined self-insert-command)) command)))

(defvar emacsvox-tabulated-list--reader-map
  (let ((map (copy-keymap emacsvox-table-reader-mode-map)))
    ;; Keep the shared navigation and q-to-leave contract.  Application actions
    ;; win on all other keys, including text-button maps at point.  Commands
    ;; displaced by an application remain available by their M-x names.
    (dolist (key '("TAB" "<backtab>" "RET" "SPC" "r" "c" "." "="
                   "w" "a" "t" "T" "k"))
      (let* ((sequence (kbd key))
             (command (lookup-key map sequence)))
        (define-key map sequence
                    `(menu-item "Table reading" ,command
                                :filter ,(apply-partially
                                          #'emacsvox-tabulated-list--reader-key
                                          sequence)))))
    map)
  "Explicit reading map that preserves tabulated applications' action keys.")

(setf (alist-get 'tabulated-list-mode emacsvox-table-reader--adapters)
      (list #'emacsvox-tabulated-list--snapshot
            #'emacsvox-tabulated-list--reader-submit
            emacsvox-tabulated-list--reader-map))

(provide 'emacsvox-tabulated-list)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-tabulated-list.el ends here
