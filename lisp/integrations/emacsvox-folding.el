;;; emacsvox-folding.el --- Speech enable Folding -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs Folding editor
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
;; Folding mode turns emacs into a folding editor.
;; Folding mode is what I use:
;; emacs 19 comes with similar packages, e.g. allout.el
;; This module defines some advice forms for  folding mode 
;; Think of a fold as a container.
;; 
;;; Code:

;;;  requires
(require 'cl-lib)
(require 'emacsvox-preamble)

;;;  Advice

(defconst emacsvox-folding--character-targets
  '(folding-backward-char folding-forward-char)
  "Folding commands that announce the destination character.")

(cl-loop
 for target in emacsvox-folding--character-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak the destination character."
     (when (ems-interactive-p ',target)
       (emacsvox-speak-char t)))))

(defun emacsvox--advice-folding-goto-line-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p 'folding-goto-line)
    (emacsvox-speak-line)))

(defun emacsvox--advice-folding-mode-after (&rest _)
  "Speak"
  (when (ems-interactive-p 'folding-mode)
    (emacsvox-icon 'button) (emacsvox-speak-mode-line)))

(defconst emacsvox-folding--toggle-targets
  '(folding-context-next-action
    folding-toggle-show-hide
    folding-pick-move
    folding-toggle-enter-exit
    folding-region-open-close)
  "Folding commands that toggle the current fold.")

(cl-loop
 for target in emacsvox-folding--toggle-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Produce an auditory icon and then speak the line. "
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'button)
       (emacsvox-speak-line)))))

(defconst emacsvox-folding--close-targets
  '(folding-hide-current-subtree
    folding-hide-current-entry
    folding-shift-out
    folding-whole-buffer)
  "Folding commands that close folds.")

(cl-loop
 for target in emacsvox-folding--close-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Produce an auditory icon.
Then speak the folded line."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'close-object)
       (emacsvox-speak-line)))))

(defconst emacsvox-folding--open-targets
  '(folding-show-all
    folding-show-current-entry
    folding-show-current-subtree
    folding-shift-in
    folding-open-buffer)
  "Folding commands that open folds.")

(cl-loop
 for target in emacsvox-folding--open-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Produce an auditory icon.
Then speak the  line."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(defun emacsvox--advice-folding-fold-region-after (&rest _)
  "Produce an auditory icon. "
  (when (ems-interactive-p 'folding-fold-region)
    (emacsvox-icon 'open-object)
    (message "Specify a meaningful name for the new fold ")))

(defconst emacsvox-folding--heading-targets
  '(folding-previous-visible-heading folding-next-visible-heading)
  "Folding commands that move between visible headings.")

(cl-loop
 for target in emacsvox-folding--heading-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(defconst emacsvox-folding--advice-targets
  (append
   emacsvox-folding--character-targets
   '(folding-goto-line folding-mode)
   emacsvox-folding--toggle-targets
   emacsvox-folding--close-targets
   emacsvox-folding--open-targets
   '(folding-fold-region)
   emacsvox-folding--heading-targets)
  "Current Folding targets that receive native after advice.")

(defun emacsvox-folding--install-advice ()
  "Install advice after the optional Folding package loads."
  (dolist (target emacsvox-folding--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'folding
  (emacsvox-folding--install-advice))

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

;;; emacsvox-folding.el ends here
