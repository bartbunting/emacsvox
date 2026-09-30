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

(defun emacsvox-tabulated-list-speak-cell (&optional movement-icon)
  "Speak the current cell with optional MOVEMENT-ICON."
  (interactive)
  (when (bobp) (error "Beginning  of buffer"))
  (when (eobp) (error "End of buffer"))
  (save-excursion
    (when-let*
        ((name (get-text-property (point) 'tabulated-list-column-name))
         (col
          (cl-position name tabulated-list-format
                       :test #'string= :key #'car))
         (value (elt (tabulated-list-get-entry) col)))
      (let ((edge-icons
             (append
              (when (= 0 col) '(left))
              (when (= (1- (length tabulated-list-format)) col) '(right)))))
        (when (listp value) (setq value (car value)))
        (let* ((empty (zerop (length (string-trim value))))
               (content
                (if (called-interactively-p 'interactive)
                    (concat name " " value)
                  value)))
          (apply
           #'emacsvox-tabulated-list--submit-cell
           content
           (emacsvox-tabulated-list--cell-facts empty)
           (append
            (when movement-icon (list movement-icon))
            edge-icons)))))))

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

(defun emacsvox-tabulated-list-next-row ()
  "Move to next row and speak that cell"
  (interactive)
  (let ((col
         (cl-position
          (get-text-property (point) 'tabulated-list-column-name)
          tabulated-list-format
          :test #'string= :key #'car)))
    (forward-line 1)
    (tabulated-list-next-column  col)
    (when-let* ((goal (next-single-property-change (point)
                                                  'tabulated-list-column-name)))
      (goto-char goal))
    (emacsvox-tabulated-list-speak-cell 'select-object)))

(defun emacsvox-tabulated-list-previous-row ()
  "Move to previous row and speak that cell."
  (interactive)
  (let ((col
         (cl-position
          (get-text-property (point) 'tabulated-list-column-name)
          tabulated-list-format
          :test #'string= :key #'car)))
    (forward-line -1)
    (tabulated-list-next-column  col)
    (when-let* ((goal (next-single-property-change
                      (point) 'tabulated-list-column-name)))
      (goto-char goal))
    (emacsvox-tabulated-list-speak-cell 'select-object)))

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

(defun emacsvox-tabulated-list--snapshot ()
  "Read visible, printed entries in display order without invoking producers.
Use complete entry values rather than truncated display text.  Custom printers
and ambiguous column names are not supported.  Headers are metadata, not rows."
  (when (and (eq tabulated-list-printer #'tabulated-list-print-entry)
             (> (length tabulated-list-format) 0)
             (tabulated-list-get-entry))
    (let* ((origin (point))
           (titles (mapcar #'car (append tabulated-list-format nil)))
           rows positions selected-row selected-column
           (supported (= (length titles) (length (delete-dups (copy-sequence titles))))))
      (save-excursion
        (goto-char (point-min))
        (while (and supported (< (point) (point-max)))
          (let* ((start (point))
                 (entry (tabulated-list-get-entry))
                 (end (min (next-single-property-change
                            start 'tabulated-list-entry nil (point-max))
                           (next-single-property-change
                            start 'tabulated-list-id nil (point-max)))))
            (when (and entry (not (invisible-p start)))
              (let ((values (mapcar #'emacsvox-tabulated-list--label
                                    (append entry nil)))
                    cell-positions)
                (setq supported (and (= (length values) (length titles))
                                     (cl-every #'stringp values)))
                (cl-loop for title in titles for column from 0 do
                         (let ((position
                                (text-property-any start end
                                                   'tabulated-list-column-name title)))
                           ;; An empty final column has no printed characters;
                           ;; the row's newline is its stable source position.
                           (when (and (not position)
                                      (= column (1- (length titles)))
                                      (equal (nth column values) ""))
                             (setq position (1- end)))
                           (when (and position (invisible-p position))
                             (setq supported nil))
                           (push position cell-positions)))
                (setq cell-positions (nreverse cell-positions))
                (when (and (<= start origin) (< origin end))
                  (setq selected-row (length rows)
                        selected-column
                        (or (cl-position
                             (get-text-property origin 'tabulated-list-column-name)
                             titles :test #'equal)
                            (if (>= origin (1- end)) (1- (length titles)) 0))))
                (push values rows)
                (push cell-positions positions)))
            (goto-char end))))
      (when (and supported selected-row)
        (setq rows (nreverse rows)
              positions (apply #'append (nreverse positions)))
        (list :region (cons (point-min) (point-max))
              :rows rows :positions positions
              :row-index selected-row :row-count (length rows)
              :column-index selected-column :column-count (length titles)
              :column-titles titles :column-title (nth selected-column titles)
              :row-title (car (nth selected-row rows))
              :data (nth selected-column (nth selected-row rows)))))))

(defun emacsvox-tabulated-list--reader-submit (text occasion presentation icon)
  "Submit shared-reader TEXT with OCCASION, PRESENTATION and ICON."
  (let* ((cell (emacsvox-tabulated-list--snapshot))
         (empty (and (eq presentation 'cell)
                     (string-empty-p (string-trim (or (plist-get cell :data) ""))))))
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
