;;; emacsvox-python.el --- Speech enable Python -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: Auditory interface to python mode
;; Keywords: Emacsvox, Speak, Spoken Output, python
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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


;;; Commentary:

;; This speech-enables python-mode available on sourceforge and ELPA

;;; Code:

;;   Required modules:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

(with-no-warnings (require 'python-mode "python-mode" 'no-error))

;;;   electric editing

(defun ems--py-electric-backspace-around (orig-fun &rest args)
  "Speak character you're deleting.\nProvide contextual feedback when closing blocks"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((ws (= (char-syntax (preceding-char)) 32)))
        (dtk-tone 500 100 'force)
        (unless ws (emacsvox-speak-this-char (preceding-char)))
        (apply orig-fun args)
        (when ws
          (dtk-notify (format "Indent %s " result))
          (emacsvox-icon 'close-object) (sit-for 0.2)
          (save-excursion
            (py-beginning-of-block) (emacsvox-speak-line)))))
     (t (apply orig-fun args)))
    result))

(advice-add 'py-electric-backspace :around
            #'ems--py-electric-backspace-around)

(defun ems--py-electric-delete-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone 500 100 'force)
      (emacsvox-speak-this-char (preceding-char))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))

(advice-add 'py-electric-delete :around
            #'ems--py-electric-delete-around)

;;;  interactive programming

(defun ems--py-shell-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'py-shell :after #'ems--py-shell-after)

(defun ems--py-clear-queue-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'py-clear-queue :after #'ems--py-clear-queue-after)

(defun ems--py-execute-region-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'py-execute-region :after #'ems--py-execute-region-after)

(defun ems--py-execute-buffer-after (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'task-done)))

(advice-add 'py-execute-buffer :after #'ems--py-execute-buffer-after)

(defun ems--py-goto-exception-after (&rest _)
  "Speak line you moved to"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'py-goto-exception :after #'ems--py-goto-exception-after)

(defun ems--py-down-exception-after (&rest _)
  "Speak line you moved to"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'py-down-exception :after #'ems--py-down-exception-after)

(defun ems--py-up-exception-after (&rest _)
  "Speak line you moved to"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'py-up-exception :after #'ems--py-up-exception-after)

;;;   whitespace management and indentation

(cl-loop
 for f in
 (list 'py-fill-paragraph 'py-fill-comment 'py-fill-string)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'fill-object)))))

(defun ems--py-newline-and-indent-after (&rest _)
  "Speak line so we know current indentation"
  (when (ems-interactive-p)
    (dtk-speak-using-voice voice-annotate
                           (format "indent %s" (current-column)))
    (dtk-interp-speak)))

(advice-add 'py-newline-and-indent :after
            #'ems--py-newline-and-indent-after)

(defun ems--py-shift-region-left-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p)
    (emacsvox-icon 'left)
    (dtk-speak
     (format "Left shifted block  containing %s lines"
             (count-lines (region-beginning) (region-end))))))

(advice-add 'py-shift-region-left :after
            #'ems--py-shift-region-left-after)

(defun ems--py-shift-region-right-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p)
    (dtk-speak
     (format "Right shifted block  containing %s lines"
             (count-lines (region-beginning) (region-end))))))

(advice-add 'py-shift-region-right :after
            #'ems--py-shift-region-right-after)

(defun ems--py-indent-region-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p)
    (emacsvox-icon 'right)
    (dtk-speak
     (format "Indented region   containing %s lines"
             (count-lines (region-beginning) (region-end))))))

(advice-add 'py-indent-region :after #'ems--py-indent-region-after)

(defun ems--py-comment-region-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p)
    (dtk-speak
     (format "Commented  block  containing %s lines"
             (count-lines (region-beginning) (region-end))))))

(advice-add 'py-comment-region :after #'ems--py-comment-region-after)

