;;; emacsvox-solitaire.el --- Solitaire -*- lexical-binding: t -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to solitaire
;; Keywords: Emacsvox, Speak, Spoken Output, solitaire
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (c) 1995 -- 2024, T. V. Raman
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;   Required modules:

(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'solitaire)

;;;   Introduction 
;;; Commentary:
;; Auditory interface to solitaire
;;; Code:

;;;   Communicate state

(defun emacsvox-solitaire-current-row ()
  "Return the one-based row of the current Solitaire cell."
  (+ 1 (/
        (- (solitaire-current-line)
           solitaire-start-y)
        2)))

(defun emacsvox-solitaire-current-column ()
  "Return the one-based column of the current Solitaire cell."
  (let ((c (current-column)))
    (+ 1
       (/ (- c solitaire-start-x)
          4))))

(defun emacsvox-solitaire--cell-kind (&optional character)
  "Return the semantic kind represented by CHARACTER or the cell at point."
  (pcase (or character (char-after (point)))
    (?o 'stone)
    (?. 'hole)
    (_ 'other)))

(defun emacsvox-solitaire--cell-facts (kind &optional event)
  "Return facts for a Solitaire cell of KIND and optional EVENT."
  (append
   (list :role 'game-cell :game-cell-kind kind)
   (when event (list :events (list event)))))

(defun emacsvox-solitaire--submit
    (content facts occasion &optional icon)
  "Submit Solitaire CONTENT and FACTS with OCCASION and optional ICON."
  (let ((actions
         (when icon
           (list (emacsvox-aural-compatibility-icon icon)))))
    (if (and (stringp content) (> (length content) 0))
        (emacsvox-aural-submit
         content
         :facts facts
         :module 'solitaire
         :occasion occasion
         :compatibility-actions actions)
      (emacsvox-aural-submit-actions
       :facts facts
       :module 'solitaire
       :occasion occasion
       :compatibility-actions actions))))

(defun emacsvox-solitaire-speak-coordinates
    (&optional icon occasion event)
  "Present the current cell coordinates in one native transaction.
Optional ICON precedes the content.  OCCASION defaults to `inspection', and
EVENT records an optional semantic event."
  (interactive)
  (let ((kind (emacsvox-solitaire--cell-kind)))
    (emacsvox-solitaire--submit
     (format
      "%s at %s %s"
      (pcase kind
        ('stone "stone")
        ('hole "hole")
        (_ "cell"))
      (emacsvox-solitaire-current-row)
      (emacsvox-solitaire-current-column))
     (emacsvox-solitaire--cell-facts kind event)
     (or occasion 'inspection)
     icon)))

(defun emacsvox-solitaire-speak-stones ()
  "Speak number of stones remaining."
  (interactive)
  (emacsvox-solitaire--submit
   (format "%d stones" solitaire-stones)
   (list :role 'game-status :game-piece-count solitaire-stones)
   'inspection))

(defun emacsvox-solitaire--present-cell-tone (kind)
  "Present the tone for a Solitaire cell containing KIND."
  (emacsvox-solitaire--submit
   nil (emacsvox-solitaire--cell-facts kind) 'inspection))

(defun emacsvox-solitaire-stone ()
  "Present the first-class tone for a Solitaire stone."
  (emacsvox-solitaire--present-cell-tone 'stone))

(defun emacsvox-solitaire-hole ()
  "Present the first-class tone for a Solitaire hole."
  (emacsvox-solitaire--present-cell-tone 'hole))

(defun emacsvox-solitaire-speak-row ()
  "Speak current row."
  (interactive)
  (emacsvox-solitaire--submit
   (buffer-substring
    (line-beginning-position) (line-end-position))
   '(:role game-status)
   'inspection))

(defun emacsvox-solitaire-cell-to-icon (cell)
  "Return the legacy auditory icon corresponding to Solitaire CELL.
This compatibility mapper remains available to external callers; native
Solitaire presentation uses semantic cell tones."
  (cond
   ((string= cell ".") 'close-object)
   ((string= cell "o") 'item)))

(defun emacsvox-solitaire-show-row ()
  "Present first-class tones for each cell in the current row."
  (interactive)
  (let ((cells
         (split-string
          (buffer-substring (line-beginning-position) (line-end-position)))))
    (mapcar
     (lambda (cell)
       (emacsvox-solitaire--present-cell-tone
        (if (string= cell "o") 'stone 'hole)))
     cells)))

(defun emacsvox-solitaire-show-column ()
  "Present first-class tones for each cell in the current column."
  (interactive)
  (save-excursion
    (let ((row (emacsvox-solitaire-current-row))
          (column (emacsvox-solitaire-current-column))
          (cells nil))
      ;; Move to the top row.
      (cl-loop repeat (1- row) do (solitaire-up))
      (cl-case (char-after (point))
        (?o (push 'stone cells))
        (?. (push 'hole cells)))
      (cond
       ((and (>= column 3) (<= column 5))
        (cl-loop
         for count from 2 to 7 do
         (solitaire-down)
         (cl-case (char-after (point))
           (?o (push 'stone cells))
           (?. (push 'hole cells)))))
       (t
        (cl-loop
         for count from 2 to 3 do
         (solitaire-down)
         (cl-case (char-after (point))
           (?o (push 'stone cells))
           (?. (push 'hole cells))))))
      (setq cells (nreverse cells))
      (mapcar #'emacsvox-solitaire--present-cell-tone cells))))

;;;  Advice commands:

(defvar emacsvox-solitaire-autoshow nil
  "Non-nil means rows and columns are toned as point moves.")

(defmacro emacsvox-solitaire--define-navigation-advice
    (targets show-function)
  "Define native movement advice for TARGETS using SHOW-FUNCTION."
  (declare (indent 1) (debug (sexp function-form)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 "Announce an interactive move around the Solitaire board."
                 (when (ems-interactive-p ',target)
                   (let ((tts-stop-immediately nil))
                     (when emacsvox-solitaire-autoshow
                       (,show-function))
                     (emacsvox-solitaire-speak-coordinates
                      'select-object 'navigation))))
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-solitaire--define-navigation-advice
    (solitaire-left solitaire-right)
  emacsvox-solitaire-show-column)

(emacsvox-solitaire--define-navigation-advice
    (solitaire-up solitaire-down)
  emacsvox-solitaire-show-row)

(defun emacsvox--advice-solitaire-center-point-after (&rest _)
  "Announce an interactive move to the center of the board."
  (when (ems-interactive-p 'solitaire-center-point)
    (emacsvox-solitaire-speak-coordinates
     'large-movement 'navigation)))

(advice-add 'solitaire-center-point :after
            #'emacsvox--advice-solitaire-center-point-after)

(defmacro emacsvox-solitaire--define-move-advice (targets)
  "Define target-aware native move feedback for Solitaire TARGETS."
  (declare (indent 0) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,(format "Announce a completed `%s' move." target)
                 (when (ems-interactive-p ',target)
                   (emacsvox-solitaire-speak-coordinates
                    'item 'state-change 'operation-completed)))
               (advice-add ',target :after #',function))))
        targets)))

(emacsvox-solitaire--define-move-advice
  (solitaire-move
   solitaire-move-right
   solitaire-move-left
   solitaire-move-up
   solitaire-move-down))

(defun emacsvox-solitaire-setup ()
  "Emacsvox provides an auditory interface to the solitaire game.
As you move you hear the coordinates and state of the current
cell.  Moving a stone produces a completion cue and cell tone.  You can examine
the state of the board by using `r' and `c' to listen to the row
and column respectively.  Emacsvox produces tones to indicate
the state --a higher pitched beep indicates a hole.  Rows and
columns are displayed aurally by grouping the tones to provide
structure.  Emacsvox specific commands:
\\[emacsvox-solitaire-show-column]
emacsvox-solitaire-show-column \\[emacsvox-solitaire-show-row]
emacsvox-solitaire-show-row
\\[emacsvox-solitaire-speak-coordinates]
emacsvox-solitaire-speak-coordinates"
  (delete-other-windows)
  (setq-local emacsvox-aural-module 'solitaire)
  (emacsvox-solitaire-setup-keymap)
  (let ((emacsvox-speak-messages nil))
    (message "Welcome to Solitaire"))
  (emacsvox-solitaire--submit
   "Welcome to Solitaire"
   '(:role game-status)
   'state-change
   'open-object))

(add-hook
 'solitaire-mode-hook
 #'emacsvox-solitaire-setup)

;;;   add keybindings

(defun emacsvox-solitaire-setup-keymap ()
  "Set up Emacsvox key bindings for Solitaire."
  (define-key solitaire-mode-map "/" 'emacsvox-solitaire-speak-stones)
  (define-key solitaire-mode-map "." 'emacsvox-solitaire-speak-coordinates)
  (define-key solitaire-mode-map "R" 'emacsvox-solitaire-speak-row)
  (define-key solitaire-mode-map "r" 'emacsvox-solitaire-show-row)
  (define-key solitaire-mode-map "c" 'emacsvox-solitaire-show-column)
  (define-key solitaire-mode-map "f" 'solitaire-move-right)
  (define-key solitaire-mode-map "b" 'solitaire-move-left)
  (define-key solitaire-mode-map "p" 'solitaire-move-up)
  (define-key solitaire-mode-map "n" 'solitaire-move-down)
  (define-key solitaire-mode-map "l" 'solitaire-right)
  (define-key solitaire-mode-map "h" 'solitaire-left)
  (define-key solitaire-mode-map "k" 'solitaire-up)
  (define-key solitaire-mode-map "j" 'solitaire-down))

(provide 'emacsvox-solitaire)
;;;  end of file 
