;;; emacsvox-tabulate.el --- Handle table data   -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Tabulated Data,  Visual layout gives structure
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
;; This module is a simple table recognizer.
;; Can recognize the columns in tabulated output, e.g. ps, ls output
;;; Code:

;;;  requires
(require 'emacsvox-preamble)

;;;   helper functions:

;; An interval is a cons of start and end 
(defun ems-make-interval (start end) (cons start end))
(defun ems-interval-start (interval) (car interval))
(defun ems-interval-end (interval) (cdr interval))
(defun ems-intersect-intervals (i1 i2)
  (let  ((i (cons (max (ems-interval-start i1)
                       (ems-interval-start i2))
                  (min (ems-interval-end i1)
                       (ems-interval-end i2)))))
    (if (< (car i) (cdr i)) i nil)))

;;;   Identify the fields in a region 

(defun ems-tabulate-field-separators-in-this-line () 
  "Returns a list of intervals specifying the field separators on the line.
Fields are assumed to be delimited by whitespace. "
  (let ((positions nil)
        (end nil)
        (first nil)
        (last nil)
        (continue t))
    (save-excursion
      (end-of-line)
      (setq end (point))
      (beginning-of-line)
      (save-restriction
        (narrow-to-region (point) end)
        (skip-syntax-forward " ")
        (while (and continue
                    (<= (point)  end))
                                        ;skip field
          (unless (zerop (skip-syntax-forward "^ "))
            (setq first  (current-column)))
                                        ;skip field separator 
          (unless (zerop (skip-syntax-forward " "))
            (setq last (current-column)))
                                        ;check if we found a field separator
          (cond
           ((and first
                 last
                 (< first last))
            (push (ems-make-interval  first last) positions))
           (t (setq continue nil)))
                                        ;reset fornext iteration
          (setq first nil
                last nil)))
      (nreverse  positions))))

(defun ems-tabulate-field-separators-in-region (start end)
  "Return a list of column separators. "
  (when  (< end start)
    (let ((tmp end))
      (setq end start
            start tmp)))
  (save-restriction 
    (narrow-to-region start end)
    (save-excursion
      (goto-char start)
      (let  ((try nil)
             (first nil)
             (last nil)
             (interval nil)
             (new-guesses nil)
             (guesses (ems-tabulate-field-separators-in-this-line)))
        (while (and guesses
                    (< (point) end)
                    (not (= 1 (forward-line 1))))
          (setq try guesses)
          (while try
            (beginning-of-line)
            (goto-char (+ (point)  (ems-interval-start   (car try))))
            (skip-syntax-forward "^ ")
            (setq first (current-column))
            (skip-syntax-forward " ")
            (setq last (current-column))
            (setq interval
                  (ems-intersect-intervals (car try)
                                           (ems-make-interval first last)))
            (when interval (push interval  new-guesses))
            (pop try)
            (setq first nil
                  last nil
                  interval nil))
          (end-of-line)
          (setf guesses (nreverse new-guesses) 
                new-guesses nil))
        guesses))))

;;  White space contains a list of intervals giving position of inter
;;  columnal space. All calculations are done in terms of buffer
;;  position.
;; Invariants: (= (- tl tr) (- bl br))
;; tl = start for first column
;; br = end for last column

;;;  Parse a region of tabular data

(provide 'emacsvox-tabulate)

;;; emacsvox-tabulate.el ends here