;;;   buffer navigation
(cl-loop
 for f in
 '(
   py-goto-block-or-clause-up py-goto-clause-up
   py-previous-class py-previous-clause py-previous-def-or-class
   py-forward-block
   py-forward-block-bol
   py-forward-block-or-clause
   py-forward-block-or-clause-bol
   py-forward-buffer
   py-forward-class
   py-forward-class-bol
   py-forward-clause
   py-forward-clause-bol
   py-forward-comment
   py-forward-decorator
   py-forward-def-bol
   py-forward-def-or-class-bol
   py-forward-elif-block
   py-forward-elif-block-bol
   py-forward-else-block
   py-forward-else-block-bol
   py-forward-except-block
   py-forward-except-block-bol
   py-forward-expression
   py-forward-for-block
   py-forward-for-block-bol
   py-forward-function
   py-forward-if-block
   py-forward-if-block-bol
   py-forward-line
   py-forward-minor-block
   py-forward-minor-block-bol
   py-forward-paragraph
   py-forward-partial-expression
   py-forward-section
   py-forward-statement-bol
   py-forward-statements
   py-forward-top-level
   py-forward-top-level-bol
   py-forward-try-block
   py-forward-try-block-bol
   py-backward-block py-backward-block-bol
   py-backward-block-or-clause py-backward-block-or-clause-bol
   py-backward-class py-backward-class-bol
   py-backward-clause py-backward-clause-bol
   py-backward-comment py-backward-decorator py-backward-decorator-bol
   py-backward-def-bol py-backward-def-or-class-bol
   py-backward-elif-block py-backward-elif-block-bol
   py-backward-else-block py-backward-else-block-bol
   py-backward-except-block py-backward-except-block-bol
   py-backward-expression py-backward-for-block py-backward-for-block-bol
   py-backward-function py-backward-if-block py-backward-if-block-bol
   py-backward-line py-backward-minor-block py-backward-minor-block-bol
   py-backward-paragraph py-backward-partial-expression py-backward-same-level
   py-backward-section py-backward-statement-bol py-backward-statements
   py-backward-top-level py-backward-top-level-p
   py-backward-try-block py-backward-try-block-bol
   py-match-paren py-indent-or-complete
   py-beginning py-beginning-of-block-bol
   py-beginning-of-block-current-column
   py-beginning-of-block-or-clause py-beginning-of-class
   py-beginning-of-class-bol
   py-beginning-of-clause-bol py-beginning-of-comment
   py-beginning-of-declarations
   py-beginning-of-decorator py-beginning-of-decorator-bol
   py-beginning-of-expression py-beginning-of-line
   py-beginning-of-list-pps
   py-beginning-of-minor-block
   py-beginning-of-partial-expression
   py-beginning-of-section py-beginning-of-statement-bol
   py-beginning-of-top-level
   py-forward-declarations py-backward-declarations
   py-down py-up
   py-down-block py-down-block-bol
   py-down-block-or-clause py-down-block-or-clause-bol
   py-down-class py-down-class-bol
   py-down-clause py-down-clause-bol
   py-down-def py-down-def-bol
   py-down-def-or-class py-down-def-or-class-bol
   py-down-minor-block py-down-minor-block-bol
   py-down-section py-down-section-bol
   py-down-statement py-down-top-level
   py-backward-statement py-forward-statement
   py-goto-block-up  py-go-to-beginning-of-comment
   py-end py-end-of-block-or-clause
   py-end-of-class py-end-of-comment
   py-end-of-decorator py-end-of-expression
   py-end-of-line py-end-of-list-position
   py-end-of-partial-expression py-end-of-section
   py-end-of-statement-bol py-end-of-string
   py-end-of-top-level
   py-beginning-of-statement py-end-of-statement
   py-beginning-of-block py-end-of-block
   py-beginning-of-clause py-end-of-clause
   py-next-statement py-previous-statement
   py-backward-def py-forward-def
   py-backward-def-or-class py-forward-def-or-class
   py-beginning-of-def-or-class py-end-of-def-or-class)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak current statement after moving"
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'paragraph)))))

