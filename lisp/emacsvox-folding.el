=;;; emacsvox-folding.el --- Speech enable Folding -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for folding-mode
;; Keywords:emacsvox, audio interface to emacs Folding editor
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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
;; Folding mode turns emacs into a folding editor.
;; Folding mode is what I use:
;; emacs 19 comes with similar packages, e.g. allout.el
;; This module defines some advice forms for  folding mode 
;; Think of a fold as a container.
;; 
;;; Code:

;;;  requires
(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Advice

(cl-loop
 for f in
 '(folding-backward-char folding-forward-char)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak char."
     (when (ems-interactive-p)
       (emacsvox-speak-char t)))))


(defun ems--folding-goto-line-after (&rest _)
  "Speak the line. " (when (ems-interactive-p) (emacsvox-speak-line)))


(advice-add 'folding-goto-line :after #'ems--folding-goto-line-after)





(defun ems--folding-mode-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-speak-mode-line)))


(advice-add 'folding-mode :after #'ems--folding-mode-after)




(cl-loop
 for f in
 '(
   folding-context-next-action folding-toggle-show-hide folding-pick-move
   folding-toggle-enter-exit folding-region-open-close
   )do 
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Produce an auditory icon and then speak the line. "
     (when (ems-interactive-p)
       (emacsvox-icon 'button)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(
   folding-hide-current-subtree folding-hide-current-entry
   folding-shift-out folding-whole-buffer)
 do
 (eval
  `(defadvice  ,f (after emacsvox pre act comp)
     "Produce an auditory icon.
Then speak the folded line."
     (when (ems-interactive-p)
       (emacsvox-icon'close-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(
   folding-show-all folding-show-current-entry folding-show-current-subtree
   folding-shift-in folding-open-buffer)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Produce an auditory icon.
Then speak the  line."
     (when (ems-interactive-p)
       (emacsvox-icon'open-object)
       (emacsvox-speak-line)))))


(defun ems--folding-fold-region-after (&rest _)
  "Produce an auditory icon. "
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Specify a meaningful name for the new fold ")))


(advice-add 'folding-fold-region :after
	    #'ems--folding-fold-region-after)




(cl-loop
 for f in 
 '(folding-previous-visible-heading folding-next-visible-heading)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

;;;  Fix keymap:
(add-hook
 'folding-mode-hook
 #'(lambda ()
     
     (when (boundp 'folding-mode-map)
       (define-key
        folding-mode-map (kbd "C-e") 'emacsvox-keymap))))

;;; Diminish:

(when (featurep 'diminish)
  (diminish 'folding-mode ""))

(provide  'emacsvox-folding)

