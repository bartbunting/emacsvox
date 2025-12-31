;;; emacsvox-view.el --- Speech enable View mode - -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for view
;; Keywords:emacsvox, audio interface to emacs, view-mode
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
;; Copyright (c) 1996 by T. V. Raman
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
;; Provide additional advice to view-mode
;;; Code:

;;;  requires
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;   Setup view mode to work with emacsvox

;; restore emacsvox keybindings:
(cl-declaim (special emacsvox-prefix))

(add-hook
 'view-mode-hook
 #'(lambda ()
     (local-unset-key emacsvox-prefix)
     (emacsvox-speak-load-directory-settings)
     (outline-minor-mode 1))
 'at-end)

;;;  Advise additional interactive commands:

(defun ems--view-mode-after (&rest _)
  "Announce what happened" 
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (if view-mode
        (message "Entered view mode Press %s to exit"
                 (key-description
                  (where-is-internal 'View-exit view-mode-map
                                     'firstonly)))
      (message "Exited view mode"))))

(advice-add 'view-mode :after #'ems--view-mode-after)

(cl-loop
 for f in
 '(
   View-exit-and-edit View-kill-and-leave View-quit-all View-quit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'close-object)
       (emacsvox-speak-mode-line)))))

(cl-loop
 for f in
 '(
   view-buffer view-buffer-other-frame view-buffer-other-window
   view-emacs-FAQ view-emacs-debugging ^ view-emacs-problems
   view-emacs-todo view-external-packages
   view-file-other-frame view-file-other-window
   view-hello-file view-lossage ) do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak"
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-mode-line)))))

(cl-loop
 for f in
 '(
   View-search-regexp-forward View-search-regexp-backward
   View-search-last-regexp-backward View-search-last-regexp-forward
   ) do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak"
     (when (ems-interactive-p)
       (let ((emacsvox-show-point t))
         (emacsvox-speak-line))
       (emacsvox-icon 'search-hit)))))

(cl-loop
 for f in
 '(
   View-scroll-half-page-backward View-scroll-half-page-forward
   View-scroll-line-backward View-scroll-line-forward
   View-scroll-lines-forward-set-scroll-size View-scroll-one-more-line
   View-scroll-page-backward view-scroll-page-forward 
   View-scroll-page-backward-set-page-size View-scroll-page-forward-set-page-size
   ) do
 `(eval
   (defadvice ,f (after emacsvox pre act comp)
     "speak"
     (when (ems-interactive-p)
       (emacsvox-icon 'scroll)
       (emacsvox-speak-windowful)))))

(defun ems--View-back-to-mark-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))))

(advice-add 'View-back-to-mark :after #'ems--View-back-to-mark-after)

(defun ems--View-goto-line-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (let ((line-number (format "line %s" (ad-get-arg 0))))
      (put-text-property 0 (length line-number) 'personality
                         voice-annotate line-number)
      (emacsvox-icon 'large-movement)
      (dtk-speak (concat line-number (ems--this-line))))))

(advice-add 'View-goto-line :after #'ems--View-goto-line-after)

(defun ems--View-scroll-to-buffer-end-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'large-movement)))

(advice-add 'View-scroll-to-buffer-end :after
            #'ems--View-scroll-to-buffer-end-after)

(defun ems--View-goto-percent-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll)
    (dtk-speak (emacsvox-get-window-contents))))

(advice-add 'View-goto-percent :after #'ems--View-goto-percent-after)

;;;  bind convenience keys

(defun emacsvox-view-setup-keys()
  "Setup emacsvox convenience keys"
  
  (cl-loop
   for  b in
   '(
     ("," 'emacsvox-speak-current-window)
     ("C-j" 'emacsvox-hide-speak-block-sans-prefix)
     ("M-d" 'emacsvox-pronounce-dispatch)
     ("M-n" 'outline-next-visible-heading)
     ("M-p" 'outline-previous-visible-heading)
     ("SPC" 'scroll-up)
     ("[" 'backward-page)
     ("]" 'forward-page)
     ("b" backward-word)
     ("c" 'emacsvox-speak-char)
     ("d" 'scroll-down)
     ("f" forward-word)
     ("h" left-char)
     ("j" next-line)
     ("k" previous-line)
     ("l" right-char)
     ("w" emacsvox-speak-word)
     )
   do
   (emacsvox-keymap-update view-mode-map b))
  (cl-loop
   for i from 0 to 9
   do
   (define-key view-mode-map (format "%s" i) 'dtk-set-predefined-rate)))

(emacsvox-view-setup-keys)

(provide  'emacsvox-view)
