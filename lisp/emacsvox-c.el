;;; emacsvox-c.el --- Speech enable C, C++     -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for C and C++ mode
;; Keywords:emacsvox, audio interface to emacs C, C++
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4637 $ |
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

:

;;; Commentary:

;; Make  C and C++ mode more emacsvox friendly
;; Works with both boring c-mode
;; and the excellent cc-mode

;;; Code:

;;   Required modules:

(require 'emacsvox-preamble)
(declare-function
 c-beginning-of-statement "cc-cmds" (&optional count lim sentence-flag))
(declare-function
 c-end-of-statement "cc-cmds" (&optional count lim sentence-flag))

;;;  advice electric deletion

(defun emacsvox--advice-c-electric-delete-forward-before (&rest _)
  "Speak the following character before an interactive deletion."
  (when (ems-interactive-p 'c-electric-delete-forward)
    (tts-tone-deletion)
    (emacsvox-speak-this-char (following-char))))

(advice-add
 'c-electric-delete-forward :before
 #'emacsvox--advice-c-electric-delete-forward-before
 '((name . emacsvox)))

(defun emacsvox--advice-c-hungry-delete-forward-before (&rest _)
  "Speak the reference character before an interactive hungry deletion."
  (when (ems-interactive-p 'c-hungry-delete-forward)
    (tts-tone-deletion)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add
 'c-hungry-delete-forward :before
 #'emacsvox--advice-c-hungry-delete-forward-before
 '((name . emacsvox)))

(defun emacsvox--advice-c-hungry-delete-backwards-before (&rest _)
  "Speak the preceding character before an interactive hungry deletion."
  (when (ems-interactive-p 'c-hungry-delete-backwards)
    (tts-tone-deletion)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add
 'c-hungry-delete-backwards :before
 #'emacsvox--advice-c-hungry-delete-backwards-before
 '((name . emacsvox)))

(defun emacsvox--advice-c-electric-backspace-before (&rest _)
  "Speak the preceding character before an interactive backspace."
  (when (ems-interactive-p 'c-electric-backspace)
    (tts-tone-deletion)
    (emacsvox-speak-this-char (preceding-char))))

(advice-add
 'c-electric-backspace :before
 #'emacsvox--advice-c-electric-backspace-before
 '((name . emacsvox)))

;;;   advice things to speak
;;;   Electric chars speak

(defun emacsvox--advice-c-electric-semi&comma-after (&rest _)
  "Speak the line when a statement is completed."
  (when (ems-interactive-p 'c-electric-semi&comma)
    (cond ((= last-input-event 44) (tts-speak " comma "))
          (t (emacsvox-speak-line)))))

(advice-add
 'c-electric-semi&comma :after
 #'emacsvox--advice-c-electric-semi&comma-after
 '((name . emacsvox)))

(defun emacsvox--advice-c-electric-delete-before (&rest _)
  "Speak char before deleting it."
  (when (ems-interactive-p 'c-electric-delete)
    (emacsvox-speak-this-char (preceding-char)) (tts-tone-deletion)))

(advice-add
 'c-electric-delete :before
 #'emacsvox--advice-c-electric-delete-before
 '((name . emacsvox)))

;;;   Moving across logical chunks

;; CPP directives:

(cl-loop
 for target in
 '(c-up-conditional c-forward-conditional c-backward-conditional)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive preprocessor movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;; Statements

(cl-loop
 for target in '(c-beginning-of-statement c-end-of-statement)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive statement movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'item)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-c-mark-function-after (&rest _)
  "Provide spoken and auditory feedback."
  (when (ems-interactive-p 'c-mark-function)
    (emacsvox-icon 'mark-object) (emacsvox-speak-line)))

(advice-add
 'c-mark-function :after
 #'emacsvox--advice-c-mark-function-after
 '((name . emacsvox)))

;;;  advice program navigation

(cl-loop
 for target in '(c-beginning-of-defun c-end-of-defun)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive function movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'paragraph)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;   extensions  provided by c++ mode

(defun emacsvox--advice-c-scope-operator-after (&rest _)
  "Speak the scope operator after interactive insertion."
  (when (ems-interactive-p 'c-scope-operator)
    (tts-speak "colon colon")))

(advice-add
 'c-scope-operator :after
 #'emacsvox--advice-c-scope-operator-after
 '((name . emacsvox)))

;;;   Some more navigation functions I define:

(defun c-previous-statement (count)
  "Move to the previous  C statement. "
  (interactive "P")
  (emacsvox-icon 'item)
  (let  ((opoint (point))
         (semantics (c-guess-basic-syntax)))
    ;; skip across a comment
    (cond
     ((or (assq 'c semantics)
          (assq 'comment-intro semantics))
      (while
          (and (or (assq 'c semantics)
                   (assq 'comment-intro semantics))
               (not (eobp))
               (= 0 (forward-line -1)))
        (setq semantics (c-guess-basic-syntax)))
      (skip-syntax-backward " ")
      (emacsvox-speak-line))
     (t (setq count (or count 1))
        (c-beginning-of-statement   count)
        (and (save-match-data (looking-at "{"))
             (skip-syntax-backward " "))
        (if (>= (point) opoint)
            (progn (tts-speak "Cannot move to previous  statement at
this level")
                   (goto-char opoint)
                   (and (sit-for 2)
                        (emacsvox-c-speak-semantics)))
          (emacsvox-speak-line))))))

(defun c-next-statement (count)
  "Move to the next C statement. "
  (interactive "P")
  (emacsvox-icon 'item)
  (let  ((opoint (point))
         (semantics (c-guess-basic-syntax)))
    ;; skip across a comment
    (cond
     ((or (assq 'c semantics)
          (assq 'comment-intro semantics))
      (while
          (and (or (assq 'c semantics)
                   (assq 'comment-intro semantics))
               (not (eobp))
               (= 0 (forward-line 1)))
        (setq semantics (c-guess-basic-syntax)))
      (skip-syntax-forward " ")
      (emacsvox-speak-line))
     (t (setq count (or count 1))
        (c-end-of-statement(1+  count))
        (c-beginning-of-statement  1)
        (and (save-match-data (looking-at "{"))
             (skip-syntax-backward " "))
        (if (<= (point) opoint)
            (progn (tts-speak "Cannot move to next statement at this
level")
                   (goto-char opoint)
                   (and (sit-for 2)
                        (emacsvox-c-speak-semantics)))
          (emacsvox-speak-line))))))

;;;   C semantics

(defvar emacsvox-c-syntactic-table
  (list
   '(string                 . "  inside multi-line string")
   '(c                      . "  inside a multi-line C
style block comment")
   '(catch-clause . "Exception handling construct")
   '(defun-open             . "  brace that opens a function definition")
   '(defun-close            . "  brace that closes a function definition")
   '(defun-block-intro      . "  the first line in a top-level defun")
   '(class-open             . "  brace that opens a class definition")
   '(class-close            . "  brace that closes a class definition")
   '(inline-open            . "  brace that opens an in-class inline method")
   '(inline-close           . "  brace that closes an in-class inline method")
   '(func-decl-cont         . "  the region between a
function definition's argument list and the function opening brace")
   '(knr-argdecl-intro      . "  first line of a K&R C argument declaration")
   '(knr-argdecl            . "  subsequent lines in a K&R
C argument declaration")
   '(inexpr-class . "Anonymous inner class")
   '(topmost-intro          .
                            "  First line in a topmost construct definition")
   '(topmost-intro-cont     . "  topmost definition continuation lines")
   '(member-init-intro      . "  first line in a member initialization list")
   '(member-init-cont       . "  subsequent member initialization list lines")
   '(inher-intro            . "  first line of a multiple inheritance list")
   '(inher-cont             . "  subsequent multiple inheritance lines")
   '(block-open             . "  statement block open brace")
   '(block-close            . "  statement block close brace")
   '(brace-list-open        . "  open brace of an enum or static array list")
   '(brace-list-close       . "  close brace of an enum or
static array list")
   '(brace-entry-open       . "  first line in an enum or static array list")
   '(brace-list-intro       . "  first line in an enum or static array list")
   '(brace-list-entry
     . "  subsequent lines in an enum or static array list")
   '(statement              . "  a C (or like) statement")
   '(statement-cont         . "  a continuation of a C (or like) statement")
   '(statement-block-intro  . "  the first line in a new statement block")
   '(statement-case-intro   . "  the first line in a case block")
   '(statement-case-open
     . "  the first line in a case block starting with brace")
   '(substatement
     . "  the first line after an if/while/for/do/else")
   '(substatement-open      . "  the brace that opens a substatement block")
   '(case-label             . "  a `case' or `default' label")
   '(access-label           . "  C++ private/protected/public access label")
   '(label                  . "  any ordinary label")
   '(do-while-closure       . "  the `while' that ends a do/while construct")
   '(else-clause            . "  the `else' of an if/else construct")
   '(comment-intro          . "  Line containing only a comment introduction")
   '(arglist-intro          . "  the first line in an argument list")
   '(arglist-cont           . "  subsequent argument list lines when no
                           arguments follow on the same line as the
                           arglist opening paren")
   '(arglist-cont-nonempty  . "  subsequent argument list lines when at
                           least one argument follows on the same
                           line as the arglist opening paren")
   '(arglist-close          . "  the solo close paren of an argument list")
   '(stream-op              . "  lines continuing a stream operator construct")
   '(inclass                .
                            "Construct is nested inside a class definition")
   '(cpp-macro              . "  the start of a cpp macro")
   '(friend                 . "  a C++ friend declaration")
   '(objc-method-intro      .
                            "  First line of an Objective-C method definition")
   '(objc-method-args-cont
     . "  lines continuing an Objective-C method definition")
   '(objc-method-call-cont  . "  lines continuing an Objective-C method call")
   '(extern-lang-open       . "  brace that opens an external language block")
   '(extern-lang-close      . "  brace that closes an external language block")
   '(inextern-lang          . "  analogous to `inclass' syntactic symbol")
   '(template-args-cont     . "  C++ template argument list continuations")
   )
  "Association list of semantic symbols defined by cc-mode
and their meanings. ")

(defun emacsvox-c-speak-semantics ()
  "Speak the C semantics of this line. "
  (interactive)
  
  (let  ((semantics (mapcar 'car (c-guess-basic-syntax)))
         (description ""))
    (setq description
          (mapconcat
           #'(lambda (sem)
               (cdr (assq  sem emacsvox-c-syntactic-table)))
           semantics
           " "))
    (condition-case nil
        (cond
         ((or (memq 'block-close semantics)
              (memq 'defun-close semantics)
              (memq 'class-close semantics)
              (memq 'inline-close semantics)
              (memq 'brace-list-close semantics))
          ;; append the line
          (setq description
                (concat description
                        ;; that begins this block
                        (let ((start nil))
                          (save-excursion
                            (forward-line 0)
                            (search-forward "}" nil t)
                            (forward-char 1)
                            (backward-sexp 1)
                            (setq start (point))
                            (forward-line 0)
                            (skip-syntax-forward " ")
                            (and (= start (point))
                                 (forward-line -1)
                                 (forward-line 0))
                            (setq start (point))
                            (end-of-line)
                            (buffer-substring start (point))))))))
      (error nil))
    (tts-speak description)
    description))

;;;   indenting commands

(defun emacsvox--advice-c-indent-defun-after (&rest _)
  "Cue completion after interactively indenting a function."
  (when (ems-interactive-p 'c-indent-defun)
    (emacsvox-icon 'fill-object) (message "Indented function")))

(advice-add
 'c-indent-defun :after
 #'emacsvox--advice-c-indent-defun-after
 '((name . emacsvox)))

(defun emacsvox--advice-c-indent-command-after (&rest _)
  "Speak the line after an interactive indentation command."
  (when (ems-interactive-p 'c-indent-command)
    (emacsvox-speak-line)))

(advice-add
 'c-indent-command :after
 #'emacsvox--advice-c-indent-command-after
 '((name . emacsvox)))

;;;  Additional Interactive Commands:

(cl-loop
 for target in '(c-previous-statement c-next-statement)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive statement navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(with-eval-after-load 'cc-awk
  (cl-loop
   for target in '(c-awk-beginning-of-defun c-awk-end-of-defun)
   for function =
   (intern (format "emacsvox--advice-%s-after" target))
   do
   (eval
    `(progn
       (defun ,function (&rest _)
         "Cue and speak after interactive AWK function movement."
         (when (ems-interactive-p ',target)
           (emacsvox-icon 'large-movement)
           (emacsvox-speak-line)))
       (advice-add
        ',target :after #',function '((name . emacsvox)))))))

(defun emacsvox--advice-c-backslash-region-after (&rest _)
  "Cue and speak the region after interactive backslash insertion."
  (when (ems-interactive-p 'c-backslash-region)
    (emacsvox-icon 'task-done)
    (emacsvox-speak-region (point) (mark))))

(advice-add
 'c-backslash-region :after
 #'emacsvox--advice-c-backslash-region-after
 '((name . emacsvox)))

(cl-loop
 for target in '(c-context-line-break c-context-open-line)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak and cue after an interactive contextual line insertion."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-line)
         (emacsvox-icon 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(c-up-conditional-with-else c-down-conditional-with-else c-down-conditional)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak and cue after interactive conditional movement."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-line)
         (emacsvox-icon 'large-movement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))
(cl-loop
 for target in
 '(
   c-indent-new-comment-line c-indent-line-or-region
   c-indent-exp c-fill-paragraph)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive CC Mode formatting command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'fill-object)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(
   c-toggle-auto-hungry-state c-toggle-auto-newline
   c-toggle-electric-state c-toggle-hungry-state c-toggle-parse-state-debug
   c-toggle-syntactic-indentation)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 for announcement = (symbol-name target)
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and report an interactive CC Mode state toggle."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'button)
         (message "Toggled %s" ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  Additional keybindings:

(cl-declaim (special c-mode-map c-mode-base-map))
(add-hook
 'c-mode-common-hook
 #'(lambda ()
     (cl-declare (special c-mode-map c-mode-base-map
                          outline-regexp))
     (setq outline-regexp "^//< ")
     (define-key c-mode-map "\C-cs" 'emacsvox-c-speak-semantics)
     (define-key c-mode-map "\M-n" 'c-next-statement)
     (define-key c-mode-map "\M-p" 'c-previous-statement)
     (when (and  (boundp 'c-mode-base-map) c-mode-base-map)
       (define-key c-mode-base-map "\C-cs" 'emacsvox-c-speak-semantics)
       (define-key c-mode-base-map "\M-n" 'c-next-statement)
       (define-key c-mode-base-map "\M-p" 'c-previous-statement))))

;;;  personalities

(voice-setup-add-map
 '(
   (c-annotation-face voice-annotate)
   ))

(provide  'emacsvox-c)
