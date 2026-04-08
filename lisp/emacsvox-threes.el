;;; emacsvox-threes.el --- Speech-enable THREES  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable THREES An Emacs Interface to threes
;; Keywords: Emacsvox,  Audio Desktop threes
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
;; MERCHANTABILITY or FITNTHREES FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; 
;; THREES == threes game. This module speech-enable the
;; game. @url{https://en.wikipedia.org/wiki/Threes} for history of the
;; game and details of game play. This module adds additional
;; convenience keybindings to the default arrow-key bindings
;; implemented in threes.el. In addition, this module implements
;; commands that speak the board as well as getting a column-specific
;; view of the board.
;; 
;; @table @kbd
;; @item  f
;; Move right
;; @item b
;; Move left
;; @item n
;; Move down
;; @item p
;; Move up
;; @item SPC
;; Speak the board
;; @item /
;; Speak board by column.
;; @item .
;; Speak current score.
;; @item ,
;; Speak  number of zeros on the board.
;; @item s
;; Save current state
;; @item u
;; Pop state from stack
;; @item ?
;; Speak next tile
;; @end table
;; The updated board is spoken after each turn.
;; The next upcoming tile is spoken after the  current state of the board.
;; You can use @kbd{SPC} and @kbd{/} to review the board.
;; 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'sox-gen)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (threes-face-0 voice-smoothen)
   (threes-face-1 voice-monotone-extra)
   (threes-face-2 voice-brighten)
   (threes-face-3 voice-bolden)
   (threes-face-max voice-animate)))

;;;  Variables:

(defvar emacsvox-threes-rows-max '(0 0 0 0)
  "Max for each row.")

