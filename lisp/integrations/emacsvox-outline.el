;;; emacsvox-outline.el --- Speech enable Outline -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs Outlines
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

;; Provide additional advice to outline-mode

;;; Code:

;;; Forward variable declarations:

(defvar outline-mode-prefix-map)
(defvar outline-navigation-repeat-map)

;;;  requires

(require 'emacsvox-preamble)
(require 'outline)

;;; Emacsvox source setup:

(defun emacsvox-outline--enable-for-source ()
  "Enable Outline minor mode in Emacsvox Emacs Lisp source buffers."
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (file-in-directory-p buffer-file-name emacsvox-directory))
    (outline-minor-mode 1)))

(add-hook 'emacs-lisp-mode-hook #'emacsvox-outline--enable-for-source)

;;;   Navigating through an outline:

(cl-loop
 for target in
 '(
   outline-next-heading outline-previous-heading outline-next-preface
   outline-next-visible-heading outline-previous-visible-heading
   outline-back-to-heading outline-up-heading
   outline-backward-same-level outline-forward-same-level)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Outline navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'section)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;; outline-flag-region:

;; Handle outline hide/show directly here --- rather than relying on
;;overlay advice alone.

(defvar ems--voiceify-overlays)

(defun emacsvox--advice-outline-flag-region-around
    (original from to flag)
  "Call ORIGINAL, then mirror FLAG as invisibility between FROM and TO."
  (let ((ems--voiceify-overlays nil)
        (beginning from)
        (inhibit-read-only t))
    (let ((result (funcall original from to flag)))
      ;; Outline accepts zero as a sentinel, but text properties do not.
      (when (zerop beginning)
        (setq beginning (point-min)))
      (with-silent-modifications
        (put-text-property
         beginning to 'invisible (and flag 'outline)))
      result)))

