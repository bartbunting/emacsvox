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
(require 'solitaire)

;;;   Introduction 
;;; Commentary:
;; Auditory interface to solitaire
;;; Code:

;;;   Communicate state

(defun emacsvox-solitaire-current-row ()
  
  (+ 1 (/ 
        (- (solitaire-current-line)
           solitaire-start-y)
        2)))

(defun emacsvox-solitaire-current-column()
  
  (let ((c (current-column)))
    (+ 1
       (/ (- c solitaire-start-x)
          4))))

(defun emacsvox-solitaire-speak-coordinates ()
  "Speak coordinates of current position"
  (interactive)
  (tts-speak
   (format "%s at %s %s "
           (cl-case(char-after (point))
             (?o "stone")
             (?. "hole"))
           (emacsvox-solitaire-current-row)
           (emacsvox-solitaire-current-column)))
  (emacsvox-icon
   (emacsvox-solitaire-cell-to-icon (format "%c" (following-char)))))

(defun emacsvox-solitaire-speak-stones ()
  "Speak number of stones remaining."
  (interactive)
  
  (tts-speak (format "%d stones" solitaire-stones)))

(defun emacsvox-solitaire-stone  () (dtk-tone 400 150))

(defun emacsvox-solitaire-hole () (dtk-tone 800 100))
(defun emacsvox-solitaire-speak-row ()
  "Speak current row."
  (interactive)
  (emacsvox-speak-line))

(defun emacsvox-solitaire-cell-to-icon (cell)
  "Map Solitaire cell to auditory icon."
  (cond
   ((string= cell ".") 'close-object)
   ((string= cell "o") 'item)))

(defun emacsvox-solitaire-show-row ()
  "Audio format current row."
  (interactive)
  (let ((cells
         (split-string
          (buffer-substring (line-beginning-position) (line-end-position)))))
    (mapcar #'emacsvox-icon
            (mapcar #'emacsvox-solitaire-cell-to-icon cells))))

(defun emacsvox-solitaire-show-column ()
  "Audio format current column."
  (interactive)
  (save-excursion
    (let ((row (emacsvox-solitaire-current-row))
          (column (emacsvox-solitaire-current-column))
          (cells nil))
      ;; move to top row 
      (cl-loop for i  from 1 to(- row 1) do (solitaire-up))
      (cl-case (char-after (point))
        (?o (push "o" cells))
        (?. (push "." cells)))
      (cond
       ((and (>= column 3) (<= column 5))
        (cl-loop
         for count from 2 to 7 do
         (solitaire-down)
         (cl-case (char-after (point))
           (?o (push "o" cells))
           (?. (push "." cells)))))
       (t
        (cl-loop
         for count from 2 to 3 do
         (solitaire-down)
         (cl-case (char-after (point))
           (?o (push "o" cells))
           (?. (push "." cells))))))
      (setq cells (nreverse cells))
      (mapcar
       #'emacsvox-icon
       (mapcar #'emacsvox-solitaire-cell-to-icon cells)))))

;;;  advice commands

;;;  advice commands

(defvar emacsvox-solitaire-autoshow nil
  "T means rows and columns are toned as we move")

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
                   (let ((dtk-stop-immediately nil))
                     (emacsvox-icon 'select-object)
                     (when emacsvox-solitaire-autoshow
                       (,show-function))
                     (emacsvox-solitaire-speak-coordinates))))
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
    (emacsvox-icon 'large-movement)
    (emacsvox-solitaire-speak-coordinates)))

(advice-add 'solitaire-center-point :after
            #'emacsvox--advice-solitaire-center-point-after)

(defun emacsvox--advice-solitaire-move-after (&rest _)
  "Announce a completed stone move."
  (emacsvox-icon 'item)
  (emacsvox-solitaire-speak-coordinates))

(advice-add 'solitaire-move :after
            #'emacsvox--advice-solitaire-move-after)

(defun emacsvox-solitaire-setup()
  "Emacsvox provides an auditory interface to the solitaire game.
As you move you hear the coordinates and state of the current
cell.  Moving a stone produces an auditory icon.  You can examine
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
  (emacsvox-icon 'open-object)
  (emacsvox-solitaire-setup-keymap)
  (message "Welcome to Solitaire"))

(add-hook
 'solitaire-mode-hook
 #'emacsvox-solitaire-setup)

;;;   add keybindings

(defun emacsvox-solitaire-setup-keymap ()
  "Setup emacsvox keybindings for solitaire"
  
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
