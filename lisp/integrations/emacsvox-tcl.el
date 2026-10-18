;;; emacsvox-tcl.el --- Speech enable TCL -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs tcl
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

(defun emacsvox--advice-tcl-electric-hash-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p 'tcl-electric-hash)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'tcl-electric-hash :after
            #'emacsvox--advice-tcl-electric-hash-after)

(defun emacsvox--advice-tcl-electric-char-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p 'tcl-electric-char)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'tcl-electric-char :after
            #'emacsvox--advice-tcl-electric-char-after)

(defun emacsvox--advice-tcl-electric-brace-after (&rest _)
  "Speak what you inserted."
  (when (ems-interactive-p 'tcl-electric-brace)
    (emacsvox-speak-this-char last-input-event)))

(advice-add 'tcl-electric-brace :after
            #'emacsvox--advice-tcl-electric-brace-after)

;;;   Actions in the tcl mode buffer:

(defun emacsvox--advice-switch-to-tcl-before (&rest _)
  "Announce yourself."
  (when (ems-interactive-p 'switch-to-tcl)
    (message "Switching to the Inferior TCL buffer")))

(advice-add 'switch-to-tcl :before
            #'emacsvox--advice-switch-to-tcl-before)

(defun emacsvox--advice-tcl-eval-region-after (&rest _)
  "Announce what you did."
  (when (ems-interactive-p 'tcl-eval-region)
    (message "Evaluating contents of region")))

(advice-add 'tcl-eval-region :after
            #'emacsvox--advice-tcl-eval-region-after)

(defun emacsvox--advice-tcl-eval-defun-after (&rest _)
  "Announce what you did"
  (when (ems-interactive-p 'tcl-eval-defun)
    (let*
        ((start nil)
         (proc-line
          (save-excursion
            (beginning-of-defun) (setq start (point))
            (end-of-line) (buffer-substring start (point)))))
      (message "Evaluated  %s" proc-line))))

(advice-add 'tcl-eval-defun :after
            #'emacsvox--advice-tcl-eval-defun-after)

(defun emacsvox--advice-tcl-help-on-word-after (&rest _)
  "Speak  the help."
  (when (ems-interactive-p 'tcl-help-on-word)
    (emacsvox-icon 'help)
    (with-current-buffer "*Tcl help*" (emacsvox-speak-buffer))))

(advice-add 'tcl-help-on-word :after
            #'emacsvox--advice-tcl-help-on-word-after)

;;;   Program structure:

(defun emacsvox--advice-tcl-indent-exp-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p 'tcl-indent-exp)
    (emacsvox-icon 'fill-object)))

(advice-add 'tcl-indent-exp :after
            #'emacsvox--advice-tcl-indent-exp-after)

(defun emacsvox--advice-tcl-indent-line-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'tcl-indent-line)
    (emacsvox-speak-line)))

(advice-add 'tcl-indent-line :after
            #'emacsvox--advice-tcl-indent-line-after)

(provide  'emacsvox-tcl)

;;; emacsvox-tcl.el ends here