(advice-add
 'outline-flag-region :around
 #'emacsvox--advice-outline-flag-region-around
 '((name . emacsvox)))

;;; Misc Commands:

(cl-loop
 for target in
 '(outline-insert-heading outline-cycle-buffer outline-cycle)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Outline visibility change."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;   Hiding and showing subtrees

(cl-loop
 for (target icon announcement) in
 '((outline-show-only-headings
    close-object "Hid the body directly following this heading")
   (outline-hide-entry
    close-object "Hid the body directly following this heading")
   (outline-show-entry
    open-object "Exposed body directly following current heading")
   (outline-hide-body
    close-object "Hid all of the buffer except for header lines")
   (outline-show-all
    open-object "Exposed all text in the buffer")
   (outline-hide-subtree
    close-object "Hid everything at deeper levels from current heading")
   (outline-hide-leaves
    close-object "Hid all of the body at deeper levels")
   (outline-show-subtree
    open-object
    "Exposed everything after current heading at deeper levels")
   (outline-hide-other
    close-object
    "Hid everything except current body and parent headings")
   (outline-show-branches
    open-object
    "Exposed all subheadings while leaving their bodies hidden")
   (outline-show-children
    open-object "Exposed subheadings below current level"))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and announce an interactive Outline visibility change."
       (when (ems-interactive-p ',target)
         (emacsvox-icon ',icon)
         (message ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-outline-hide-sublevels-after (levels &rest _)
  "Cue and announce hiding all but the top LEVELS."
  (when (ems-interactive-p 'outline-hide-sublevels)
    (emacsvox-icon 'close-object)
    (message "Hid everything except the top  %s levels" levels)))

(advice-add
 'outline-hide-sublevels :after
 #'emacsvox--advice-outline-hide-sublevels-after
 '((name . emacsvox)))

;;;   Interactive speaking of sections

(defvar emacsvox-outline-dont-query-before-speaking t
  "Option to control prompts when speaking  outline sections.")

(defun emacsvox-outline-speak-heading (what direction)
  "Function used by all interactive section speaking
commands. "
  
  (let ((start nil)
        (end nil))
    (funcall what  direction)
    (setq start (point))
    (save-excursion
      (condition-case nil
          (progn
            (forward-line 1)
            (funcall what 1)
            (setq end (point)))
        (error (setq end (point-max)))))
    (when (or  emacsvox-outline-dont-query-before-speaking
               (y-or-n-p
                (format  "Speak %s lines from section %s"
                         (count-lines start end) (ems--this-line))))
      (emacsvox-speak-region start end))))

(defun emacsvox-outline-speak-next-heading ()
  "Analogous to outline-next-visible-heading,
except that the outline section is  spoken"
  (interactive)
  (emacsvox-icon 'section)
  (emacsvox-outline-speak-heading 'outline-next-visible-heading 1))

(defun emacsvox-outline-speak-previous-heading ()
  "Analogous to outline-previous-visible-heading,
except that the outline section is  spoken"
  (interactive)
  (emacsvox-icon 'section)
  (emacsvox-outline-speak-heading 'outline-next-visible-heading -1))

(defun emacsvox-outline-speak-forward-heading ()
  "Analogous to outline-forward-same-level,
except that the outline section is  spoken"
  (interactive)
  (emacsvox-icon 'section)
  (emacsvox-outline-speak-heading 'outline-forward-same-level 1))

(defun emacsvox-outline-speak-backward-heading ()
  "Analogous to outline-backward-same-level
except that the outline section is  spoken"
  (interactive)
  (emacsvox-icon 'section)
  (forward-line -1)
  (emacsvox-outline-speak-heading 'outline-forward-same-level -1))

(defun emacsvox-outline-speak-this-heading ()
  "Speak current outline section starting from point"
  (interactive)
  (emacsvox-icon 'select-object)
  (let ((start (point))
        (end nil))
    (save-excursion
      (condition-case nil
          (progn
            (outline-next-visible-heading 1)
            (setq end (point)))
        (error (setq end (point-max)))))
    (and
     (or emacsvox-outline-dont-query-before-speaking
         (y-or-n-p
          (format "Speak %s lines from section %s"
                  (count-lines start end) (ems--this-line))))
     (emacsvox-speak-region start end))))

;;;  bind these in outline mode

(defun emacsvox-outline-setup-keys ()
  "Bind keys in outline minor mode map"
  (cl-loop
   for map in
   (if (and (bound-and-true-p outline-navigation-repeat-map)
            (keymapp outline-navigation-repeat-map))
       (list outline-mode-prefix-map outline-navigation-repeat-map)
     (list outline-mode-prefix-map ))
   do
   (define-key map "j" 'outline-next-visible-heading)
   (define-key map "k" 'outline-previous-visible-heading)
   (define-key map "p" 'emacsvox-outline-speak-previous-heading)
   (define-key map "n" 'emacsvox-outline-speak-next-heading)
   (define-key map "b" 'emacsvox-outline-speak-backward-heading)
   (define-key map "f" 'emacsvox-outline-speak-forward-heading)
   (define-key map " " 'emacsvox-outline-speak-this-heading))
  
  (mapc
   #'(lambda (cmd)
       (put cmd 'repeat-map 'outline-navigation-repeat-map))
   '(emacsvox-outline-speak-next-heading
     emacsvox-outline-speak-backward-heading
     emacsvox-outline-speak-forward-heading
     emacsvox-outline-speak-this-heading)))

(add-hook 'outline-mode-hook 'emacsvox-outline-setup-keys)
(add-hook 'outline-minor-mode-hook 'emacsvox-outline-setup-keys)

;;;  Personalities (
(voice-setup-add-map
 '(
   (outline-1 voice-bolden)
   (outline-2 voice-brighten)
   (outline-3 voice-lighten)
   (outline-4 voice-smoothen)
   (outline-5 voice-monotone)
   (outline-6 voice-lighten-medium)
   ))

;;;  silence errors to help org-mode:

;;;  foldout specific advice

(defun emacsvox--advice-foldout-zoom-subtree-after (&rest _)
  "Cue and describe an interactively zoomed Foldout subtree."
  (when (ems-interactive-p 'foldout-zoom-subtree)
    (emacsvox-icon 'open-object)
    (message
     "Zoomed into outline %s containing %s lines"
     (ems--this-line) (count-lines (point-min) (point-max)))))

(defun emacsvox--advice-foldout-exit-fold-after (&rest _)
  "Cue and speak after interactively exiting a Foldout fold."
  (when (ems-interactive-p 'foldout-exit-fold)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-line)))

(with-eval-after-load "foldout"
  (advice-add
   'foldout-zoom-subtree :after
   #'emacsvox--advice-foldout-zoom-subtree-after
   '((name . emacsvox)))
  (advice-add
   'foldout-exit-fold :after
   #'emacsvox--advice-foldout-exit-fold-after
   '((name . emacsvox))))

(provide  'emacsvox-outline)

;;; emacsvox-outline.el ends here
