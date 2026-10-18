;;; emacsvox-2048.el --- Speech-enable 2048 Game -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop 2048
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
;; Speech-enable 2048 Game

;;; Code:

;;; Forward variable declarations:

(defvar *2048-board*)
(defvar *2048-columns*)
(defvar *2048-rows*)
(defvar *2048-score*)
(defvar emacsvox-2048-game-stack)

;;; Commentary:
;; 2048 ==

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require '2048-game "2048-game" 'no-error)

;;;  Push And Pop states:

(cl-defstruct emacsvox-2048-game-state
  board score
  rows cols
  )

(defvar emacsvox-2048-game-stack nil
  "Stack of saved states.")
(defun emacsvox-2048-push-state ()
  "Push current game state on stack."
  (interactive)
  (push
   (make-emacsvox-2048-game-state
    :board (copy-sequence *2048-board*)
    :score *2048-score*
    :rows *2048-rows*
    :cols *2048-columns*)
   emacsvox-2048-game-stack)
  (emacsvox-icon 'mark-object)
  (message "Saved state."))

(defun emacsvox-2048-pop-state ()
  "Reset state from stack."
  (interactive)
  (cond
   ((null emacsvox-2048-game-stack) (error "No saved  states."))
   (t
    (let ((state (pop emacsvox-2048-game-stack)))
      (setq
       *2048-board* (emacsvox-2048-game-state-board state)
       *2048-score* (emacsvox-2048-game-state-score state)
       *2048-rows* (emacsvox-2048-game-state-rows state)
       *2048-columns* (emacsvox-2048-game-state-cols state))
      (2048-print-board)
      (emacsvox-icon 'yank-object)
      (message "Popped: Score is now %s" *2048-score*)))))

(defun emacsvox-2048-prune-stack (drop)
  "Prune game stack to specified length."
  (interactive 
   (list
    (cond
     ((null emacsvox-2048-game-stack) (error "No saved  states."))
     (t (read-number
         (format "Stack: %s New? "
                 (length emacsvox-2048-game-stack))
         (/ (length emacsvox-2048-game-stack) 2))))))
  
  (setq emacsvox-2048-game-stack
        (butlast emacsvox-2048-game-stack
                 (- (length emacsvox-2048-game-stack) drop)))
  (message "Stack is now %s deep"
           (length emacsvox-2048-game-stack))
  (emacsvox-icon 'delete-object))

;;;  Export And Import Games:

(defvar emacsvox-2048-game-file
  (expand-file-name "2048-game-stack"
                    emacsvox-user-directory)
  "File where we export/import game state.")

(defun emacsvox-2048-export (&optional prompt)
  "Exports game stack to a file.
Optional interactive prefix arg prompts for a file.
Note that the file is overwritten silently."
  (interactive "P")
  
  (with-temp-buffer
    (let ((file
           (if prompt
               (read-file-name "File to save game to: ")
             emacsvox-2048-game-file))
          (print-length nil)
          (print-level nil))
      (insert "(setq emacsvox-2048-game-stack \n'")
      (pp emacsvox-2048-game-stack (current-buffer))
      (insert ")\n")
      (write-file file)
      (emacsvox-icon 'save-object)
      (message "Exported game to %s." file))))

(defun emacsvox-2048-import (&optional prompt)
  "Import game.
Optional interactive prefix arg prompts for a filename."
  (interactive "P")
  (let ((file
         (if prompt
             (read-file-name "File to import game from: ")
           emacsvox-2048-game-file)))
    (load-file file)
    (cl-loop
     for i in
     '(4096 8192 16384 32768 65536 131072) do
     (2048-init-tile i))
    (emacsvox-icon 'task-done)
    (message "Imported game %s." file)))

;;;  Adding rows and columns:

(defun emacsvox-2048-add-row ()
  "Add a row  to the current board."
  (interactive)
  
  (setq *2048-rows* (cl-incf *2048-rows*))
  (let ((board (copy-sequence *2048-board*)))
    (setq *2048-board* (make-vector (* *2048-columns* *2048-rows*) 0))
    (cl-loop
     for   i from 0 to (1- (length board)) do
     (aset  *2048-board* i  (aref board i))
     (2048-print-board))
    (message "Added row.")))

(defun emacsvox-2048-drop-row ()
  "Drop last  row  from  the current board."
  (interactive)
  
  (setq *2048-rows* (1- *2048-rows*))
  (let ((board (copy-sequence *2048-board*)))
    (setq *2048-board* (make-vector (* *2048-columns* *2048-rows*) 0))
    (cl-loop
     for   i from 0 to (1- (length *2048-board*)) do
     (aset  *2048-board* i  (aref board i))
     (2048-print-board))
    (emacsvox-icon 'delete-object)
    (message "Dropped row.")))

(defun emacsvox-2048-add-column ()
  "Add a column  to the current board."
  (interactive)
  
  (let ((board (copy-sequence *2048-board*))
        (index 0)
        (cols *2048-columns*))
    (setq *2048-columns* (cl-incf *2048-columns*))
    (setq *2048-board* (make-vector (* *2048-columns* *2048-rows*) 0))
    (cl-loop
     for r from 0 to (1- *2048-rows*) do
     (cl-loop
      for c from 0 to (1- cols) do
      (setq index (+ (* r cols) c))     ; old  board
      (aset *2048-board*
            (+ r index)
            (aref board index)))
     (message "Added column."))))

(defun emacsvox-2048-drop-column ()
  "Drop last  row  from  the current board."
  (interactive)
  
  (let ((board (copy-sequence *2048-board*))
        (bound 0))
    (setq *2048-columns* (1- *2048-columns*))
    (setq *2048-board* (make-vector (* *2048-columns* *2048-rows*) 0))
    (cl-loop
     for   i from 0 to (1- (length *2048-board*)) do
     (cond
      ((= bound *2048-columns*) (setq bound 0))
      (t
       (cl-incf bound)
       (aset  *2048-board* i  (aref board i)))))
    (2048-print-board))
  (emacsvox-icon 'delete-object)
  (message "Dropped column."))
(defun emacsvox-2048-board-reset ()
  "Reset board to default size."
  
  (setq *2048-rows* 4
        *2048-columns* 4))

;;;  Advice commands, bind one review command

(defun emacsvox-2048-speak-board ()
  "Speak board."
  (interactive)
  
  (tts-speak-list (append *2048-board* nil) *2048-columns*))

(defun emacsvox-2048-speak-transposed-board ()
  "Speak board column-wise."
  (interactive)
  
  (tts-speak-list
   (cl-loop for col from 0 to (- *2048-columns*  1)
            collect
            (cl-loop for row from 0 to (- *2048-rows*  1)
                     collect
                     (aref  *2048-board*  (+ col (* 4 row)))))
   *2048-rows*))

(defconst emacsvox-2048--move-targets
  '(2048-left 2048-right 2048-down 2048-up)
  "2048 movement commands that receive spoken board feedback.")

(cl-loop
 for target in emacsvox-2048--move-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak"
     (when (ems-interactive-p ',target)
       (cond
        ((cl-some #'identity *2048-combines-this-move*)
         (emacsvox-icon 'item))
        (t (emacsvox-icon 'close-object)))
       (emacsvox-2048-speak-board)
       (cond
        ((2048-game-was-won) (emacsvox-icon 'task-done))
        ((2048-game-was-lost) (emacsvox-icon 'alarm)))))))

(defun emacsvox--advice-2048-insert-random-cell-after (&rest _)
  "Provide auditory icon" (emacsvox-icon 'item))

(defconst emacsvox-2048--advice-targets
  (append emacsvox-2048--move-targets '(2048-insert-random-cell))
  "Current 2048 targets that receive native after advice.")

(defun emacsvox-2048--install-advice ()
  "Install advice after the optional 2048 package loads."
  (dolist (target emacsvox-2048--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load '2048-game
  (emacsvox-2048--install-advice))

(defun emacsvox-2048-score ()
  "Show total on board."
  (interactive)
  
  (message (format "Score: %d" *2048-score*)))

;;;  Setup
(declare-function
 emacsvox-pronounce-add-local-entry
 "emacsvox-pronounce" (word pron))

(defun emacsvox-2048-setup ()
  "Emacsvox setup for 2048."
  (cl-declaim (special  2048-mode-map))
  (voice-lock-mode -1)
  (define-key 2048-mode-map "#" 'emacsvox-2048-prune-stack)
  (define-key 2048-mode-map "D" 'emacsvox-2048-drop-row)
  (define-key 2048-mode-map "d" 'emacsvox-2048-drop-column)
  (define-key 2048-mode-map "P" 'emacsvox-2048-prune-stack)
  (define-key 2048-mode-map "R" 'emacsvox-2048-add-row)
  (define-key 2048-mode-map "C" 'emacsvox-2048-add-column)
  (define-key 2048-mode-map "e" 'emacsvox-2048-export)
  (define-key 2048-mode-map "i" 'emacsvox-2048-import)
  (define-key 2048-mode-map " " 'emacsvox-2048-speak-board)
  (define-key 2048-mode-map "s" 'emacsvox-2048-push-state)
  (define-key 2048-mode-map "u"  'emacsvox-2048-pop-state)
  (define-key 2048-mode-map [delete]  'emacsvox-2048-pop-state)
  (define-key 2048-mode-map "/" 'emacsvox-2048-speak-transposed-board)
  (define-key 2048-mode-map  "="'emacsvox-2048-score)
  (define-key 2048-mode-map  "r"'emacsvox-2048-randomize-game)
  (define-key 2048-mode-map  (kbd "C-SPC") 'emacsvox-2048-score)
  (define-key 2048-mode-map "g" '2048-game)
  (tts-set-rate
   (+ tts-speech-rate-base
      (* tts-speech-rate-step  3)))
  (tts-apply-punctuation-mode-policy)
  (emacsvox-icon 'open-object)
  (emacsvox-pronounce-add-local-entry "0" "o")
  (emacsvox-2048-speak-board))
(cl-declaim (special-display-p 2048-mode-hook))
(add-hook '2048-mode-hook 'emacsvox-2048-setup)

;;;  Randomize game

(defun emacsvox-2048-randomize-game (&optional count)
  "Puts game in a randomized new state."
  (interactive "nCount: ")
  
  (cl-loop
   for i from 0 to 15 do
   (cond
    ((< i  count)
     (aset *2048-board* i
           (ash 2 (random (random count)))))
    (t (aset *2048-board* i 0))))
  (emacsvox-2048-speak-board))

(provide 'emacsvox-2048)

;;; emacsvox-2048.el ends here
