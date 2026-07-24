;;; emacsvox-auctex.el --- Speech enable AucTeX -- -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for auctex-mode
;; Keywords:emacsvox, audio interface to emacs AUCTEX
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

;;  Required modules:  
(require 'emacsvox-preamble)

;;; Commentary:
;; Speech-enables the AucTeX package.  AucTeX, now available from
;; ELPA, has been my authoring environment of choice for writing LaTeX
;; since 1991.
;;; Code:

;;; Forward variable declarations:

(defvar imenu-create-index-function)
(defvar imenu-generic-expression)

;;;  voice locking:

;; faces from AUCTeX 11
(voice-setup-add-map
 '(
   (font-latex-bold-face voice-bolden)
   (font-latex-doctex-documentation-face voice-monotone-medium)
   (font-latex-doctex-preprocessor-face voice-brighten-medium)
   (font-latex-italic-face voice-animate)
   (font-latex-math-face voice-brighten-extra)
   (font-latex-sedate-face voice-smoothen)
   (font-latex-string-face voice-lighten)
   (font-latex-subscript-face voice-smoothen)
   (font-latex-superscript-face voice-brighten)
   (font-latex-verbatim-face voice-monotone-extra)
   (font-latex-warning-face voice-bolden-and-animate)
   ))

;;;   Marking structured objects:

(defvar emacsvox-auctex--advice nil
  "Current AUCTeX targets and their native advice functions.")

