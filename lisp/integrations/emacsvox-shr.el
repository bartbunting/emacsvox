;;; emacsvox-shr.el --- Speech-enable shared HTML reading  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop shr
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
;;
;; Provide link navigation feedback for all SHR clients, including HTML mail,
;; without loading EWW.  EWW's existing specialised link speaker remains
;; available when that integration is loaded.
;; Retain logical data-table cells for shared reading in HTML mail.

;;; Code:

(require 'emacsvox-preamble)
(require 'shr)
(require 'emacsvox-table-reader)

(defvar-local emacsvox-eww-a-speaker nil
  "Specialized link speaker.")

(defun emacsvox--advice-shr-link-message-around (original &rest arguments)
  "Keep SHR's URL echo visible without speaking a duplicate notification."
  (let ((ems--message-filter
         (concat
          (when ems--message-filter
            (concat "\\(?:" ems--message-filter "\\)\\|"))
          "\\`[[:alpha:]][[:alnum:]+.-]*:")))
    (apply original arguments)))

(cl-loop
 for target in
 '(shr-next-link shr-previous-link)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the styled label after interactive HTML link navigation."
       (when (ems-interactive-p ',target)
         (if emacsvox-eww-a-speaker
             (funcall emacsvox-eww-a-speaker)
           (emacsvox-speak-region
            (point)
            (next-single-property-change
             (point) 'help-echo nil (point-max))))))
     (advice-add
      ',target :after #',function '((name . emacsvox)))
     (advice-add
      ',target :around #'emacsvox--advice-shr-link-message-around
      '((name . emacsvox-link-message))))))

;;; Logical cells in rendered HTML tables.

(defvar emacsvox-shr--data-table-p nil
  "Non-nil while rendering a recognized rectangular data table.")
(defvar emacsvox-shr--presentation-table-p nil
  "Non-nil while rendering a table explicitly marked as presentation.")

(defun emacsvox-shr--data-table-p (dom)
  "Whether normalized DOM has a header row and unmerged data cells.
Reject nested tables and layout-only structures rather than guessing columns."
  (let* ((body (or (dom-child-by-tag dom 'tbody) dom))
         (rows (dom-non-text-children body))
         (cells (mapcar #'dom-non-text-children rows))
         (width (length (car cells))))
    (and (not emacsvox-shr--presentation-table-p)
         (> (length rows) 1) (> width 1)
         (<= (* width (length rows)) 2000)
         (cl-every (lambda (row) (eq (dom-tag row) 'tr)) rows)
         (cl-every
          (lambda (row)
            (and (= (length row) width)
                 (cl-every
                  (lambda (cell)
                    (and (memq (dom-tag cell) '(td th))
                         (not (dom-by-tag cell 'table))
                         (cl-every
                          (lambda (attribute)
                            (member (dom-attr cell attribute) '(nil "1")))
                          '(rowspan colspan)))) row))) cells)
         (cl-every
          (lambda (cell)
            (or (eq (dom-tag cell) 'th)
                (dom-by-tag cell 'b) (dom-by-tag cell 'strong))) (car cells)))))

(defun emacsvox--advice-shr-table-role-around (original dom)
  "Keep DOM's layout role before SHR normalizes its attributes."
  (let ((emacsvox-shr--presentation-table-p
         (or (dom-attr dom 'emacsvox-presentation-table)
             (member (dom-attr dom 'role) '("presentation" "none")))))
    (prog1 (funcall original dom)
      (when emacsvox-shr--presentation-table-p
        (dom-set-attribute dom 'emacsvox-presentation-table t)))))

(defun emacsvox--advice-shr-data-table-around (original dom)
  "Establish whether normalized DOM can supply logical table reading."
  (let ((emacsvox-shr--data-table-p (emacsvox-shr--data-table-p dom)))
    (funcall original dom)))

(defun emacsvox-shr--table-spans (table begin end)
  "Map rendered TABLE cells between BEGIN and END to displayed spans.
Use SHR's alignment properties, including padding for empty and wrapped cells.
Return nil if the actual rendering does not match the logical row structure."
  (save-excursion
    (goto-char begin)
    (let ((rulers (and shr-table-horizontal-line
                       (not (equal (cdr (assq 'border-collapse shr-stylesheet))
                                   "collapse"))))
          (row-index 0) spans valid)
      (setq valid t)
      (when rulers (forward-line 1))
      (dolist (row table)
        (dotimes (_ (max 1 (apply #'max (mapcar (lambda (cell) (nth 2 cell)) row))))
          (let ((start (point)) (limit (min end (line-end-position))) (column 0))
            (while (and valid (< column (length row)))
              (let ((align (text-property-not-all start limit 'shr-table-indent nil)))
                (if (not align)
                    (setq valid nil)
                  (push (list start (1+ align) row-index column) spans)
                  (setq start (1+ align) column (1+ column)))))
            (when (text-property-not-all start limit 'shr-table-indent nil)
              (setq valid nil)))
          (forward-line 1))
        (when rulers (forward-line 1))
        (setq row-index (1+ row-index)))
      (when (and valid (= (point) end)) (nreverse spans)))))

(defun emacsvox-shr--table-cell-text (lines)
  "Join rendered cell LINES, preserving faces without retaining DOM caches."
  (mapconcat
   (lambda (line)
     (let ((text (substring-no-properties line)) (start 0))
       (while (< start (length line))
         (let ((end (next-single-property-change start 'face line (length line)))
               (face (get-text-property start 'face line)))
           (when face (put-text-property start end 'face face text))
           (setq start end)))
       (string-trim text))) lines " "))

(defun emacsvox--advice-shr-insert-table-around (original table widths)
  "Render TABLE at WIDTHS unchanged, retaining logical data and cell spans."
  (let ((begin (point)) (result (funcall original table widths)))
    (when emacsvox-shr--data-table-p
      (when-let* ((spans (emacsvox-shr--table-spans table begin (point))))
        (let* ((rows (mapcar
                      (lambda (row)
                        (mapcar
                         (lambda (cell)
                           (emacsvox-shr--table-cell-text (nth 3 cell))) row)) table))
               ;; A distinct object identifies this rendering, without keeping
               ;; the DOM, renderer caches or source buffer alive.
               (model (list :rows rows)))
          (put-text-property begin (point) 'emacsvox-shr-table model)
          (dolist (span spans)
            (put-text-property (nth 0 span) (nth 1 span)
                               'emacsvox-shr-table-cell (nthcdr 2 span))))))
    result))

(defun emacsvox-shr--table-snapshot ()
  "Return the complete logical HTML cell at point and fresh displayed bounds."
  (when-let* (((not (invisible-p (point))))
              (model (get-text-property (point) 'emacsvox-shr-table))
              (coordinates (get-text-property (point) 'emacsvox-shr-table-cell)))
    (let* ((begin (or (previous-single-property-change
                      (1+ (point)) 'emacsvox-shr-table nil (point-min)) (point-min)))
           (end (next-single-property-change (point) 'emacsvox-shr-table nil (point-max)))
           (rows (plist-get model :rows))
           (width (length (car rows)))
           (positions (make-vector (* width (length rows)) nil))
           (row (car coordinates)) (column (cadr coordinates)))
      (save-excursion
        (goto-char begin)
        (while (< (point) end)
          (when-let* ((cell (get-text-property (point) 'emacsvox-shr-table-cell)))
            (let ((index (+ (* width (car cell)) (cadr cell))))
              (unless (aref positions index)
                (aset positions index (point)))))
          (goto-char (next-single-property-change
                      (point) 'emacsvox-shr-table-cell nil end))))
      (when (cl-every #'identity positions)
        (list :region (cons begin end) :positions (append positions nil) :rows rows
              :row-index row :row-count (length rows)
              :column-index column :column-count width
              :data (nth column (nth row rows)) :column-titles-p t
              :column-title (nth column (car rows))
              :row-title (unless (zerop row) (car (nth row rows))))))))

(advice-add 'shr-tag-table :around #'emacsvox--advice-shr-table-role-around
            '((name . emacsvox-logical-table)))
(advice-add 'shr-tag-table-1 :around #'emacsvox--advice-shr-data-table-around
            '((name . emacsvox-logical-table)))
(advice-add 'shr-insert-table :around #'emacsvox--advice-shr-insert-table-around
            '((name . emacsvox-logical-table)))

(provide 'emacsvox-shr)
;;; emacsvox-shr.el ends here
