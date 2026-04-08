;;; emacsvox-tcl.el --- Speech enable TCL -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for tcl-mode
;; Keywords:emacsvox, audio interface to emacs tcl
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman 
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.



;;; Commentary:
;; Provide additional advice to tcl-mode 
;;; Code:

;;;  requires
(require 'emacsvox-preamble)

;;;  voice locking:

;;  Snarfed from tcl.el /usr/local/lib/emacs/site-lisp/tcl.el

(defvar tcl-proc-list
  '("proc" "method" "itcl_class" "public" "protected")
  "List of commands whose first argument defines something.
This exists because some people (eg, me) use \"defvar\" et al. ")

(defvar tcl-proc-regexp
  (concat "^\\("
          (mapconcat 'identity tcl-proc-list "\\|")
          "\\)[ \t]+")
  "Regexp to use when matching proc headers.")

(defvar tcl-typeword-list
  '("global" "upvar")
  "List of Tcl keywords denoting \"type\".  Used only for highlighting. ")

;; Generally I've picked control operators to be keywords.
(defvar tcl-keyword-list
  '("if" "then" "else" "elseif" "for" "foreach" "break" "continue" "while"
    "set" "eval" "case" "in" "switch" "default" "exit" "error" "proc" "return"
    "uplevel" "cl-loop" "for_array_keys" "for_recursive_glob" "for_file"
    "unwind_protect" 
    ;; itcl
    "method" "itcl_class")
  "List of Tcl keywords.  Used only for highlighting.
Default list includes some TclX keywords. ")

;;;   Advice electric insertion to talk:

(defun ems--tcl-electric-hash-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'tcl-electric-hash :after #'ems--tcl-electric-hash-after)

(defun ems--tcl-electric-char-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'tcl-electric-char :after #'ems--tcl-electric-char-after)

(defun ems--tcl-electric-brace-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'tcl-electric-brace :after #'ems--tcl-electric-brace-after)

;;;   Actions in the tcl mode buffer:

(defun ems--switch-to-tcl-before (&rest _)
  "Announce yourself."
  (when (ems-interactive-p)
    (message "Switching to the Inferior TCL buffer")))

(advice-add 'switch-to-tcl :before #'ems--switch-to-tcl-before)

(defun ems--tcl-eval-region-after (&rest _)
  "Announce what you did."
  (when (ems-interactive-p) (message "Evaluating contents of region")))

(advice-add 'tcl-eval-region :after #'ems--tcl-eval-region-after)

(defun ems--tcl-eval-defun-after (&rest _)
  "Announce what you did"
  (when (ems-interactive-p)
    (let*
        ((start nil)
         (proc-line
          (save-excursion
            (tcl-beginning-of-defun) (setq start (point))
            (end-of-line) (buffer-substring start (point)))))
      (message "Evaluated  %s" proc-line))))

(advice-add 'tcl-eval-defun :after #'ems--tcl-eval-defun-after)

(defun ems--tcl-help-on-word-after (&rest _)
  "Speak  the help."
  (when (ems-interactive-p)
    (emacsvox-icon 'help)
    (with-current-buffer "*Tcl help*" (emacsvox-speak-buffer))))

(advice-add 'tcl-help-on-word :after #'ems--tcl-help-on-word-after)

;;;   Program structure:

(defun ems--tcl-mark-defun-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (message "Marked procedure")))

(advice-add 'tcl-mark-defun :after #'ems--tcl-mark-defun-after)

(defun ems--tcl-beginning-of-defun-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'paragraph) (emacsvox-speak-line)))

(advice-add 'tcl-beginning-of-defun :after
            #'ems--tcl-beginning-of-defun-after)

(defun ems--tcl-end-of-defun-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'paragraph)))

(advice-add 'tcl-end-of-defun :after #'ems--tcl-end-of-defun-after)

(defun ems--indent-tcl-exp-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p) (emacsvox-icon 'fill-object)))

(advice-add 'indent-tcl-exp :after #'ems--indent-tcl-exp-after)

(defun ems--tcl-indent-line-after (&rest _)
  "Speak the line" (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'tcl-indent-line :after #'ems--tcl-indent-line-after)

(provide  'emacsvox-tcl)