(defun emacsvox--advice-LaTeX-fill-paragraph-after (&rest _)
  "speak."
  (when (ems-interactive-p 'LaTeX-fill-paragraph)
    (emacsvox-icon 'fill-object)))

(defun emacsvox--advice-LaTeX-mark-section-after (&rest _)
  "Speak the first line. \nAlso provide an auditory icon. "
  (when (ems-interactive-p 'LaTeX-mark-section)
    (emacsvox-speak-line) (emacsvox-icon 'mark-object)))

(defun emacsvox--advice-LaTeX-mark-environment-after (&rest _)
  "Speak the first line. \nAlso provide an auditory icon. "
  (when (ems-interactive-p 'LaTeX-mark-environment)
    (emacsvox-speak-line) (emacsvox-icon 'mark-object)))

;;;   delimiter matching:

(defun emacsvox--advice-LaTeX-find-matching-begin-after (&rest _)
  "speak."
  (when (ems-interactive-p 'LaTeX-find-matching-begin)
    (emacsvox-speak-line)))

(defun emacsvox--advice-LaTeX-find-matching-end-after (&rest _)
  "speak."
  (when (ems-interactive-p 'LaTeX-find-matching-end)
    (emacsvox-speak-line)))

(defun emacsvox--advice-LaTeX-close-environment-after (&rest _)
  "Speak the inserted line. "
  (when (ems-interactive-p 'LaTeX-close-environment)
    (emacsvox-icon 'close-object) (emacsvox-read-previous-line)))

(cl-loop
 for target in
 '(TeX-insert-dollar TeX-insert-quote)
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Speak quotes that were inserted."
     (let ((origin (point))
           (result (apply original arguments)))
       (when (ems-interactive-p ',target)
         (emacsvox-speak-region origin (point)))
       result)))
 (push (list target :around advice-function) emacsvox-auctex--advice))

;;;   Inserting structures

(defun emacsvox--advice-TeX-newline-after (&rest _)
  "speak to indicate indentation."
  (when (ems-interactive-p 'TeX-newline)
    (emacsvox-speak-line)))

(defun emacsvox--advice-LaTeX-insert-item-after (&rest _)
  "speak."
  (when (ems-interactive-p 'LaTeX-insert-item)
    (emacsvox-speak-line)))

(defun emacsvox--advice-LaTeX-environment-after (&rest _)
  "speak, by speaking\nthe opening line of the newly inserted environment. "
  (when (ems-interactive-p 'LaTeX-environment)
    (emacsvox-icon 'open-object) (emacsvox-read-previous-line)))

(defun emacsvox--advice-TeX-insert-macro-around (orig-fun &rest args)
  "Speak."
  (let ((origin (point))
        (result (apply orig-fun args)))
    (emacsvox-speak-region origin (point))
    result))

;;;   Commenting chunks:

(defun emacsvox--advice-TeX-comment-or-uncomment-paragraph-after (&rest _)
  "Provide spoken and auditory feedback. "
  (when (ems-interactive-p 'TeX-comment-or-uncomment-paragraph)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

;;;   Debugging tex

(defun emacsvox--advice-TeX-next-error-after (&rest _)
  "Speak the error line. "
  (when (ems-interactive-p 'TeX-next-error)
    (emacsvox-icon 'item) (emacsvox-speak-line)))

;;;   Hooks

;; We add imenu settings to LaTeX-mode-hook

(add-hook  'LaTeX-mode-hook
           #'(lambda ()
               (require 'imenu)
               (setq imenu-create-index-function
                     'imenu-default-create-index-function)
               (setq imenu-generic-expression
                     '(
                       (nil
                        "^ *\\\\\\(sub\\)*section{\\([^}]+\\)"
                        2)))))

;;;  advice font changes 

(defun emacsvox--advice-TeX-font-around (orig-fun replace what)
  "Speak the font we inserted"
  (let ((origin (point))
        (result (funcall orig-fun replace what)))
    (when (ems-interactive-p 'TeX-font)
      (if replace
          (emacsvox-speak-line)
        (emacsvox-speak-region origin (point))))
    result))

(dolist
    (entry
     '((LaTeX-fill-paragraph :after
        emacsvox--advice-LaTeX-fill-paragraph-after)
       (LaTeX-mark-section :after
        emacsvox--advice-LaTeX-mark-section-after)
       (LaTeX-mark-environment :after
        emacsvox--advice-LaTeX-mark-environment-after)
       (LaTeX-find-matching-begin :after
        emacsvox--advice-LaTeX-find-matching-begin-after)
       (LaTeX-find-matching-end :after
        emacsvox--advice-LaTeX-find-matching-end-after)
       (LaTeX-close-environment :after
        emacsvox--advice-LaTeX-close-environment-after)
       (TeX-newline :after emacsvox--advice-TeX-newline-after)
       (LaTeX-insert-item :after
        emacsvox--advice-LaTeX-insert-item-after)
       (LaTeX-environment :after
        emacsvox--advice-LaTeX-environment-after)
       (TeX-insert-macro :around
        emacsvox--advice-TeX-insert-macro-around)
       (TeX-comment-or-uncomment-paragraph :after
        emacsvox--advice-TeX-comment-or-uncomment-paragraph-after)
       (TeX-next-error :after emacsvox--advice-TeX-next-error-after)
       (TeX-font :around emacsvox--advice-TeX-font-around)))
  (push entry emacsvox-auctex--advice))

(defun emacsvox-auctex--install-advice ()
  "Install advice for functions present in current AUCTeX."
  (dolist (entry emacsvox-auctex--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(tex latex))
  (eval-after-load feature #'emacsvox-auctex--install-advice))

;;;  tex utils:

(defun emacsvox-auctex-end-of-word (arg)
  "move to end of word"
  (interactive "P")
  (if arg
      (forward-word arg)
    (forward-word 1)))

(defun emacsvox-auctex-comma-at-end-of-word ()
  "Move to the end of current word and add a comma."
  (interactive)
  (forward-word 1)
  (insert-char ?,))

(defun emacsvox-auctex-lacheck-buffer-file ()
  "Run Lacheck on current buffer."
  (interactive)
  (compile (format "lacheck %s"
                   (buffer-file-name (current-buffer)))))

(defun emacsvox-auctex-tex-tie-current-word (n)
  "Tie the next n  words."
  (interactive "P")
  (or n (setq n 1))
  (while
      (> n 0)
    (setq n (- n 1))
    (forward-word 1)
    (delete-horizontal-space)
    (insert-char 126 1))
  (forward-word 1))

(provide  'emacsvox-auctex)