(cl-loop
 for  f in
 '(
   py-mark-class-bol py-mark-clause py-mark-clause-bol py-mark-comment
   py-mark-comment-bol py-mark-def py-mark-def-bol
   py-mark-def-or-class py-mark-def-or-class-bol py-mark-except-block
   py-mark-except-block-bol py-mark-expression py-mark-expression-bol
   py-mark-if-block py-mark-if-block-bol py-mark-line py-mark-line-bol
   py-mark-minor-block py-mark-minor-block-bol py-mark-paragraph
   py-mark-paragraph-bol py-mark-partial-expression
   py-mark-partial-expression-bol py-mark-section py-mark-statement
   py-mark-statement-bol py-mark-top-level py-mark-top-level-bol
   py-mark-try-block py-mark-try-block-bol)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak number of lines marked"
     (when (ems-interactive-p)
       (dtk-speak
        (format
         "Marked block containing %s lines"
         (count-lines (region-beginning) (region-end))))
       (emacsvox-icon 'mark-object)))))

(cl-loop
 for f in
 '(

   Possible completions are:
   py-narrow-to-block  py-narrow-to-block-or-clause    py-narrow-to-class
   py-narrow-to-clause         py-narrow-to-def
   py-narrow-to-def-or-class
   py-narrow-to-statement
   )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (message "Narrowed  %s lines"
                (count-lines (point-min) (point-max)))))))

(defun ems--py-mark-def-or-class-after (&rest _)
  "Speak number of lines marked"
  (when (ems-interactive-p)
    (dtk-speak
     (format "Marked block containing %s lines"
             (count-lines (region-beginning) (region-end))))
    (emacsvox-icon 'mark-object)))

(advice-add 'py-mark-def-or-class :after
            #'ems--py-mark-def-or-class-after)

(defun ems--py-forward-into-nomenclature-after (&rest _)
  "Speak rest of current word"
  (when (ems-interactive-p) (emacsvox-speak-word 1)))

(advice-add 'py-forward-into-nomenclature :after
            #'ems--py-forward-into-nomenclature-after)

(defun ems--py-backward-into-nomenclature-after (&rest _)
  "Speak rest of current word"
  (when (ems-interactive-p) (emacsvox-speak-word 1)))

(advice-add 'py-backward-into-nomenclature :after
            #'ems--py-backward-into-nomenclature-after)

;;;  the process buffer

(defun ems--py-process-filter-around (orig-fun &rest args)
  "Make comint in Python speak its output. "
  (let ((result (apply orig-fun args)))
    
    (let ((prior (point)) (dtk-stop-immediately nil))
      (apply orig-fun args)
      (when
          (and emacsvox-comint-autospeak
               (window-live-p
                (get-buffer-window (process-buffer (ad-get-arg 0)))))
        (condition-case nil (emacsvox-speak-region prior (point))
          (error (emacsvox-icon 'scroll) (dtk-stop 'all))))
      result)
    result))

(advice-add 'py-process-filter :around #'ems--py-process-filter-around)

;;;  Voice Mappings:
(voice-setup-add-map
 '(
   (py-number-face voice-lighten)
   (py-XXX-tag-face voice-animate)
   (py-pseudo-keyword-face voice-animate-medium)
   (py-variable-name-face  voice-animate)
   (py-decorators-face voice-lighten)
   (py-builtins-face voice-smoothen)
   (py-class-name-face voice-bolden-extra)
   (py-exception-name-face voice-brighten)
   (py-def-class-face voice-lighten)
   (py-import-from-face voice-animate)
   (py-object-reference-face voice-bolden-and-animate)
   (py-try-if-face voice-lighten)
   ))

;;;  pydoc advice:

(defun ems--pydoc-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-rest-of-buffer)))

(advice-add 'pydoc :after #'ems--pydoc-after)

(defun ems--py-help-at-point-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'help) (dtk-stop 'all) (emacsvox-speak-buffer)))

(advice-add 'py-help-at-point :after #'ems--py-help-at-point-after)

(provide 'emacsvox-py)
;;;  end of file

