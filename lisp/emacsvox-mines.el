;;; emacsvox-mines.el --- Speech-enable MINES  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable MINES An Emacs Interface to mines
;; Keywords: Emacsvox,  Audio Desktop mines
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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
;; MERCHANTABILITY or FITNMINES FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; MINES == Minesweeper game in emacs. The game itself provides a
;; fully keyboard driven interface. In addition, Emacsvox provides
;; these additional interactive commands:
;; @itemize @bullet
;; @item @kbd{SPC} Speak current cell.
;; @item @kbd{.} Speak neighbors of current cell.
;; @item @kbd{,} Speak number of marks
;; @item @kbd{a} Move to beginning of row.
;; @item @kbd{e} Move to end of row.
;; @item @kbd{g} Move to specified cell 
;; @item @kbd{s} Move to next uncovered cell.
;; @item @kbd{/} Speak number of remaining uncovered cells.
;; @item @kbd{'} Speaks entire board.
;; @end itemize
;; 
;; Speaking cell neighbors uses appropriate clause boundaries to group
;; related cells --- neighbors are read left-to-right, top-to-bottom.
;; Moving to the left/right edge of the board produces an appropriate
;; auditory icon.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'mines "mines" 'no-error)

;;;  Interactive Commands:

(defun emacsvox-mines-speak-cell ()
  "Speak current cell."
  (interactive)
  (let* ((pos (mines-index-2-matrix (mines-current-pos)))
         (row (cl-first pos))
         (column (cl-second pos)))
    (when (= 0 column) (emacsvox-icon 'left))
    (when (= 7 column) (emacsvox-icon 'right))
    (when (or (= row 0) (= row 7)) (emacsvox-icon 'large-movement))
    (dtk-speak
     (format "%c in row %s column %s" (following-char) row column))))

(defun emacsvox-mines-speak-uncovered-count ()
  "Speak number of uncovered cells."
  (interactive)
  
  
  (dtk-speak
   (format "%d mines with %d uncovered cells remaining."
           mines-number-mines (cl-count-if #'null mines-state))))

(defun emacsvox-mines-jump-to-uncovered-cell (from-beginning)
  "Jump to next uncovered cell. With interactive prefix-arg, jump
to beginning of board before searching."
  (interactive "P")
  (when from-beginning (mines-goto 0))
  (forward-char 1)
  (let ((found (search-forward "."nil t)))
    (when found (backward-char 1))
    (if found
        (emacsvox-mines-speak-cell)
      (message "No uncovered cell here. "))))

(defun emacsvox-mines-goto (index)
  "Move to specified cell."
  (interactive "nCell: ")
  (mines-goto index)
  (emacsvox-mines-speak-cell))

(defun emacsvox-mines-speak-mark-count  ()
  "Count and speak number of marks."
  (interactive)
  
  (let ((count 0) ;;; fix over-counting 
        (m (format "%c" mines-flagged-cell-char)))
    (save-excursion
      (goto-char (point-min))
      (while (search-forward  m nil t) (cl-incf count) (forward-char 1)))
    (message "%d marks" count)))
(defun emacsvox-mines-speak-board ()
  "Speak the board."
  (interactive)
  
  (let ((cells nil))
    (save-excursion
      (setq cells
            (cl-loop
             for i from 0 to (1- (length mines-state)) collect
             (progn
               (mines-goto i)
               (let ((v (aref mines-state i))
                     (n (aref mines-grid i)))
                 (cond
                  ((and (null v)(get-text-property (point) 'flag))
                   " M")
                  ((null v) "dot")
                  ((and v (numberp n))  (format "%d" n))
                  ((eq '@ v)  "at")
                  (t (message "Should not  get here"))))))))
    (dtk-speak-list cells mines-number-cols)))

(defun emacsvox-mines-init ()
  "Setup additional keys for playing minesweeper."
  
  (setq mines-flagged-cell-char ?M)
  (cl-loop
   for b in
   '(("." emacsvox-mines-speak-neighbors)
     ("," emacsvox-mines-speak-mark-count)
     ("SPC" emacsvox-mines-speak-cell)
     ("/" emacsvox-mines-speak-uncovered-count)
     ("'" emacsvox-mines-speak-board)
     ("a" emacsvox-mines-beginning-of-row)
     ("e" emacsvox-mines-end-of-row)
     ("g" emacsvox-mines-goto)
     ("s" emacsvox-mines-jump-to-uncovered-cell))
   do
   (define-key mines-mode-map (kbd (cl-first b)) (cl-second b))))

(eval-after-load  "mines"
  `(progn (emacsvox-mines-init)))

(defun emacsvox-mines-cell-flagged-p (c)
  "Predicate to check if cell at index c is flagged."
  (save-excursion
    (mines-goto c)
    (get-text-property (point) 'flag)))

(defun emacsvox-mines-speak-neighbors ()
  "Speak neighboring cells in sorted order."
  (interactive)
  
  (let* ((current (mines-current-pos))
         (cells (sort (mines-get-neighbours current) #'<))
         (pos (mines-index-2-matrix current))
         (row (cl-first pos))
         (count (length cells))
         (values (mapcar #'(lambda (c) (aref mines-state c)) cells))
         (numbers (mapcar #'(lambda (c) (aref mines-grid c)) cells))
         (result nil)
         (group nil))
    (cl-loop
     for c in cells
     and v in values
     and n in numbers do
     (cond
      ((and (null v) (emacsvox-mines-cell-flagged-p c))
       (push "M" result))
      ((null v) (push "dot" result))
      ((and v (numberp n)) (push (format "%d" n) result))
      ((eq '@ v) (push "at" result))
      (t (message "Should not  get here"))))
    (setq
     group
     (cond
      ((and (= 3 count) (= 0 row)) ;;; top corners
       '(1 2))
      ((and (= 3 count) (= 7 row)) ;;; bottom corners
       '(2 1))
      ((and (= 5 count) (= 0 row)) ;;; top
       '(2 3))
      ((and (= 5 count) (= 7 row)) ;;; bottom
       '(3 2))
      ((= 5 count) ;;; left/right edge
       '(2 1 2))
      (t '(3 2 3))))
    (dtk-speak-list (nreverse result) group)))
(defun emacsvox-mines-beginning-of-row  ()
  "Move to beginning of row"
  (interactive)
  (let ((row (cl-first (mines-index-2-matrix (mines-current-pos)))))
    (mines-goto (* row mines-number-cols))
    (emacsvox-mines-speak-cell)))

(defun emacsvox-mines-end-of-row  ()
  "Move to end of row"
  (interactive)
  (let ((row (cl-first (mines-index-2-matrix (mines-current-pos)))))
    (mines-goto (+ (1- mines-number-cols)(* row mines-number-cols)))
    (emacsvox-mines-speak-cell)))

;;;  Advice Interactive Commands

(defun ems--mines-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "New Minesweeper game") (emacsvox-icon 'open-object)))

(advice-add 'mines :after #'ems--mines-after)

(cl-loop
 for f in
 '(mines-go-down
   mines-go-left
   mines-go-right
   mines-go-up)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-mines-speak-cell)))))

(defun ems--mines-dig-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (unless mines-game-over (emacsvox-mines-speak-cell))))

(advice-add 'mines-dig :after #'ems--mines-dig-after)

(defun ems--mines-flag-cell-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (if (eq t (aref mines-grid (mines-current-pos)))
        (emacsvox-icon 'close-object)
      (emacsvox-icon 'mark-object))
    (emacsvox-mines-speak-cell)))

(advice-add 'mines-flag-cell :after #'ems--mines-flag-cell-after)

(defun ems--mines-game-over-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'shutdown)))

(advice-add 'mines-game-over :after #'ems--mines-game-over-after)

(defun ems--mines-game-completed-after (&rest _)
  "Provide an auditory icon." (emacsvox-icon 'task-done))

(advice-add 'mines-game-completed :after
            #'ems--mines-game-completed-after)

(provide 'emacsvox-mines)
;;;  end of file