(defun emacsvox-threes-get-rows-max ()
  "Return max for each row."
  
  (mapcar #'(lambda (r) (apply #'max   r)) threes-cells))

;;;  Helpers:

(cl-loop
 for i in'(0 1 2 3) do
 (eval
  `(defun  ,(intern  (format "emacsvox-threes-%s" i)) ()
     "Set next tile."
     (interactive)
     
     (setq threes-next-number ,i)
     (emacsvox-threes-speak-board))))

(defun emacsvox-threes-sox-gen (number)
  "Generate a tone  that indicates 1, 2 or 3."
  (let ((fade "fade h .1 .5 .4 gain -8 "))
    (cond
     ((= 1 number) (sox-sin .5 "%-2:%-1"fade))
     ((= 2 number) (sox-sin .5 "%1:%3" fade))
     ((= 3 number) (sox-sin .5 "%4:%6"fade)))))

;;;  Advice interactive commands:

(defun emacsvox-threes-speak-board ()
  "Speak the board."
  (interactive)
  
  (when threes-game-over-p (emacsvox-icon 'alarm))
  (emacsvox-threes-sox-gen threes-next-number)
  (let ((cells (apply #'append (copy-sequence threes-cells)))
        (next
         (list (propertize
                (format "%s" threes-next-number) 'personality voice-bolden))))
    (dtk-speak-list (append cells next) 4)
    (emacsvox-icon 'select-object)))

(defun emacsvox-threes-speak-empty-count ()
  "Speak number of cells that are non-empty."
  (interactive)
  
  (dtk-speak
   (format " %d zeros"
           (apply #'+
                  (mapcar #'(lambda (s) (cl-count-if #'zerop s))
                          threes-cells)))))

(defun emacsvox-threes-speak-next ()
  "Speak upcoming tile."
  (interactive)
  (emacsvox-threes-sox-gen threes-next-number)
  (dtk-speak (format "%s" threes-next-number)))

(defun emacsvox-threes-speak-transposed-board ()
  "Speak the board by columns."
  (interactive)
  
  (dtk-speak-list   (threes-cells-transpose threes-cells) 4)
  (emacsvox-icon 'progress))

(defun emacsvox-threes-setup ()
  "Set up additional key-bindings."
  
  (define-key threes-mode-map "1" 'emacsvox-threes-1)
  (define-key threes-mode-map "0" 'emacsvox-threes-0)
  (define-key threes-mode-map "2" 'emacsvox-threes-2)
  (define-key threes-mode-map "3" 'emacsvox-threes-3)
  (define-key threes-mode-map "#" 'emacsvox-threes-prune-stack)
  (define-key threes-mode-map "e" 'emacsvox-threes-export)
  (define-key threes-mode-map "i" 'emacsvox-threes-import)
  (define-key threes-mode-map "s" 'emacsvox-threes-push-state)
  (define-key threes-mode-map "u" 'emacsvox-threes-pop-state)
  (define-key threes-mode-map "g" 'threes)
  (define-key threes-mode-map " " 'emacsvox-threes-speak-board)
  (define-key threes-mode-map "." 'emacsvox-threes-score)
  (define-key threes-mode-map "," 'emacsvox-threes-speak-empty-count)
  (define-key threes-mode-map "/" 'emacsvox-threes-speak-transposed-board)
  (define-key threes-mode-map "?" 'emacsvox-threes-speak-next)
  (define-key threes-mode-map "n" 'threes-down)
  (define-key threes-mode-map "p" 'threes-up)
  (define-key threes-mode-map "f" 'threes-right)
  (define-key threes-mode-map "b" 'threes-left))

(defun ems--threes-after (&rest _)
  "speak." (setq threes-game-over-p nil) (random t)
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-threes-speak-board)))

(advice-add 'threes :after #'ems--threes-after)

(declare-function threes-cells-score "threes" nil)
(declare-function threes-cells-transpose "threes" (cells))

(defun emacsvox-threes-score ()
  "Speak the score."
  (interactive)
  (message (format "Score: %s" (number-to-string (threes-cells-score)))))

(cl-loop
 for f in
 '(threes-up threes-down threes-left threes-right)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak"
     (when (ems-interactive-p)
       (emacsvox-threes-speak-board)))))

(defun ems--threes-check-before-move-before (&rest _)
  "Cache max"
  (setq emacsvox-threes-rows-max (emacsvox-threes-get-rows-max)))

(advice-add 'threes-check-before-move :before
            #'ems--threes-check-before-move-before)

(when (boundp 'threes-mode-map)
  (emacsvox-threes-setup))

;;;  Push And Pop states:

(cl-defstruct emacsvox-threes-game-state
  board)

(defvar emacsvox-threes-game-stack nil
  "Stack of saved states.")

(defun emacsvox-threes-push-state ()
  "Push current game state on stack."
  (interactive)
  
  (push
   (make-emacsvox-threes-game-state
    :board (copy-sequence threes-cells))
   emacsvox-threes-game-stack)
  (emacsvox-icon 'mark-object)
  (message "Saved state."))
(declare-function threes-print-board "threes.el" nil)
(defun emacsvox-threes-pop-state ()
  "Reset state from stack."
  (interactive)
  (cl-declare (special emacsvox-threes-game-stack threes-cells
                       threes-game-over-p))
  (cond
   ((null emacsvox-threes-game-stack) (error "No saved  states."))
   (t
    (setq threes-game-over-p nil)
    (let ((state (pop emacsvox-threes-game-stack)))
      (setq threes-cells (emacsvox-threes-game-state-board state))
      (threes-print-board)
      (emacsvox-icon 'yank-object)
      (message "Popped: Score is now %s" (threes-cells-score))))))

(defun emacsvox-threes-prune-stack (drop)
  "Prune game stack to specified length."
  (interactive
   (list
    (cond
     ((null emacsvox-threes-game-stack) (error "No saved  states."))
     (t (read-number
         (format "Stack: %s New? "
                 (length emacsvox-threes-game-stack))
         (/ (length emacsvox-threes-game-stack) 2))))))
  
  (setq emacsvox-threes-game-stack
        (butlast emacsvox-threes-game-stack
                 (- (length emacsvox-threes-game-stack) drop)))
  (message "Stack is now %s deep"
           (length emacsvox-threes-game-stack))
  (emacsvox-icon 'delete-object))

;;;  Export And Import Games:

(defvar emacsvox-threes-game-file
  (expand-file-name "threes-game-stack"
                    emacsvox-user-directory)
  "File where we export/import game state.")

(defun emacsvox-threes-export (&optional prompt)
  "Exports game stack to a file.
Optional interactive prefix arg prompts for a file.
Note that the file is overwritten silently."
  (interactive "P")
  
  (with-temp-buffer
    (let ((file
           (if prompt
               (read-file-name "File to save game to: ")
             emacsvox-threes-game-file))
          (print-length nil)
          (print-level nil))
      (insert "(setq emacsvox-threes-game-stack \n'")
      (pp emacsvox-threes-game-stack (current-buffer))
      (insert ")\n")
      (write-file file)
      (emacsvox-icon 'save-object)
      (message "Exported game to %s." file))))

(defun emacsvox-threes-import (&optional prompt)
  "Import game.
Optional interactive prefix arg prompts for a filename."
  (interactive "P")
  (let ((file
         (if prompt
             (read-file-name "File to import game from: ")
           emacsvox-threes-game-file)))
    (load-file file)
    (emacsvox-icon 'task-done)
    (message "Imported game %s." file)))

(provide 'emacsvox-threes)
;;;  end of file

