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


;;; Commentary:

;; This speech-enables python-mode bundled with Emacs

;;; Code:

;;   Required modules:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)

(require 'python "python" 'no-error)

;;;  Semantic aural presentation:

(defun emacsvox-python-enable-aural-context ()
  "Identify the current Python buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'python))

(add-hook 'python-mode-hook #'emacsvox-python-enable-aural-context)

(defun emacsvox-python-navigation-facts (target)
  "Return semantic navigation facts for Python command TARGET."
  (let* ((name (symbol-name target))
         (syntax-role
          (cond
           ((string-match-p "defun" name) 'function)
           ((string-match-p "block" name) 'block)
           ((string-match-p "statement" name) 'statement)
           ((string-match-p "sexp\\|list" name) 'expression)
           ((string-match-p "if-name-main" name) 'main-guard)
           (t 'construct))))
    (list
     :role 'code-construct
     :events '(boundary-entered focus-entered)
     :syntax-role syntax-role)))

(defun emacsvox-python--submit-edit-feedback (icon text)
  "Submit Python edit TEXT with optional leading compatibility ICON."
  (emacsvox-aural-submit
   text
   :facts
   '(:role code-construct :events (object-changed) :syntax-role block)
   :module 'python
   :occasion 'edit
   :compatibility-actions
   (and icon (list (emacsvox-aural-compatibility-icon icon)))))

;;;  interactive programming

(defun emacsvox-python--task-done (target)
  "Cue completion when TARGET is the interactive Python command."
  (when (ems-interactive-p target)
    (emacsvox-icon 'task-done)))

(defun emacsvox--advice-python-check-after (&rest _)
  "Cue completion of an interactive Python check."
  (emacsvox-python--task-done 'python-check))

(advice-add 'python-check :after
            #'emacsvox--advice-python-check-after)

(defun emacsvox--advice-python-shell-send-region-after (&rest _)
  "Cue completion after sending a region interactively."
  (emacsvox-python--task-done 'python-shell-send-region))

(advice-add 'python-shell-send-region :after
            #'emacsvox--advice-python-shell-send-region-after)

(defun emacsvox--advice-python-shell-send-defun-after (&rest _)
  "Cue completion after sending a defun interactively."
  (emacsvox-python--task-done 'python-shell-send-defun))

(advice-add 'python-shell-send-defun :after
            #'emacsvox--advice-python-shell-send-defun-after)

(defun emacsvox--advice-python-shell-send-file-after (&rest _)
  "Cue completion after sending a file interactively."
  (emacsvox-python--task-done 'python-shell-send-file))

(advice-add 'python-shell-send-file :after
            #'emacsvox--advice-python-shell-send-file-after)

(defun emacsvox--advice-python-shell-send-buffer-after (&rest _)
  "Cue completion after sending a buffer interactively."
  (emacsvox-python--task-done 'python-shell-send-buffer))

(advice-add 'python-shell-send-buffer :after
            #'emacsvox--advice-python-shell-send-buffer-after)

(defun emacsvox--advice-python-shell-send-string-after (&rest _)
  "Cue completion after sending a string interactively."
  (emacsvox-python--task-done 'python-shell-send-string))

(advice-add 'python-shell-send-string :after
            #'emacsvox--advice-python-shell-send-string-after)

;;;   whitespace management and indentation

(defun emacsvox--advice-python-indent-dedent-line-after (&rest _)
  "speak."
  (when (ems-interactive-p 'python-indent-dedent-line)
    (emacsvox-speak-line) (emacsvox-icon 'right)))

(advice-add 'python-indent-dedent-line :after
            #'emacsvox--advice-python-indent-dedent-line-after)

(defun emacsvox--advice-python-indent-dedent-line-backspace-around
    (orig-fun arg)
  "Speak character you're deleting."
  (if (ems-interactive-p 'python-indent-dedent-line-backspace)
      (let ((ws (= 32 (char-syntax (preceding-char)))))
        (emacsvox-speak-edit-operation 'deletion)
        (unless ws
          (emacsvox-speak-this-char (preceding-char)))
        (prog1 (funcall orig-fun arg)
          (when ws
            (tts-notify (format "Indent %s " (current-column))))))
    (funcall orig-fun arg)))

(advice-add 'python-indent-dedent-line-backspace :around
            #'emacsvox--advice-python-indent-dedent-line-backspace-around)

(defun emacsvox--advice-python-fill-paragraph-after (&rest _)
  "Cue an interactive paragraph fill."
  (when (ems-interactive-p 'python-fill-paragraph)
    (emacsvox-icon 'fill-object)))

(advice-add 'python-fill-paragraph :after
            #'emacsvox--advice-python-fill-paragraph-after)

(defun emacsvox--advice-python-indent-shift-left-after
    (start end &rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'python-indent-shift-left)
    (emacsvox-python--submit-edit-feedback
     'left
     (format "Left shifted block  containing %s lines"
             (count-lines start end)))))

(advice-add 'python-indent-shift-left :after
            #'emacsvox--advice-python-indent-shift-left-after)

(defun emacsvox--advice-python-indent-shift-right-after
    (start end &rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'python-indent-shift-right)
    (emacsvox-python--submit-edit-feedback
     nil
     (format "Right shifted block  containing %s lines"
             (count-lines start end)))))

(advice-add 'python-indent-shift-right :after
            #'emacsvox--advice-python-indent-shift-right-after)

(defun emacsvox--advice-python-indent-region-after (start end)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'indent-region)
    (emacsvox-python--submit-edit-feedback
     'right
     (format "Indented region   containing %s lines"
             (count-lines start end)))))

(advice-add 'python-indent-region :after
            #'emacsvox--advice-python-indent-region-after)

;;;   buffer navigation

(defun emacsvox--advice-python-mark-defun-after (&rest _)
  "speak."
  (when (ems-interactive-p 'python-mark-defun)
    (emacsvox-icon 'mark-object)
    (message "Marked function containing %s lines"
             (count-lines (point) (mark 'force)))))

(advice-add 'python-mark-defun :after
            #'emacsvox--advice-python-mark-defun-after)

(defun emacsvox-python--navigation-feedback (target)
  "Speak the current line when TARGET is the interactive command."
  (when (ems-interactive-p target)
    (let* ((facts (emacsvox-python-navigation-facts target))
           (context
            (emacsvox-aural-capture-context 'python 'navigation))
           (emacsvox-aural-submission-facts facts)
           (emacsvox-aural-submission-context context)
           (emacsvox-aural-submission-module 'python)
           (emacsvox-aural-submission-occasion 'navigation))
      (let (spoken)
        (emacsvox-speak-line-with-speaker
         (lambda (content)
           (setq spoken t)
           (emacsvox-aural-submit
            content
            :facts facts
            :context context
            :module 'python
            :occasion 'navigation
            :compatibility-actions
            (list
             (emacsvox-aural-compatibility-icon
              'paragraph 'after)))))
        (unless spoken
          (emacsvox-icon 'paragraph))))))

(defun emacsvox--advice-python-nav-up-list-after (&rest _)
  "Speak after navigating up a list."
  (emacsvox-python--navigation-feedback 'python-nav-up-list))

(advice-add 'python-nav-up-list :after
            #'emacsvox--advice-python-nav-up-list-after)

(defun emacsvox--advice-python-nav-if-name-main-after (&rest _)
  "Speak after navigating to the main guard."
  (emacsvox-python--navigation-feedback 'python-nav-if-name-main))

(advice-add 'python-nav-if-name-main :after
            #'emacsvox--advice-python-nav-if-name-main-after)

(defun emacsvox--advice-python-nav-forward-statement-after (&rest _)
  "Speak after navigating forward by statement."
  (emacsvox-python--navigation-feedback 'python-nav-forward-statement))

(advice-add 'python-nav-forward-statement :after
            #'emacsvox--advice-python-nav-forward-statement-after)

(defun emacsvox--advice-python-nav-forward-sexp-safe-after (&rest _)
  "Speak after safe forward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-sexp-safe))

(advice-add 'python-nav-forward-sexp-safe :after
            #'emacsvox--advice-python-nav-forward-sexp-safe-after)

(defun emacsvox--advice-python-nav-forward-sexp-after (&rest _)
  "Speak after forward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-sexp))

(advice-add 'python-nav-forward-sexp :after
            #'emacsvox--advice-python-nav-forward-sexp-after)

(defun emacsvox--advice-python-nav-forward-defun-after (&rest _)
  "Speak after forward defun navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-defun))

(advice-add 'python-nav-forward-defun :after
            #'emacsvox--advice-python-nav-forward-defun-after)

(defun emacsvox--advice-python-nav-forward-block-after (&rest _)
  "Speak after forward block navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-block))

(advice-add 'python-nav-forward-block :after
            #'emacsvox--advice-python-nav-forward-block-after)

(defun emacsvox--advice-python-nav-end-of-statement-after (&rest _)
  "Speak after moving to the end of a statement."
  (emacsvox-python--navigation-feedback 'python-nav-end-of-statement))

(advice-add 'python-nav-end-of-statement :after
            #'emacsvox--advice-python-nav-end-of-statement-after)

(defun emacsvox--advice-python-nav-end-of-defun-after (&rest _)
  "Speak after moving to the end of a defun."
  (emacsvox-python--navigation-feedback 'python-nav-end-of-defun))

(advice-add 'python-nav-end-of-defun :after
            #'emacsvox--advice-python-nav-end-of-defun-after)

(defun emacsvox--advice-python-nav-end-of-block-after (&rest _)
  "Speak after moving to the end of a block."
  (emacsvox-python--navigation-feedback 'python-nav-end-of-block))

(advice-add 'python-nav-end-of-block :after
            #'emacsvox--advice-python-nav-end-of-block-after)

(defun emacsvox--advice-python-nav-beginning-of-statement-after (&rest _)
  "Speak after moving to the beginning of a statement."
  (emacsvox-python--navigation-feedback 'python-nav-beginning-of-statement))

(advice-add 'python-nav-beginning-of-statement :after
            #'emacsvox--advice-python-nav-beginning-of-statement-after)

(defun emacsvox--advice-python-nav-beginning-of-block-after (&rest _)
  "Speak after moving to the beginning of a block."
  (emacsvox-python--navigation-feedback 'python-nav-beginning-of-block))

(advice-add 'python-nav-beginning-of-block :after
            #'emacsvox--advice-python-nav-beginning-of-block-after)

(defun emacsvox--advice-python-nav-backward-up-list-after (&rest _)
  "Speak after navigating backward up a list."
  (emacsvox-python--navigation-feedback 'python-nav-backward-up-list))

(advice-add 'python-nav-backward-up-list :after
            #'emacsvox--advice-python-nav-backward-up-list-after)

(defun emacsvox--advice-python-nav-backward-statement-after (&rest _)
  "Speak after navigating backward by statement."
  (emacsvox-python--navigation-feedback 'python-nav-backward-statement))

(advice-add 'python-nav-backward-statement :after
            #'emacsvox--advice-python-nav-backward-statement-after)

(defun emacsvox--advice-python-nav-backward-sexp-safe-after (&rest _)
  "Speak after safe backward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-sexp-safe))

(advice-add 'python-nav-backward-sexp-safe :after
            #'emacsvox--advice-python-nav-backward-sexp-safe-after)

(defun emacsvox--advice-python-nav-backward-sexp-after (&rest _)
  "Speak after backward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-sexp))

(advice-add 'python-nav-backward-sexp :after
            #'emacsvox--advice-python-nav-backward-sexp-after)

(defun emacsvox--advice-python-nav-backward-defun-after (&rest _)
  "Speak after backward defun navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-defun))

(advice-add 'python-nav-backward-defun :after
            #'emacsvox--advice-python-nav-backward-defun-after)

(defun emacsvox--advice-python-nav-backward-block-after (&rest _)
  "Speak after backward block navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-block))

(advice-add 'python-nav-backward-block :after
            #'emacsvox--advice-python-nav-backward-block-after)

(provide 'emacsvox-python)
;;;  end of file
